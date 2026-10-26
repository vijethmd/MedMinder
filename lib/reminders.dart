import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'data.dart';
import 'theme.dart';

// How reminders work:
// - Medicines due at the same time are grouped into a "session" and get ONE
//   notification listing every medicine and how many to take.
// - Each session notification repeats daily. A background job just after
//   midnight refreshes the lists (courses starting/ending) and the weekly report.
// - Everything runs on the phone; nothing needs the internet.

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

// Notification channels (the sound of a channel can't change, hence v7)
const String _channelId = 'medminder_reminders_v7';
const String _channelName = 'Medicine reminders';
const String _reportChannelId = 'medminder_reports';
const String _oldChannelId = 'med_channel_v6';
const String _sound = 'medminder_chime'; // res/raw/medminder_chime.wav
const String _statusBarIcon = 'ic_stat_medminder';

// Notification IDs
const int _sessionIdBase = 2000; // + session index (0..5)
const int _snoozeIdBase = 3000; // + session index
const int _reportId = 4000;
const int _todayIdBase = 5000; // + session index: one-off when some were taken early
const int _testNowId = 999;
const int _testLaterId = 998;

// Background alarm (android_alarm_manager_plus) that refreshes everything daily
const int _dailyRefreshAlarmId = 900001;

// Notification buttons
const String takenAction = 'taken';
const String snoozeAction = 'snooze';

// Quick snooze choices shown right on the notification
const Map<String, int> snoozeChoices = {
  '5 min': 5,
  '10 min': 10,
  '15 min': 15,
  '1 hour': 60,
};

// ========== SETUP ==========
// Without this tz.local is UTC and reminders fire at the wrong time
Future<void> initTimeZone() async {
  tz.initializeTimeZones();
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));
  } catch (_) {}
}

Future<void> initReminders() async {
  await initTimeZone();
  await AndroidAlarmManager.initialize();

  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings(_statusBarIcon),
    ),
    onDidReceiveNotificationResponse: _onForegroundResponse,
    onDidReceiveBackgroundNotificationResponse: onNotificationAction,
  );

  final android = _android;
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders to take your medicines',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(_sound),
      // Alarm volume, so it is loud enough to notice
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _reportChannelId,
      'Weekly report',
      description: 'A summary of the medicines you took each week',
      importance: Importance.defaultImportance,
    ),
  );
  await android?.deleteNotificationChannel(_oldChannelId);

  await _migrateFromPerMedicineReminders();
}

// Before sessions, each medicine had its own notifications and a
// "course end" alarm; remove those once
Future<void> _migrateFromPerMedicineReminders() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('sessions_migrated') ?? false) return;
  for (final med in await DBHelper.getMedicines()) {
    for (int i = 0; i < doseSlots.length; i++) {
      await notifications.cancel(med.id! * 10 + i);
      await notifications.cancel(100000 + med.id! * 10 + i);
    }
    await AndroidAlarmManager.cancel(med.id!);
  }
  await prefs.setBool('sessions_migrated', true);
}

AndroidFlutterLocalNotificationsPlugin? get _android =>
    notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

Future<bool> remindersEnabled() async =>
    await _android?.areNotificationsEnabled() ?? true;

// Ask for notification + exact alarm permission (needs a visible screen).
// Returns whether notifications are allowed afterwards.
Future<bool> requestReminderPermissions() async {
  await _android?.requestNotificationsPermission();
  if (!(await _android?.canScheduleExactNotifications() ?? true)) {
    await _android?.requestExactAlarmsPermission();
  }
  return remindersEnabled();
}

// Android stops showing the permission prompt after it's been refused
// twice; then the only way is the app's notification settings page
Future<void> openNotificationSettings() async {
  try {
    await const MethodChannel('medminder/system').invokeMethod('openNotificationSettings');
  } catch (_) {}
}

// Exact alarms when allowed, otherwise let Android deliver them a bit late
Future<AndroidScheduleMode> _scheduleMode() async {
  return (await _android?.canScheduleExactNotifications() ?? true)
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;
}

// ========== REMINDER TIMES ==========
// (reminderTimeOfDay, sessionTime and sessionMedicines live in data.dart)
tz.TZDateTime _at(DateTime day, TimeOfDay time) =>
    tz.TZDateTime(tz.local, day.year, day.month, day.day, time.hour, time.minute);

