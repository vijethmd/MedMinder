import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:med_minder/data.dart';
import 'package:med_minder/reminders.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  group('Medicine', () {
    test('reads rows saved before course dates existed', () {
      final med = Medicine.fromMap({
        'id': 3,
        'name': 'dolo',
        'pattern': '1-0-2',
        'relation': 'Before Food',
      });
      expect(med.doses, [1, 0, 2]);
      expect(med.afterFood, isFalse);
      expect(med.startDate, today());
      expect(med.endDate, isNull);
    });

    test('saves and reads back the same values', () {
      final med = Medicine(
        name: 'Paracetamol',
        doses: const [1, 1, 1],
        afterFood: true,
        startDate: DateTime(2026, 10, 26),
        endDate: DateTime(2026, 11, 1),
      );
      final back = Medicine.fromMap({...med.toMap(), 'id': 1});
      expect(med.toMap()['pattern'], '1-1-1');
      expect(back.doses, [1, 1, 1]);
      expect(back.startDate, DateTime(2026, 10, 26));
      expect(back.endDate, DateTime(2026, 11, 1));
    });

    test('is active only between start and end date (inclusive)', () {
      final med = Medicine(
        name: 'x',
        doses: const [1, 0, 0],
        afterFood: true,
        startDate: DateTime(2026, 10, 26),
        endDate: DateTime(2026, 10, 30),
      );
      expect(med.isActiveOn(DateTime(2026, 10, 25)), isFalse);
      expect(med.isActiveOn(DateTime(2026, 10, 26, 23, 59)), isTrue);
      expect(med.isActiveOn(DateTime(2026, 10, 30)), isTrue);
      expect(med.isActiveOn(DateTime(2026, 10, 31)), isFalse);
    });
  });

  group('Dates and labels', () {
    test('daysBetween counts whole days', () {
      expect(daysBetween(DateTime(2026, 10, 26, 23), DateTime(2026, 10, 27, 1)), 1);
      expect(daysBetween(DateTime(2026, 10, 26), DateTime(2026, 11, 1)), 6);
    });

    test('snooze labels', () {
      expect(snoozeLabel(10), '10 min');
      expect(snoozeLabel(60), '1 hour');
      expect(snoozeLabel(120), '2 hours');
      expect(snoozeChoices['1 hour'], 60);
    });
  });

  group('Reminder times', () {
    setUp(() => tz.setLocalLocation(tz.getLocation('Asia/Kolkata')));

    test('before food is 20 min earlier, after food 40 min later', () async {
      SharedPreferences.setMockInitialValues({'dinner_hour': 22, 'dinner_minute': 30});
      final prefs = await SharedPreferences.getInstance();
      expect(reminderTimeOfDay(prefs, doseSlots[2], false), const TimeOfDay(hour: 22, minute: 10));
      expect(reminderTimeOfDay(prefs, doseSlots[2], true), const TimeOfDay(hour: 23, minute: 10));
      // Defaults: breakfast 8:00
      expect(reminderTimeOfDay(prefs, doseSlots[0], true), const TimeOfDay(hour: 8, minute: 40));
    });

    test('wraps past midnight', () async {
      SharedPreferences.setMockInitialValues({'dinner_hour': 23, 'dinner_minute': 50});
      final prefs = await SharedPreferences.getInstance();
      expect(reminderTimeOfDay(prefs, doseSlots[2], true), const TimeOfDay(hour: 0, minute: 30));
    });

    test('first reminder waits for a future start date', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final start = DateTime(today().year, today().month, today().day + 10);
      final med = Medicine(
        id: 1,
        name: 'x',
        doses: const [1, 0, 0],
        afterFood: false,
        startDate: start,
      );
      final first = firstReminder(prefs, med, 0)!;
      expect(dateOnly(first), start);
      expect([first.hour, first.minute], [7, 40]);
    });

    test('no reminder once the course is over', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final med = Medicine(
        id: 1,
        name: 'x',
        doses: const [1, 1, 1],
        afterFood: true,
        startDate: DateTime(2020, 1, 1),
        endDate: DateTime(2020, 1, 5),
      );
      expect(firstReminder(prefs, med, 0), isNull);
    });

  });

  group('Sessions', () {
    test('group medicines by time of day and food', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final before = Medicine(
          id: 1, name: 'A', doses: const [1, 0, 2], afterFood: false, startDate: today());
      final after = Medicine(
          id: 2, name: 'B', doses: const [1, 1, 0], afterFood: true, startDate: today());
      final ended = Medicine(
          id: 3, name: 'C', doses: const [1, 0, 0], afterFood: false,
          startDate: DateTime(2020), endDate: DateTime(2020, 2));
      final meds = [before, after, ended];

      const morningBefore = Session(0, false);
      expect(sessionMedicines(prefs, meds, morningBefore, today()).map((m) => m.name), ['A']);
      expect(sessionMedicines(prefs, meds, const Session(0, true), today()).map((m) => m.name), ['B']);
      expect(sessionMedicines(prefs, meds, const Session(1, false), today()), isEmpty);

      // Added at noon: not due at this morning's 7:40 reminder, due tomorrow
      final addedAtNoon = Medicine(
          id: 4, name: 'D', doses: const [1, 0, 0], afterFood: false,
          startDate: today(), createdAt: atTime(today(), const TimeOfDay(hour: 12, minute: 0)));
      expect(sessionMedicines(prefs, [addedAtNoon], morningBefore, today()), isEmpty);
      expect(sessionMedicines(prefs, [addedAtNoon], morningBefore, addDays(today(), 1)).length, 1);
      expect(morningBefore.title, 'Morning medicines');
      expect(morningBefore.whenText, 'before breakfast');
    });

    test('index round-trips', () {
      for (final s in allSessions) {
        expect(Session.fromIndex(s.index), s);
      }
    });
  });

  group('Weekly report', () {
    test('counts taken doses per medicine', () {
      final monday = DateTime(2026, 10, 19);
      DoseEntry entry(String name, {required bool taken}) => DoseEntry(
            medId: name.hashCode,
            medName: name,
            date: monday,
            slot: 0,
            afterFood: true,
            amount: 1,
            takenAt: taken ? monday : null,
          );
      final week = WeekSummary.fromEntries(monday, [
        entry('Dolo', taken: true),
        entry('Dolo', taken: false),
        entry('Aspirin', taken: true),
      ]);
      expect(week.expected, 3);
      expect(week.taken, 2);
      expect(week.percent, 67);
      expect(week.medicines.map((m) => '${m.name} ${m.taken}/${m.expected}'),
          ['Aspirin 1/1', 'Dolo 1/2']);
    });

    test('weeks start on Monday', () {
      expect(mondayOf(DateTime(2026, 10, 26)), DateTime(2026, 10, 26)); // Monday
      expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26)); // Sunday
    });
  });
}
