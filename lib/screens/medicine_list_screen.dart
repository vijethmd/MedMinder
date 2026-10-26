import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';
import 'medicine_form_screen.dart';

// ========== MY MEDICINES SCREEN ==========
// Every saved medicine with its times, course dates, Edit and Delete
class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({super.key});

  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  List<Medicine> medicines = [];
  SharedPreferences? prefs;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DBHelper.getMedicines();
    final savedPrefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      medicines = data;
      prefs = savedPrefs;
      isLoading = false;
    });
  }

  Future<void> _openForm([Medicine? medicine]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MedicineFormScreen(medicine: medicine)),
    );
    _load();
  }

  Future<void> _delete(Medicine med) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${med.name}?',
      message: 'Its reminders will stop. This cannot be undone.',
      confirmLabel: 'Yes, delete',
      destructive: true,
    );
    if (!confirmed) return;

    await DBHelper.delete(med.id!);
    await removeMedicineReminders(med.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${med.name} deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My medicines')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : medicines.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    for (final med in medicines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _MedicineCard(
                          medicine: med,
                          prefs: prefs!,
                          onEdit: () => _openForm(med),
                          onDelete: () => _delete(med),
                        ),
                      ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a medicine'),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.medication_rounded, AppColors.primary, size: 96),
            const SizedBox(height: 20),
            Text('No medicines yet', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap "Add a medicine" below to set up your first reminder.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final Medicine medicine;
  final SharedPreferences prefs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MedicineCard({
    required this.medicine,
    required this.prefs,
    required this.onEdit,
    required this.onDelete,
  });

  // Where the course is: not started, running, last day or finished
  StatusPill _courseStatus() {
    final med = medicine;
    final shortDate = DateFormat('d MMM');
    if (med.isFinished) {
      return StatusPill('Finished on ${shortDate.format(med.endDate!)}',
          AppColors.textMuted, icon: Icons.check_circle_rounded);
    }
    if (med.notStartedYet) {
      return StatusPill('Starts ${friendlyDate(med.startDate)}', AppColors.morning,
          icon: Icons.event_rounded);
    }
    if (med.endDate == null) {
      return const StatusPill('Every day · no end date', AppColors.success,
          icon: Icons.all_inclusive_rounded);
    }
    final daysLeft = daysBetween(today(), med.endDate!) + 1;
    return StatusPill(
      daysLeft == 1
          ? 'Last day today'
          : 'Until ${shortDate.format(med.endDate!)} · $daysLeft days left',
      AppColors.primary,
      icon: Icons.event_available_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final med = medicine;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.medication_rounded, AppColors.primary),
              const SizedBox(width: 14),
              Expanded(child: Text(med.name, style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: 12),
          _courseStatus(),
          const SizedBox(height: 16),

          // Each time of day with its reminder time
          for (int i = 0; i < doseSlots.length; i++)
            if (med.doses[i] > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(doseSlots[i].icon, color: doseSlots[i].color, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${doseSlots[i].label} · '
                        '${reminderTimeOfDay(prefs, doseSlots[i], med.afterFood).format(context)}',
                        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text('Take ${med.doses[i]}', style: text.bodyLarge),
                  ],
                ),
              ),
          Row(
            children: [
              const Icon(Icons.restaurant_rounded, color: AppColors.textMuted, size: 26),
              const SizedBox(width: 12),
              Text(
                med.afterFood ? 'After food' : 'Before food',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 2),
                  ),
                  icon: const Icon(Icons.delete_rounded),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