// First time a medicine's dose should ring, or null if the course is over by then
tz.TZDateTime? firstReminder(SharedPreferences prefs, Medicine med, int slot) {
  final now = tz.TZDateTime.now(tz.local);
  final time = reminderTimeOfDay(prefs, doseSlots[slot], med.afterFood);

  final day = med.startDate.isAfter(today()) ? med.startDate : today();
  var first = _at(day, time);
  if (!first.isAfter(now)) first = _at(addDays(day, 1), time);

  if (med.endDate != null && dateOnly(first).isAfter(med.endDate!)) return null;
  return first;
}

// Which day a session notification belongs to: the latest time it rang.
// (A night reminder opened after midnight still belongs to yesterday.)
DateTime sessionDate(SharedPreferences prefs, Session s) {
  final atToday = _at(today(), sessionTime(prefs, s));
  return atToday.isAfter(tz.TZDateTime.now(tz.local)) ? addDays(today(), -1) : today();
}

// One session on today's list (home screen)
class SessionToday {
  // A session can be marked as taken from this long before its reminder
  static const Duration earlyWindow = Duration(hours: 1);
  // After this long without being taken it shows as "Not taken yet"
  static const Duration lateAfter = Duration(hours: 2);

  final Session session;
  final tz.TZDateTime time;
  final List<Medicine> medicines;
  final Set<int> takenIds;
  // Added today after this session's time: shown, but never "missed"
  final Set<int> addedLaterIds;

  const SessionToday(this.session, this.time, this.medicines, this.takenIds, this.addedLaterIds);

  tz.TZDateTime get _now => tz.TZDateTime.now(tz.local);

  bool get allTaken => medicines.every((m) => takenIds.contains(m.id));
  // Everything that was actually due has been taken
  bool get expectedTaken => medicines
      .where((m) => !addedLaterIds.contains(m.id))
      .every((m) => takenIds.contains(m.id));
  // Earlier sessions stay open so they can still be corrected
  bool get isOpen => !_now.isBefore(time.subtract(earlyWindow));
  bool get isDue => !time.isAfter(_now);
  bool get isLate => _now.isAfter(time.add(lateAfter));
}

List<SessionToday> todaysSessions(
    SharedPreferences prefs, List<Medicine> medicines, List<DoseEntry> entries) {
  final list = <SessionToday>[];
  for (final s in allSessions) {
    final meds = sessionMedicines(prefs, medicines, s, today(), includeAddedLater: true);
    if (meds.isEmpty) continue;
    final time = _at(today(), sessionTime(prefs, s));
    final taken = entries
        .where((e) => e.isTaken && e.slot == s.slot)
        .map((e) => e.medId)
        .toSet();
    final addedLater = meds.where((m) => !m.isDueAt(time)).map((m) => m.id!).toSet();
    list.add(SessionToday(s, time, meds, taken, addedLater));
  }
  list.sort((a, b) => a.time.compareTo(b.time));
  return list;
}

// ========== NOTIFICATION LOOK ==========
// e.g. "Dolo — take 1"
String _doseLine(Medicine med, Session s) => '${med.name} — take ${med.doses[s.slot]}';

// Big text, MedMinder chime, "Taken" + "Snooze" buttons and quick snooze choices
NotificationDetails _reminderDetails({
  required int snoozeMinutes,
  required String title,
  required String bigText,
  required String summary,
}) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: _statusBarIcon,
      color: AppColors.primary,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(_sound),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: title,
        summaryText: summary,
      ),
      actions: [
        const AndroidNotificationAction(
          takenAction,
          'Taken ✓',
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          snoozeAction,
          'Snooze ${snoozeLabel(snoozeMinutes)}',
          cancelNotification: true, // hide it until the snooze ends
          // Shown as tap-once chips under the notification
          inputs: [
            AndroidNotificationActionInput(
              choices: snoozeChoices.keys.toList(),
              allowFreeFormInput: false,
            ),
          ],
        ),
      ],
    ),
  );
}

String _sessionPayload(Session s) => jsonEncode({'type': 'session', 'session': s.index});

