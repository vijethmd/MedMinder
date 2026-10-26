import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'theme.dart';

// Everything here is stored on the phone only (SQLite + shared preferences).

// ========== DOSE SLOTS ==========
// A medicine can be taken up to three times a day, each tied to a meal
class DoseSlot {
  final String label;
  final String mealKey; // shared preferences key prefix
  final String mealName;
  final int defaultHour;
  final IconData icon;
  final Color color;

  const DoseSlot({
    required this.label,
    required this.mealKey,
    required this.mealName,
    required this.defaultHour,
    required this.icon,
    required this.color,
  });
}

const List<DoseSlot> doseSlots = [
  DoseSlot(
    label: 'Morning',
    mealKey: 'breakfast',
    mealName: 'Breakfast',
    defaultHour: 8,
    icon: Icons.wb_twilight_rounded,
    color: AppColors.morning,
  ),
  DoseSlot(
    label: 'Afternoon',
    mealKey: 'lunch',
    mealName: 'Lunch',
    defaultHour: 13,
    icon: Icons.wb_sunny_rounded,
    color: AppColors.afternoon,
  ),
  DoseSlot(
    label: 'Night',
    mealKey: 'dinner',
    mealName: 'Dinner',
    defaultHour: 20,
    icon: Icons.nightlight_round,
    color: AppColors.night,
  ),
];

// ========== SESSIONS ==========
// Medicines due at the same time (same meal, same before/after food) are
// reminded together in one notification
class Session {
  final int slot;
  final bool afterFood;

  const Session(this.slot, this.afterFood);

  factory Session.fromIndex(int index) => Session(index ~/ 2, index.isOdd);

  int get index => slot * 2 + (afterFood ? 1 : 0); // 0..5
  DoseSlot get doseSlot => doseSlots[slot];

  // "Morning medicines", "before breakfast"
  String get title => '${doseSlot.label} medicines';
  String get whenText => '${afterFood ? 'after' : 'before'} ${doseSlot.mealName.toLowerCase()}';

  bool includes(Medicine med) => med.doses[slot] > 0 && med.afterFood == afterFood;

  @override
  bool operator ==(Object other) => other is Session && other.index == index;

  @override
  int get hashCode => index;
}

final List<Session> allSessions = [for (int i = 0; i < 6; i++) Session.fromIndex(i)];

// ========== DATES ==========
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dateOnly(DateTime.now());
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

// Whole days from a to b (safe across daylight-saving changes)
int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

String dbDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime? parseDbDate(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

// e.g. "Today, Mon 26 Oct" / "Wed 28 Oct 2026"
String friendlyDate(DateTime d) {
  final diff = daysBetween(today(), d);
  if (diff == 0) return 'Today, ${DateFormat('EEE d MMM').format(d)}';
  if (diff == 1) return 'Tomorrow, ${DateFormat('EEE d MMM').format(d)}';
  if (diff == -1) return 'Yesterday, ${DateFormat('EEE d MMM').format(d)}';
  return DateFormat('EEE d MMM yyyy').format(d);
}

// e.g. "today at 7:40 AM" / "Wednesday 28 October at 7:40 AM"
String describeWhen(DateTime t) {
  final time = DateFormat.jm().format(t);
  final diff = daysBetween(today(), t);
  if (diff == 0) return 'today at $time';
  if (diff == 1) return 'tomorrow at $time';
  return '${DateFormat('EEEE d MMMM').format(t)} at $time';
}

// ========== MEDICINE ==========
class Medicine {
  final int? id;
  final String name;
  final List<int> doses; // how many to take: morning, afternoon, night (0 = none)
  final bool afterFood;
  final DateTime startDate;
  final DateTime? endDate; // null = no end date
  final DateTime? createdAt; // doses before this moment aren't expected

  const Medicine({
    this.id,
    required this.name,
    required this.doses,
    required this.afterFood,
    required this.startDate,
    this.endDate,
    this.createdAt,
  });

  factory Medicine.fromMap(Map<String, dynamic> map) {
    final doses = (map['pattern'] as String? ?? '')
        .split('-')
        .map((d) => int.tryParse(d) ?? 0)
        .toList();
    while (doses.length < doseSlots.length) {
      doses.add(0);
    }
    return Medicine(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      doses: doses.take(doseSlots.length).toList(),
      afterFood: map['relation'] == 'After Food',
      startDate: parseDbDate(map['start_date']) ?? today(),
      endDate: parseDbDate(map['end_date']),
      createdAt: map['created_at'] == null ? null : DateTime.tryParse(map['created_at'] as String),
    );
  }

  // Same columns as before ("1-0-1", "After Food") so old data keeps working
  Map<String, dynamic> toMap() => {
        'name': name,
        'pattern': doses.join('-'),
        'relation': afterFood ? 'After Food' : 'Before Food',
        'start_date': dbDate(startDate),
        'end_date': endDate == null ? null : dbDate(endDate!),
      };

  Medicine withId(int newId) => Medicine(
        id: newId,
        name: name,
        doses: doses,
        afterFood: afterFood,
        startDate: startDate,
        endDate: endDate,
        createdAt: createdAt ?? DateTime.now(),
      );

  bool isActiveOn(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(startDate) && (endDate == null || !d.isAfter(endDate!));
  }

  // Due at this exact time? (A medicine added at 11 PM isn't "missed" at 8 PM)
  bool isDueAt(DateTime when) =>
      isActiveOn(when) && (createdAt == null || !when.isBefore(createdAt!));

  bool get isFinished => endDate != null && today().isAfter(endDate!);
  bool get notStartedYet => today().isBefore(startDate);
}

// ========== DATABASE HELPER ==========
class DBHelper {
  static Database? _db;

  static Future<Database> db() async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'medications.db'),
      version: 4,
      onCreate: (db, version) async {
        await db.execute(
          '''
          CREATE TABLE medications(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            pattern TEXT,
            relation TEXT,
            start_date TEXT,
            end_date TEXT,
            created_at TEXT
          )
          ''',
        );
        await _createV3Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 2 added course dates; existing medicines start today and never end
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE medications ADD COLUMN start_date TEXT');
          await db.execute('ALTER TABLE medications ADD COLUMN end_date TEXT');
          await db.update('medications', {'start_date': dbDate(today())});
        }
        // Version 3 added the taken log and weekly reports
        if (oldVersion < 3) await _createV3Tables(db);
        // Version 4 remembers when each medicine was added
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE medications ADD COLUMN created_at TEXT');
        }
      },
    );
  }

  static Future<void> _createV3Tables(Database db) async {
    // One row per medicine, per dose, per day; taken_at is empty until taken
    await db.execute(
      '''
      CREATE TABLE dose_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        med_id INTEGER,
        med_name TEXT,
        date TEXT,
        slot INTEGER,
        after_food INTEGER,
        amount INTEGER,
        taken_at TEXT,
        UNIQUE(med_id, date, slot)
      )
      ''',
    );
    await db.execute(
      '''
      CREATE TABLE weekly_reports(
        week_start TEXT PRIMARY KEY,
        expected INTEGER,
        taken INTEGER,
        details TEXT
      )
      ''',
    );
  }

  static Future<List<Medicine>> getMedicines() async {
    final db = await DBHelper.db();
    final rows = await db.query('medications', orderBy: 'name COLLATE NOCASE');
    return rows.map(Medicine.fromMap).toList();
  }

  static Future<int> insert(Medicine medicine) async {
    final db = await DBHelper.db();
    return db.insert('medications', {
      ...medicine.toMap(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> update(Medicine medicine) async {
    final db = await DBHelper.db();
    await db.update('medications', medicine.toMap(),
        where: 'id = ?', whereArgs: [medicine.id]);
  }

  static Future<void> delete(int id) async {
    final db = await DBHelper.db();
    await db.delete('medications', where: 'id = ?', whereArgs: [id]);
  }
}

// ========== TAKEN LOG ==========
class DoseEntry {
  final int medId;
  final String medName;
  final DateTime date;
  final int slot;
  final bool afterFood;
  final int amount;
  final DateTime? takenAt;

  const DoseEntry({
    required this.medId,
    required this.medName,
    required this.date,
    required this.slot,
    required this.afterFood,
    required this.amount,
    this.takenAt,
  });

  factory DoseEntry.fromMap(Map<String, dynamic> map) => DoseEntry(
        medId: map['med_id'] as int,
        medName: map['med_name'] as String? ?? '',
        date: parseDbDate(map['date'])!,
        slot: map['slot'] as int,
        afterFood: map['after_food'] == 1,
        amount: map['amount'] as int? ?? 1,
        takenAt: map['taken_at'] == null ? null : DateTime.tryParse(map['taken_at'] as String),
      );

  bool get isTaken => takenAt != null;
  Session get session => Session(slot, afterFood);
}

class DoseLog {
  // Add a "due" row for every dose on [day] (rows already there are kept)
  static Future<void> ensureDay(
      DateTime day, List<Medicine> medicines, SharedPreferences prefs) async {
    final db = await DBHelper.db();
    final batch = db.batch();
    for (final med in medicines) {
      if (med.id == null) continue;
      for (int slot = 0; slot < doseSlots.length; slot++) {
        if (med.doses[slot] <= 0) continue;
        final time = reminderTimeOfDay(prefs, doseSlots[slot], med.afterFood);
        if (!med.isDueAt(atTime(day, time))) continue;
        batch.insert(
          'dose_log',
          {
            'med_id': med.id,
            'med_name': med.name,
            'date': dbDate(day),
            'slot': slot,
            'after_food': med.afterFood ? 1 : 0,
            'amount': med.doses[slot],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  // Fill in days since the log was last updated, then today.
  // Days before the log started are never filled, so old history isn't invented.
  static Future<void> catchUp(List<Medicine> medicines, SharedPreferences prefs) async {
    final now = today();
    final startedOn = Settings.logStartedOn(prefs);
    if (startedOn == null) await Settings.setLogStartedOn(prefs, now);

    final filledUntil = Settings.logFilledUntil(prefs);
    var day = filledUntil == null ? now : addDays(filledUntil, 1);
    if (daysBetween(day, now) > 13) day = addDays(now, -13);
    while (!day.isAfter(now)) {
      await ensureDay(day, medicines, prefs);
      day = addDays(day, 1);
    }
    await Settings.setLogFilledUntil(prefs, now);
  }

  static Future<List<DoseEntry>> between(DateTime from, DateTime to) async {
    final db = await DBHelper.db();
    final rows = await db.query(
      'dose_log',
      where: 'date >= ? AND date <= ?',
      whereArgs: [dbDate(from), dbDate(to)],
      orderBy: 'date, slot, med_name COLLATE NOCASE',
    );
    return rows.map(DoseEntry.fromMap).toList();
  }

  static Future<List<DoseEntry>> forDay(DateTime day) => between(day, day);

  // Add one dose row even if it wasn't expected (e.g. ticked on the day the
  // medicine was added, after its time had passed)
  static Future<void> addDose(Medicine med, DateTime day, int slot) async {
    final db = await DBHelper.db();
    await db.insert(
      'dose_log',
      {
        'med_id': med.id,
        'med_name': med.name,
        'date': dbDate(day),
        'slot': slot,
        'after_food': med.afterFood ? 1 : 0,
        'amount': med.doses[slot],
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> removeDose(int medId, DateTime day, int slot) async {
    final db = await DBHelper.db();
    await db.delete(
      'dose_log',
      where: 'med_id = ? AND date = ? AND slot = ?',
      whereArgs: [medId, dbDate(day), slot],
    );
  }

  static Future<void> setTaken(int medId, DateTime day, int slot, bool taken) async {
    final db = await DBHelper.db();
    await db.update(
      'dose_log',
      {'taken_at': taken ? DateTime.now().toIso8601String() : null},
      where: 'med_id = ? AND date = ? AND slot = ?',
      whereArgs: [medId, dbDate(day), slot],
    );
  }

  // Everything in one session (e.g. the "Taken" button on a notification)
  static Future<void> setSessionTaken(Session session, DateTime day) async {
    final db = await DBHelper.db();
    await db.update(
      'dose_log',
      {'taken_at': DateTime.now().toIso8601String()},
      where: 'date = ? AND slot = ? AND after_food = ? AND taken_at IS NULL',
      whereArgs: [dbDate(day), session.slot, session.afterFood ? 1 : 0],
    );
  }

  // After editing or deleting a medicine: forget its not-yet-taken doses
  // from [day] on (taken ones stay for the reports)
  static Future<void> clearPendingFrom(int medId, DateTime day) async {
    final db = await DBHelper.db();
    await db.delete(
      'dose_log',
      where: 'med_id = ? AND date >= ? AND taken_at IS NULL',
      whereArgs: [medId, dbDate(day)],
    );
  }
}

// ========== WEEKLY REPORTS ==========
class MedicineTally {
  final String name;
  int expected;
  int taken;

  MedicineTally(this.name, {this.expected = 0, this.taken = 0});

  int get percent => expected == 0 ? 0 : (taken * 100 / expected).round();

  Map<String, dynamic> toJson() => {'name': name, 'expected': expected, 'taken': taken};

  factory MedicineTally.fromJson(Map<String, dynamic> json) => MedicineTally(
        json['name'] as String,
        expected: json['expected'] as int,
        taken: json['taken'] as int,
      );
}

class WeekSummary {
  final DateTime weekStart;
  final int expected;
  final int taken;
  final List<MedicineTally> medicines;

  const WeekSummary(this.weekStart, this.expected, this.taken, this.medicines);

  int get percent => expected == 0 ? 0 : (taken * 100 / expected).round();
  DateTime get weekEnd => addDays(weekStart, 6);

  // Count doses; [counts] can skip ones that aren't due yet
  factory WeekSummary.fromEntries(DateTime weekStart, Iterable<DoseEntry> entries) {
    final byName = <String, MedicineTally>{};
    for (final e in entries) {
      final tally = byName.putIfAbsent(e.medName, () => MedicineTally(e.medName));
      tally.expected++;
      if (e.isTaken) tally.taken++;
    }
    final list = byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return WeekSummary(
      weekStart,
      list.fold(0, (sum, t) => sum + t.expected),
      list.fold(0, (sum, t) => sum + t.taken),
      list,
    );
  }
}

class Reports {
  // Build and store the report for the week starting on [weekStart] (a Monday)
  static Future<WeekSummary> createWeekly(DateTime weekStart) async {
    final entries = await DoseLog.between(weekStart, addDays(weekStart, 6));
    final summary = WeekSummary.fromEntries(weekStart, entries);
    final db = await DBHelper.db();
    await db.insert(
      'weekly_reports',
      {
        'week_start': dbDate(weekStart),
        'expected': summary.expected,
        'taken': summary.taken,
        'details': jsonEncode(summary.medicines.map((m) => m.toJson()).toList()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return summary;
  }

  static Future<List<WeekSummary>> history() async {
    final db = await DBHelper.db();
    final rows = await db.query('weekly_reports', orderBy: 'week_start DESC');
    return rows.map((row) {
      final details = (jsonDecode(row['details'] as String? ?? '[]') as List)
          .map((m) => MedicineTally.fromJson(m as Map<String, dynamic>))
          .toList();
      return WeekSummary(
        parseDbDate(row['week_start'])!,
        row['expected'] as int,
        row['taken'] as int,
        details,
      );
    }).toList();
  }
}

// ========== SETTINGS ==========
// Meal times, snooze length and app state, kept in shared preferences
class Settings {
  static const int defaultSnoozeMinutes = 10;

  static TimeOfDay mealTime(SharedPreferences prefs, DoseSlot slot) => TimeOfDay(
        hour: prefs.getInt('${slot.mealKey}_hour') ?? slot.defaultHour,
        minute: prefs.getInt('${slot.mealKey}_minute') ?? 0,
      );

  static Future<void> setMealTime(
      SharedPreferences prefs, DoseSlot slot, TimeOfDay time) async {
    await prefs.setInt('${slot.mealKey}_hour', time.hour);
    await prefs.setInt('${slot.mealKey}_minute', time.minute);
  }

  static int snoozeMinutes(SharedPreferences prefs) =>
      prefs.getInt('snooze_minutes') ?? defaultSnoozeMinutes;

  static Future<void> setSnoozeMinutes(SharedPreferences prefs, int minutes) =>
      prefs.setInt('snooze_minutes', minutes);

  // First-run setup finished
  static bool onboarded(SharedPreferences prefs) => prefs.getBool('onboarded') ?? false;
  static Future<void> setOnboarded(SharedPreferences prefs) => prefs.setBool('onboarded', true);

  // Weekly report on/off (on by default)
  static bool weeklyReport(SharedPreferences prefs) => prefs.getBool('weekly_report') ?? true;
  static Future<void> setWeeklyReport(SharedPreferences prefs, bool on) =>
      prefs.setBool('weekly_report', on);

  static DateTime? _date(SharedPreferences prefs, String key) =>
      parseDbDate(prefs.getString(key));
  static Future<void> _setDate(SharedPreferences prefs, String key, DateTime d) =>
      prefs.setString(key, dbDate(d));

  static DateTime? logStartedOn(SharedPreferences prefs) => _date(prefs, 'log_started_on');
  static Future<void> setLogStartedOn(SharedPreferences prefs, DateTime d) =>
      _setDate(prefs, 'log_started_on', d);

  static DateTime? logFilledUntil(SharedPreferences prefs) => _date(prefs, 'log_filled_until');
  static Future<void> setLogFilledUntil(SharedPreferences prefs, DateTime d) =>
      _setDate(prefs, 'log_filled_until', d);

  static DateTime? lastReportWeek(SharedPreferences prefs) => _date(prefs, 'last_report_week');
  static Future<void> setLastReportWeek(SharedPreferences prefs, DateTime d) =>
      _setDate(prefs, 'last_report_week', d);
}

// ========== REMINDER TIMES ==========
// Meal time minus 20 min (before food) or plus 40 min (after food)
TimeOfDay reminderTimeOfDay(SharedPreferences prefs, DoseSlot slot, bool afterFood) {
  final meal = Settings.mealTime(prefs, slot);
  final minutes =
      (meal.hour * 60 + meal.minute + (afterFood ? 40 : -20)) % (24 * 60);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

TimeOfDay sessionTime(SharedPreferences prefs, Session s) =>
    reminderTimeOfDay(prefs, s.doseSlot, s.afterFood);

DateTime atTime(DateTime day, TimeOfDay time) =>
    DateTime(day.year, day.month, day.day, time.hour, time.minute);

// Medicines to take in session [s] on [day]. Normally only ones that
// existed by that time; [includeAddedLater] also lists ones added afterwards
// (shown on the home screen so a newly added medicine doesn't vanish).
List<Medicine> sessionMedicines(
        SharedPreferences prefs, List<Medicine> medicines, Session s, DateTime day,
        {bool includeAddedLater = false}) =>
    medicines
        .where((m) =>
            s.includes(m) &&
            (includeAddedLater
                ? m.isActiveOn(day)
                : m.isDueAt(atTime(day, sessionTime(prefs, s)))))
        .toList();

// "1 hour", "10 min"
String snoozeLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}' : '$minutes min';
