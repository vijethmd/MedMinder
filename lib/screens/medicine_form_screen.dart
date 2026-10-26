import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';

// ========== ADD / EDIT MEDICINE SCREEN ==========
// Four simple steps: name, times of day, food, how long
class MedicineFormScreen extends StatefulWidget {
  final Medicine? medicine; // null = adding a new one

  const MedicineFormScreen({super.key, this.medicine});

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  static const List<int> durationPresets = [5, 7, 10, 14, 30];
  static const String ongoing = 'ongoing';
  static const String customEnd = 'custom';

  final _nameController = TextEditingController();
  List<int> doses = [0, 0, 0];
  bool afterFood = true;
  DateTime startDate = today();
  DateTime? endDate;
  String durationChoice = ongoing; // 'ongoing', '7' (days) or 'custom'
  SharedPreferences? prefs;
  bool isSaving = false;

  bool get isEditing => widget.medicine != null;

  @override
  void initState() {
    super.initState();
    final med = widget.medicine;
    if (med != null) {
      _nameController.text = med.name;
      doses = List.of(med.doses);
      afterFood = med.afterFood;
      startDate = med.startDate;
      endDate = med.endDate;
      if (endDate != null) {
        final days = daysBetween(startDate, endDate!) + 1;
        durationChoice = durationPresets.contains(days) ? '$days' : customEnd;
      }
    }
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => prefs = p);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------- Dates ----------
  void _setPreset(int days) {
    setState(() {
      durationChoice = '$days';
      endDate = DateTime(startDate.year, startDate.month, startDate.day + days - 1);
    });
  }

  Future<void> _pickStartDate() async {
    final now = today();
    final earliest = startDate.isBefore(now) ? startDate : DateTime(now.year - 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: earliest,
      lastDate: DateTime(now.year + 2, now.month, now.day),
      helpText: 'WHEN DO YOU START?',
      confirmText: 'Choose',
    );
    if (picked == null) return;

    setState(() => startDate = dateOnly(picked));
    // Keep the chosen length, or make sure a custom end isn't before the start
    final days = int.tryParse(durationChoice);
    if (days != null) {
      _setPreset(days);
    } else if (endDate != null && endDate!.isBefore(startDate)) {
      setState(() => endDate = startDate);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate ?? DateTime(startDate.year, startDate.month, startDate.day + 6),
      firstDate: startDate,
      lastDate: DateTime(startDate.year + 5, startDate.month, startDate.day),
      helpText: 'LAST DAY OF THIS MEDICINE',
      confirmText: 'Choose',
    );
    if (picked == null) return;
    setState(() {
      durationChoice = customEnd;
      endDate = dateOnly(picked);
    });
  }

  String get _courseSummary {
    if (endDate == null) {
      return 'Every day from ${friendlyDate(startDate)}, with no end date.';
    }
    final days = daysBetween(startDate, endDate!) + 1;
    return 'Every day from ${friendlyDate(startDate)} '
        'until ${friendlyDate(endDate!)} ($days ${days == 1 ? 'day' : 'days'}).';
  }