// Show [medicines] for session [s] at [when] (repeating daily or once)
Future<void> _scheduleSessionNotification({
  required int id,
  required Session s,
  required List<Medicine> medicines,
  required tz.TZDateTime when,
  required int snoozeMinutes,
  required AndroidScheduleMode mode,
  bool repeatDaily = true,
}) async {
  final title = '💊 ${s.title} · ${DateFormat.jm().format(when)}';
  final lines = medicines.map((m) => _doseLine(m, s)).toList();
  final summary = 'Take ${s.whenText}';
  await notifications.zonedSchedule(
    id,
    title,
    lines.join(', '),
    when,
    _reminderDetails(
      snoozeMinutes: snoozeMinutes,
      title: title,
      bigText: lines.map((l) => '• $l').join('\n'),
      summary: summary,
    ),
    androidScheduleMode: mode,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
    payload: _sessionPayload(s),
  );
}

// ========== SCHEDULING ==========
// Rebuild every session reminder from the saved medicines and meal times.
// Called on app start, after any change, and by the daily background job.
Future<void> refreshReminders() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // another isolate may have changed settings
  final medicines = await DBHelper.getMedicines();
  await DoseLog.catchUp(medicines, prefs);
  final todayEntries = await DoseLog.forDay(today());
  final mode = await _scheduleMode();
  final snooze = Settings.snoozeMinutes(prefs);
  final now = tz.TZDateTime.now(tz.local);

  for (final s in allSessions) {
    final id = _sessionIdBase + s.index;
    final time = sessionTime(prefs, s);
    var scheduled = false;
    var firstDay = 0;

    // Never remind about a medicine already taken today (avoids double doses).
    // If some were taken early, today gets a one-off reminder for the rest
    // and the daily reminder (with everything) starts tomorrow.
    final todayWhen = _at(today(), time);
    if (todayWhen.isAfter(now)) {
      await notifications.cancel(_todayIdBase + s.index);
      final taken = todayEntries
          .where((e) => e.isTaken && e.slot == s.slot)
          .map((e) => e.medId)
          .toSet();
      final due = sessionMedicines(prefs, medicines, s, today());
      final left = due.where((m) => !taken.contains(m.id)).toList();
      if (left.length < due.length) {
        firstDay = 1;
        if (left.isNotEmpty) {
          await _scheduleSessionNotification(
            id: _todayIdBase + s.index,
            s: s,
            medicines: left,
            when: todayWhen,
            snoozeMinutes: snooze,
            mode: mode,
            repeatDaily: false,
          );
        }
      }
    }

    // Android's daily repeat always starts at the next time this clock time
    // comes round, whatever date it is given. So a later first day (course
    // not started yet, or taken early today) is scheduled once, and the
    // 00:05 job turns it into a daily reminder on that day.
    final nextNatural = todayWhen.isAfter(now) ? todayWhen : _at(addDays(today(), 1), time);

    // First upcoming day that has something to take (looks 60 days ahead
    // so a course starting later still gets its reminder)
    for (int d = firstDay; d <= 60 && !scheduled; d++) {
      final day = addDays(today(), d);
      final when = _at(day, time);
      if (!when.isAfter(now)) continue;

      final due = sessionMedicines(prefs, medicines, s, day);
      if (due.isEmpty) continue;

      await _scheduleSessionNotification(
        id: id,
        s: s,
        medicines: due,
        when: when,
        snoozeMinutes: snooze,
        mode: mode,
        repeatDaily: when.isAtSameMomentAs(nextNatural),
      );
      scheduled = true;
    }
    if (!scheduled) await notifications.cancel(id);
  }

  await _scheduleDailyRefresh();
}

// After saving a medicine; returns when each of its doses first rings
Future<List<tz.TZDateTime>> saveMedicineReminders(Medicine med) async {
  await DoseLog.clearPendingFrom(med.id!, today());
  await refreshReminders();
  final prefs = await SharedPreferences.getInstance();
  final firsts = <tz.TZDateTime>[];
  for (int i = 0; i < doseSlots.length; i++) {
    if (med.doses[i] <= 0) continue;
    final first = firstReminder(prefs, med, i);
    if (first != null) firsts.add(first);
  }
  return firsts..sort();
}

// After deleting a medicine (its taken history stays for the reports)
Future<void> removeMedicineReminders(int medId) async {
  await DoseLog.clearPendingFrom(medId, today());
  await refreshReminders();
}

