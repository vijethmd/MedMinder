import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';

// ========== TAKE YOUR MEDICINES ==========
// Opened by tapping a reminder: what to take now, each with a Taken button
class TakeMedicinesScreen extends StatefulWidget {
  final Session session;
  final DateTime? date; // null = the day this session last rang

  const TakeMedicinesScreen({super.key, required this.session, this.date});

  @override
  State<TakeMedicinesScreen> createState() => _TakeMedicinesScreenState();
}

class _TakeMedicinesScreenState extends State<TakeMedicinesScreen> {
  SharedPreferences? prefs;
  late DateTime day;
  List<Medicine> medicines = [];
  Map<int, DoseEntry> entries = {}; // by medicine id
  bool isLoading = true;
  bool isSaving = false;

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    day = widget.date ?? sessionDate(p, session);
    final all = await DBHelper.getMedicines();
    await DoseLog.ensureDay(day, all, p);
    final logged = await DoseLog.forDay(day);
    if (!mounted) return;
    setState(() {
      prefs = p;
      medicines = sessionMedicines(p, all, session, day);
      entries = {
        for (final e in logged)
          if (e.slot == session.slot) e.medId: e,
      };
      isLoading = false;
    });
  }

  bool _isTaken(Medicine med) => entries[med.id]?.isTaken ?? false;

  // Show the change straight away (saving and rescheduling take a moment),
  // and ignore extra taps meanwhile so a double tap can't undo it
  void _showLocally(Medicine med, bool taken) {
    entries[med.id!] = DoseEntry(
      medId: med.id!,
      medName: med.name,
      date: day,
      slot: session.slot,
      afterFood: session.afterFood,
      amount: med.doses[session.slot],
      takenAt: taken ? DateTime.now() : null,
    );
  }

  Future<void> _toggle(Medicine med) async {
    if (isSaving) return;
    final taken = !_isTaken(med);
    setState(() {
      isSaving = true;
      _showLocally(med, taken);
    });
    await setDoseTaken(med, session, day, taken);
    await _load();
    isSaving = false;
    if (taken && medicines.every(_isTaken)) await _allDone();
  }

  Future<void> _takeAll() async {
    if (isSaving) return;
    setState(() {
      isSaving = true;
      for (final med in medicines) {
        if (!_isTaken(med)) _showLocally(med, true);
      }
    });
    await setSessionTaken(session, day);
    await _load();
    isSaving = false;
    await _allDone();
  }

  Future<void> _allDone() async {
    if (!mounted) return;
    await showInfoDialog(
      context,
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
      title: 'Well done!',
      message: 'All your ${session.doseSlot.label.toLowerCase()} medicines are marked as taken.',
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final time = sessionTime(prefs!, session);
    final allTaken = medicines.isNotEmpty && medicines.every(_isTaken);

    return Scaffold(
      appBar: AppBar(title: const Text('Your medicines')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          // Which session
          AppCard(
            color: session.doseSlot.color.withValues(alpha: 0.08),
            borderColor: session.doseSlot.color,
            child: Row(
              children: [
                IconBadge(session.doseSlot.icon, session.doseSlot.color, size: 68),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.title, style: text.titleLarge),
                      Text(
                        '${time.format(context)} · ${session.whenText}',
                        style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                      ),
                      if (daysBetween(day, today()) != 0)
                        Text(friendlyDate(day),
                            style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (medicines.isEmpty)
            Text('Nothing to take at this time.', style: text.bodyLarge)
          else ...[
            Text(
              allTaken ? 'All taken ✓' : 'Tap "Taken" after taking each one',
              style: text.titleMedium?.copyWith(
                color: allTaken ? AppColors.success : AppColors.text,
              ),
            ),
            const SizedBox(height: 14),
            for (final med in medicines)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _MedicineToTake(
                  medicine: med,
                  amount: med.doses[session.slot],
                  takenAt: entries[med.id]?.takenAt,
                  onToggle: () => _toggle(med),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: medicines.isEmpty || allTaken
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: _takeAll,
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(medicines.length == 1 ? 'I have taken it' : 'I have taken them all'),
                ),
              ),
            ),
    );
  }
}

class _MedicineToTake extends StatelessWidget {
  final Medicine medicine;
  final int amount;
  final DateTime? takenAt;
  final VoidCallback onToggle;

  const _MedicineToTake({
    required this.medicine,
    required this.amount,
    required this.takenAt,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final taken = takenAt != null;

    return AppCard(
      color: taken ? AppColors.successSoft : AppColors.surface,
      borderColor: taken ? AppColors.success : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.medication_rounded, AppColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medicine.name, style: text.titleLarge),
                    Text('Take $amount', style: text.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (taken)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Taken at ${DateFormat.jm().format(takenAt!)}',
                    style: text.titleMedium?.copyWith(color: AppColors.success),
                  ),
                ),
                TextButton(onPressed: onToggle, child: const Text('Undo')),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: onToggle,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Taken'),
              ),
            ),
        ],
      ),
    );
  }
}
