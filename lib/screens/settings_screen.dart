import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';

// ========== MEAL TIMES & SETTINGS SCREEN ==========
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<int> snoozeOptions = [5, 10, 15, 30, 60];

  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => prefs = p);
    });
  }

  // ---------- Meal times ----------
  Future<void> _pickMealTime(DoseSlot slot) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: Settings.mealTime(prefs!, slot),
      helpText: '${slot.mealName.toUpperCase()} TIME',
    );
    if (picked == null) return;

    await Settings.setMealTime(prefs!, slot, picked);
    // Move existing reminders to the new meal time
    await refreshReminders();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${slot.mealName} set to ${picked.format(context)}. Reminders updated.'),
      ),
    );
  }

  // ---------- Snooze ----------
  Future<void> _setSnooze(int minutes) async {
    await Settings.setSnoozeMinutes(prefs!, minutes);
    // Reminders carry the "Snooze N min" label, so rebuild them
    await refreshReminders();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Snooze set to ${snoozeLabel(minutes)}')),
    );
  }

  Future<void> _pickCustomSnooze() async {
    final controller = TextEditingController(text: '${Settings.snoozeMinutes(prefs!)}');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Snooze for how long?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: const InputDecoration(
            suffixText: 'minutes',
            helperText: 'Between 1 and 240',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null) Navigator.pop(context, value.clamp(1, 240));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (minutes != null) await _setSnooze(minutes);
  }

  // ---------- Weekly report ----------
  Future<void> _setWeeklyReport(bool on) async {
    await Settings.setWeeklyReport(prefs!, on);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? 'Weekly report turned on' : 'Weekly report turned off')),
    );
  }

  // ---------- Test ----------
  Future<void> _sendTest() async {
    final secondAt = await sendTestReminders();
    if (!mounted) return;
    await showInfoDialog(
      context,
      icon: Icons.notifications_active_rounded,
      color: AppColors.primary,
      title: 'Test sent',
      message: 'You should see a reminder now, and another at '
          '${DateFormat.jm().format(secondAt)}.\n\n'
          'You can lock your phone and wait for it.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final snooze = Settings.snoozeMinutes(prefs!);

    return Scaffold(
      appBar: AppBar(title: const Text('Meal times & settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          // Meal times
          const SectionHeader(
            'Your meal times',
            subtitle: 'Reminders are set around these times.',
          ),
          for (final slot in doseSlots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: () => _pickMealTime(slot),
                child: Row(
                  children: [
                    IconBadge(slot.icon, slot.color, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(slot.mealName, style: text.titleMedium),
                          Text(
                            Settings.mealTime(prefs!, slot).format(context),
                            style: text.headlineSmall?.copyWith(color: slot.color),
                          ),
                        ],
                      ),
                    ),
                    Text('Change', style: text.labelLarge?.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ),

          // Snooze
          const SectionHeader(
            'Snooze',
            subtitle: 'What the "Snooze" button does. The reminder also shows '
                'quick choices: 5 min, 10 min, 15 min and 1 hour.',
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBadge(Icons.snooze_rounded, AppColors.afternoon, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Remind me again after',
                              style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                          Text(
                            snoozeLabel(snooze),
                            style: text.headlineSmall?.copyWith(color: AppColors.afternoon),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final minutes in snoozeOptions)
                      ChoiceChip(
                        label: Text(snoozeLabel(minutes)),
                        selected: snooze == minutes,
                        onSelected: (_) => _setSnooze(minutes),
                      ),
                    ChoiceChip(
                      label: const Text('Other…'),
                      selected: !snoozeOptions.contains(snooze),
                      onSelected: (_) => _pickCustomSnooze(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Weekly report
          const SectionHeader(
            'Weekly report',
            subtitle: 'Every Monday morning, see how often you took your medicines last week.',
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Settings.weeklyReport(prefs!),
              onChanged: _setWeeklyReport,
              secondary: const IconBadge(Icons.insights_rounded, AppColors.night, size: 56),
              title: Text('Weekly report', style: text.titleMedium),
              subtitle: Text(
                Settings.weeklyReport(prefs!) ? 'On' : 'Off',
                style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),

          // Test
          const SectionHeader(
            'Check your reminders',
            subtitle: 'Sends one reminder now and another in 1 minute. Reminders play '
                "MedMinder's own chime at alarm volume.",
          ),
          FilledButton.icon(
            onPressed: _sendTest,
            icon: const Icon(Icons.notifications_active_rounded),
            label: const Text('Send a test reminder'),
          ),

          // How it works
          const SectionHeader('How reminders work'),
          AppCard(
            color: AppColors.primarySoft,
            borderColor: AppColors.primarySoft,
            child: Column(
              children: [
                const _InfoRow(Icons.schedule_rounded, 'Before food',
                    'Reminder 20 minutes before your meal'),
                const Divider(height: 28),
                const _InfoRow(Icons.restaurant_rounded, 'After food',
                    'Reminder 40 minutes after your meal'),
                const Divider(height: 28),
                _InfoRow(Icons.snooze_rounded, 'Snooze',
                    'Tap Snooze for ${snoozeLabel(snooze)}, or tap 5 min, 10 min, 15 min or 1 hour'),
                const Divider(height: 28),
                const _InfoRow(Icons.check_circle_rounded, 'Taken ✓',
                    'Tap it once you have taken your medicine'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoRow(this.icon, this.title, this.description);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28, color: AppColors.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              Text(description, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