// Mark doses taken from inside the app, then tidy up notifications
Future<void> setDoseTaken(Medicine med, Session s, DateTime day, bool taken) async {
  final prefs = await SharedPreferences.getInstance();
  final expected = med.isDueAt(atTime(day, sessionTime(prefs, s)));
  if (taken) {
    await DoseLog.addDose(med, day, s.slot);
    await DoseLog.setTaken(med.id!, day, s.slot, true);
  } else if (expected) {
    await DoseLog.setTaken(med.id!, day, s.slot, false);
  } else {
    // Added after this dose's time: unticking means it simply wasn't due
    await DoseLog.removeDose(med.id!, day, s.slot);
  }
  await _afterTakenChange(s, day);
}

// Tick several at once (home screen "Mark all as taken")
Future<void> setDosesTaken(List<Medicine> medicines, Session s, DateTime day) async {
  for (final med in medicines) {
    await DoseLog.addDose(med, day, s.slot);
    await DoseLog.setTaken(med.id!, day, s.slot, true);
  }
  await _afterTakenChange(s, day);
}

Future<void> setSessionTaken(Session s, DateTime day) async {
  final prefs = await SharedPreferences.getInstance();
  final medicines = await DBHelper.getMedicines();
  await DoseLog.ensureDay(day, medicines, prefs);
  await DoseLog.setSessionTaken(s, day);
  await _afterTakenChange(s, day);
}

Future<void> _afterTakenChange(Session s, DateTime day) async {
  final prefs = await SharedPreferences.getInstance();
  final medicines = sessionMedicines(prefs, await DBHelper.getMedicines(), s, day);
  final entries = await DoseLog.forDay(day);
  final taken = entries.where((e) => e.isTaken && e.slot == s.slot).map((e) => e.medId).toSet();
  if (medicines.every((m) => taken.contains(m.id))) {
    // All done: remove the reminder and any snooze for this session
    await notifications.cancel(_snoozeIdBase + s.index);
    await notifications.cancel(_todayIdBase + s.index);
    await notifications.cancel(_sessionIdBase + s.index);
  }
  await refreshReminders();
}

// ========== DAILY BACKGROUND JOB ==========
Future<void> _scheduleDailyRefresh() async {
  final now = DateTime.now();
  await AndroidAlarmManager.oneShotAt(
    DateTime(now.year, now.month, now.day + 1, 0, 5),
    _dailyRefreshAlarmId,
    onDailyRefresh,
    exact: true,
    allowWhileIdle: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}

// Runs at 00:05 every day, even if the app is closed
@pragma('vm:entry-point')
Future<void> onDailyRefresh(int alarmId) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    await initTimeZone();
    await refreshReminders();
    await checkWeeklyReport();
  } catch (e, stack) {
    debugPrint('MedMinder: daily refresh failed: $e\n$stack');
  }
}

// ========== WEEKLY REPORT ==========
// Once a week (Monday), sum up last week and notify at 9 AM
Future<void> checkWeeklyReport() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!Settings.weeklyReport(prefs)) return;

  final thisMonday = mondayOf(today());
  final lastWeek = addDays(thisMonday, -7);
  final startedOn = Settings.logStartedOn(prefs);
  // Need at least part of last week tracked, and only one report per week
  if (startedOn == null || !startedOn.isBefore(thisMonday)) return;
  if (Settings.lastReportWeek(prefs) == lastWeek) return;

  final report = await Reports.createWeekly(lastWeek);
  await Settings.setLastReportWeek(prefs, lastWeek);
  if (report.expected == 0) return;

  const title = '📋 Your weekly medicine report';
  final body = 'Last week you took ${report.taken} of ${report.expected} doses '
      '(${report.percent}%). Tap to see details.';
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      _reportChannelId,
      'Weekly report',
      icon: _statusBarIcon,
      color: AppColors.primary,
      styleInformation: DefaultStyleInformation(true, true),
    ),
  );
  final payload = jsonEncode({'type': 'report'});
  final nineAm = _at(thisMonday, const TimeOfDay(hour: 9, minute: 0));

  if (nineAm.isAfter(tz.TZDateTime.now(tz.local))) {
    await notifications.zonedSchedule(
      _reportId,
      title,
      body,
      nineAm,
      details,
      androidScheduleMode: await _scheduleMode(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  } else {
    await notifications.show(_reportId, title, body, details, payload: payload);
  }
}

// ========== OPENING THE APP FROM A NOTIFICATION ==========
// What a tapped notification asks the app to show
class NotificationTarget {
  final Session? session; // "take your medicines" page
  final bool report; // weekly report page

  const NotificationTarget({this.session, this.report = false});

  static NotificationTarget? fromPayload(String? payload) {
    try {
      final data = jsonDecode(payload ?? '') as Map<String, dynamic>;
      if (data['type'] == 'session') {
        return NotificationTarget(session: Session.fromIndex(data['session'] as int));
      }
      if (data['type'] == 'report') return const NotificationTarget(report: true);
    } catch (_) {}
    return null;
  }
}

final StreamController<NotificationTarget> _taps = StreamController.broadcast();
Stream<NotificationTarget> get notificationTaps => _taps.stream;

// The notification that opened the app from closed, if any
Future<NotificationTarget?> launchTarget() async {
  final details = await notifications.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp != true) return null;
  final response = details!.notificationResponse;
  if (response?.actionId != null) return null;
  return NotificationTarget.fromPayload(response?.payload);
}