  // ---------- Save ----------
  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return _showProblem('Please type the name of the medicine.');
    }
    if (doses.every((d) => d == 0)) {
      return _showProblem('Please choose at least one time of day (Morning, Afternoon or Night).');
    }

    setState(() => isSaving = true);
    var med = Medicine(
      id: widget.medicine?.id,
      name: name,
      doses: List.of(doses),
      afterFood: afterFood,
      startDate: startDate,
      endDate: endDate,
    );
    if (med.id == null) {
      med = med.withId(await DBHelper.insert(med));
    } else {
      await DBHelper.update(med);
    }

    await requestReminderPermissions();
    final firsts = await saveMedicineReminders(med);
    if (!mounted) return;

    await showInfoDialog(
      context,
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
      title: 'Saved',
      message: firsts.isEmpty
          ? '$name is saved, but its last day has already passed, so there are no more reminders.'
          : '$name is saved.\n\nFirst reminder: ${describeWhen(firsts.first)}.',
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showProblem(String message) {
    return showInfoDialog(
      context,
      icon: Icons.info_rounded,
      color: AppColors.danger,
      title: 'Almost there',
      message: message,
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit medicine' : 'Add a medicine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          // Step 1: name
          const _StepHeader(number: 1, title: 'What is the medicine called?'),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: text.titleMedium,
            decoration: const InputDecoration(hintText: 'For example: Paracetamol'),
          ),

          // Step 2: times of day
          const _StepHeader(
            number: 2,
            title: 'When do you take it?',
            hint: 'Tap a time to choose it. Use – and + to change how many.',
          ),
          for (int i = 0; i < doseSlots.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SlotCard(
                slot: doseSlots[i],
                count: doses[i],
                reminderTime: prefs == null
                    ? null
                    : reminderTimeOfDay(prefs!, doseSlots[i], afterFood),
                onChanged: (count) => setState(() => doses[i] = count),
              ),
            ),

          // Step 3: food
          const _StepHeader(number: 3, title: 'Before or after food?'),
          _ChoiceCard(
            icon: Icons.schedule_rounded,
            title: 'Before food',
            subtitle: 'Reminder 20 minutes before your meal',
            selected: !afterFood,
            onTap: () => setState(() => afterFood = false),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            icon: Icons.restaurant_rounded,
            title: 'After food',
            subtitle: 'Reminder 40 minutes after your meal',
            selected: afterFood,
            onTap: () => setState(() => afterFood = true),
          ),

          // Step 4: course dates
          const _StepHeader(number: 4, title: 'For how long?'),
          AppCard(
            onTap: _pickStartDate,
            child: Row(
              children: [
                const IconBadge(Icons.event_rounded, AppColors.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start date',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      Text(friendlyDate(startDate), style: text.titleMedium),
                    ],
                  ),
                ),
                Text('Change', style: text.labelLarge?.copyWith(color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('How many days?', style: text.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text('No end date'),
                selected: durationChoice == ongoing,
                onSelected: (_) => setState(() {
                  durationChoice = ongoing;
                  endDate = null;
                }),
              ),
              for (final days in durationPresets)
                ChoiceChip(
                  label: Text('$days days'),
                  selected: durationChoice == '$days',
                  onSelected: (_) => _setPreset(days),
                ),
              ChoiceChip(
                avatar: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                label: const Text('Pick end date'),
                selected: durationChoice == customEnd,
                onSelected: (_) => _pickEndDate(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            color: AppColors.primarySoft,
            borderColor: AppColors.primarySoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_repeat_rounded, color: AppColors.primary, size: 30),
                const SizedBox(width: 14),
                Expanded(child: Text(_courseSummary, style: text.bodyLarge)),
              ],
            ),
          ),
        ],
      ),

      // Save button always visible at the bottom
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(isEditing ? 'Save changes' : 'Save medicine'),
          ),
        ),
      ),
    );
  }
}

// Numbered step title
class _StepHeader extends StatelessWidget {
  final int number;
  final String title;
  final String? hint;

  const _StepHeader({required this.number, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary,
                child: Text(
                  '$number',
                  style: text.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: text.titleLarge)),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

// Morning / Afternoon / Night card with a – count + stepper
class _SlotCard extends StatelessWidget {
  final DoseSlot slot;
  final int count;
  final TimeOfDay? reminderTime;
  final ValueChanged<int> onChanged;

  const _SlotCard({
    required this.slot,
    required this.count,
    required this.reminderTime,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = count > 0;

    return Semantics(
      selected: selected,
      child: AppCard(
        onTap: () => onChanged(selected ? 0 : 1),
        color: selected ? slot.color.withValues(alpha: 0.07) : AppColors.surface,
        borderColor: selected ? slot.color : null,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconBadge(slot.icon, slot.color, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, style: text.titleMedium),
                  if (reminderTime != null)
                    Text(
                      'Reminder ${reminderTime!.format(context)}',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            if (selected)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundButton(
                    icon: Icons.remove_rounded,
                    color: slot.color,
                    tooltip: 'One less',
                    onPressed: () => onChanged(count - 1),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: text.headlineSmall,
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.add_rounded,
                    color: slot.color,
                    tooltip: 'One more',
                    onPressed: count < 9 ? () => onChanged(count + 1) : null,
                  ),
                ],
              )
            else
              Icon(Icons.add_circle_outline_rounded, size: 40, color: slot.color),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 28,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
      ),
      icon: Icon(icon),
    );
  }
}

// Big radio-style choice
class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: AppCard(
        onTap: onTap,
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderColor: selected ? AppColors.primary : null,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(subtitle, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(icon, size: 30, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