void _onForegroundResponse(NotificationResponse response) {
  if (response.actionId != null) {
    onNotificationAction(response);
    return;
  }
  final target = NotificationTarget.fromPayload(response.payload);
  if (target != null) _taps.add(target);
}

// ========== NOTIFICATION BUTTONS ==========
// Runs when "Taken" or "Snooze" is tapped, even if the app is closed
@pragma('vm:entry-point')
Future<void> onNotificationAction(NotificationResponse response) async {
  debugPrint('MedMinder: button "${response.actionId}" input=${response.input}');
  try {
    // May run in a fresh background isolate, so set everything up again
    DartPluginRegistrant.ensureInitialized();
    await initTimeZone();
    final target = NotificationTarget.fromPayload(response.payload);
    final session = target?.session;

    if (response.actionId == takenAction && session != null) {
      final prefs = await SharedPreferences.getInstance();
      await setSessionTaken(session, sessionDate(prefs, session));
    } else if (response.actionId == snoozeAction) {
      await _snooze(response, session);
    }
  } catch (e, stack) {
    debugPrint('MedMinder: button failed: $e\n$stack');
  }
}

Future<void> _snooze(NotificationResponse response, Session? session) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  // A chip (e.g. "15 min") or the plain Snooze button (default length)
  final minutes = snoozeChoices[response.input] ?? Settings.snoozeMinutes(prefs);
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
  debugPrint('MedMinder: snoozing for $minutes min');

  if (session == null) {
    // Test reminder
    await _scheduleTest(_testLaterId, when, prefs);
    return;
  }

  // Only what is still left to take
  final day = sessionDate(prefs, session);
  final taken = (await DoseLog.forDay(day))
      .where((e) => e.isTaken && e.slot == session.slot)
      .map((e) => e.medId)
      .toSet();
  final medicines = sessionMedicines(prefs, await DBHelper.getMedicines(), session, day)
      .where((m) => !taken.contains(m.id))
      .toList();
  if (medicines.isEmpty) return;
  await _scheduleSessionNotification(
    id: _snoozeIdBase + session.index,
    s: session,
    medicines: medicines,
    when: when,
    snoozeMinutes: Settings.snoozeMinutes(prefs),
    mode: await _scheduleMode(),
    repeatDaily: false,
  );
}

// ========== TEST ==========
// One reminder now and one in a minute through the same alarm path.
// Returns when the second one is due.
Future<tz.TZDateTime> sendTestReminders() async {
  await requestReminderPermissions();
  final prefs = await SharedPreferences.getInstance();
  final details = _testDetails(prefs);
  await notifications.show(
    _testNowId,
    _testTitle,
    _testText,
    details,
    payload: jsonEncode({'type': 'test'}),
  );
  final inOneMinute = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
  await _scheduleTest(_testLaterId, inOneMinute, prefs);
  return inOneMinute;
}

const String _testTitle = '💊 Test reminder';
const String _testText = 'This is how your medicine reminders will look and sound.';

NotificationDetails _testDetails(SharedPreferences prefs) => _reminderDetails(
      snoozeMinutes: Settings.snoozeMinutes(prefs),
      title: _testTitle,
      bigText: '$_testText\n• Your medicines are listed here\n• with how many to take',
      summary: 'Test',
    );

Future<void> _scheduleTest(int id, tz.TZDateTime when, SharedPreferences prefs) async {
  await notifications.zonedSchedule(
    id,
    _testTitle,
    _testText,
    when,
    _testDetails(prefs),
    androidScheduleMode: await _scheduleMode(),
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    payload: jsonEncode({'type': 'test'}),
  );
}
