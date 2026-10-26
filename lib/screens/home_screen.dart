import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';
import 'medicine_form_screen.dart';
import 'medicine_list_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

// ========== HOME SCREEN ==========
// Today's medicines at a glance plus big buttons for everything else
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Medicine> medicines = [];
  List<SessionToday> sessions = [];
  SharedPreferences? prefs;
  bool remindersOn = true;
  bool isLoading = true;
  bool isSaving = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Cards open up (or go "late") as time passes, so re-check every minute
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Refresh when coming back to the app (time moved on, permission changed)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final data = await DBHelper.getMedicines();
    final savedPrefs = await SharedPreferences.getInstance();
    await savedPrefs.reload();
    await DoseLog.ensureDay(today(), data, savedPrefs);
    final entries = await DoseLog.forDay(today());
    final enabled = await remindersEnabled();
    if (!mounted) return;
    setState(() {
      medicines = data;
      prefs = savedPrefs;
      sessions = todaysSessions(savedPrefs, data, entries);
      remindersOn = enabled;
      isLoading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  // Tick / untick one medicine. The change shows at once; saving and
  // rescheduling happen after, and extra taps meanwhile are ignored.
  Future<void> _toggle(SessionToday item, Medicine med) async {
    if (isSaving || !item.isOpen) return;
    final taken = !item.takenIds.contains(med.id);
    setState(() {
      isSaving = true;
      taken ? item.takenIds.add(med.id!) : item.takenIds.remove(med.id);
    });
    await setDoseTaken(med, item.session, today(), taken);
    await _load();
    isSaving = false;
  }

  Future<void> _takeAll(SessionToday item) async {
    if (isSaving || !item.isOpen) return;
    final remaining = item.medicines.where((m) => !item.takenIds.contains(m.id)).toList();
    setState(() {
      isSaving = true;
      item.takenIds.addAll(remaining.map((m) => m.id!));
    });
    await setDosesTaken(remaining, item.session, today());
    await _load();
    isSaving = false;
  }

  // Ask again; if Android won't show the prompt any more, open settings
  Future<void> _turnOnReminders() async {
    final allowed = await requestReminderPermissions();
    if (!allowed) await openNotificationSettings();
    _load();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final showReport = prefs != null && Settings.weeklyReport(prefs!);

    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  children: [
                    // Greeting, date and logo
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting,
                                style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                              ),
                              Text(
                                DateFormat('EEEE d MMMM').format(DateTime.now()),
                                style: text.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                        Image.asset(
                          'assets/images/logo.png',
                          width: 68,
                          height: 68,
                          semanticLabel: 'MedMinder',
                        ),
                      ],
                    ),

                    // Notifications blocked: the app can't do its job
                    if (!remindersOn) ...[
                      const SizedBox(height: 20),
                      _remindersOffBanner(),
                    ],

                    // Today's doses, grouped like the reminders
                    const SectionHeader("Today's medicines"),
                    ..._todayList(),

                    // Main actions
                    const SectionHeader('What would you like to do?'),
                    BigMenuButton(
                      icon: Icons.add_rounded,
                      title: 'Add a medicine',
                      subtitle: 'Set up new reminders',
                      color: AppColors.primary,
                      filled: true,
                      onTap: () => _open(const MedicineFormScreen()),
                    ),
                    const SizedBox(height: 14),
                    BigMenuButton(
                      icon: Icons.medication_liquid_rounded,
                      title: 'My medicines',
                      subtitle: medicines.isEmpty
                          ? 'None saved yet'
                          : '${medicines.length} saved · edit or delete',
                      color: AppColors.afternoon,
                      onTap: () => _open(const MedicineListScreen()),
                    ),
                    if (showReport) ...[
                      const SizedBox(height: 14),
                      BigMenuButton(
                        icon: Icons.insights_rounded,
                        title: 'Weekly report',
                        subtitle: 'How often you took your medicines',
                        color: AppColors.night,
                        onTap: () => _open(const ReportScreen()),
                      ),
                    ],
                    const SizedBox(height: 14),
                    BigMenuButton(
                      icon: Icons.restaurant_rounded,
                      title: 'Meal times & settings',
                      subtitle: 'Meals, snooze, report, test',
                      color: AppColors.morning,
                      onTap: () => _open(const SettingsScreen()),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _remindersOffBanner() {
    final text = Theme.of(context).textTheme;
    return AppCard(
      color: AppColors.dangerSoft,
      borderColor: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.notifications_off_rounded, AppColors.danger),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Notifications are turned off', style: text.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'MedMinder cannot remind you to take your medicines '
            'until you allow notifications.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: _turnOnReminders,
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Allow notifications'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _todayList() {
    final text = Theme.of(context).textTheme;
    if (sessions.isEmpty) {
      return [
        AppCard(
          child: Row(
            children: [
              const IconBadge(Icons.check_circle_rounded, AppColors.success),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  medicines.isEmpty
                      ? 'No medicines yet.\nTap "Add a medicine" below to start.'
                      : 'Nothing to take today.',
                  style: text.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      for (final item in sessions)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SessionTile(
            item: item,
            onToggle: (med) => _toggle(item, med),
            onTakeAll: () => _takeAll(item),
          ),
        ),
    ];
  }
}

// One session on today's list. Earlier and current sessions can be ticked
// off (or corrected); later ones are greyed out until their time comes.
class _SessionTile extends StatelessWidget {
  final SessionToday item;
  final ValueChanged<Medicine> onToggle;
  final VoidCallback onTakeAll;

  const _SessionTile({required this.item, required this.onToggle, required this.onTakeAll});

  static const Color _closedColor = Color(0xFFECE9E3);

  StatusPill _status() {
    if (item.allTaken) {
      return const StatusPill('Taken', AppColors.success, icon: Icons.check_circle_rounded);
    }
    if (!item.isOpen) {
      return const StatusPill('Later today', AppColors.textMuted, icon: Icons.lock_clock_rounded);
    }
    // Only newly added medicines left: they weren't due yet, so no warning
    if (item.expectedTaken) {
      return const StatusPill('New today', AppColors.primary, icon: Icons.new_releases_rounded);
    }
    if (!item.isDue) {
      return const StatusPill('Coming up soon', AppColors.primary, icon: Icons.alarm_rounded);
    }
    if (item.isLate) {
      return const StatusPill('Not taken yet', AppColors.danger, icon: Icons.error_rounded);
    }
    return const StatusPill('Time to take now', AppColors.primary,
        icon: Icons.notifications_active_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = item.session;
    final open = item.isOpen;
    final whenText = '${s.whenText[0].toUpperCase()}${s.whenText.substring(1)}';

    final card = AppCard(
      color: item.allTaken
          ? AppColors.successSoft
          : open
              ? AppColors.surface
              : _closedColor,
      borderColor: item.allTaken || !open || item.expectedTaken
          ? null
          : item.isLate
              ? AppColors.danger
              : AppColors.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Morning" / "Before breakfast" (no clock times: easier to follow)
          Row(
            children: [
              IconBadge(s.doseSlot.icon, open ? s.doseSlot.color : AppColors.textMuted, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.doseSlot.label, style: text.titleLarge),
                    Text(whenText,
                        style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _status(),
          const SizedBox(height: 8),
          if (open && !item.allTaken)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'Tap a medicine once you have taken it',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),

          // What to take: big tap-to-tick rows
          for (final med in item.medicines)
            _MedicineRow(
              name: med.name,
              amount: med.doses[s.slot],
              taken: item.takenIds.contains(med.id),
              isNew: item.addedLaterIds.contains(med.id),
              enabled: open,
              onTap: () => onToggle(med),
            ),

          if (open && !item.allTaken) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: onTakeAll,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(item.medicines.length == 1 ? 'Mark as taken' : 'Mark all as taken'),
              ),
            ),
          ],
        ],
      ),
    );

    // Later sessions: greyed out and not tappable
    return open ? card : IgnorePointer(child: Opacity(opacity: 0.6, child: card));
  }
}

class _MedicineRow extends StatelessWidget {
  final String name;
  final int amount;
  final bool taken;
  final bool isNew; // added today after this dose's time
  final bool enabled;
  final VoidCallback onTap;

  const _MedicineRow({
    required this.name,
    required this.amount,
    required this.taken,
    required this.isNew,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      checked: taken,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            children: [
              Icon(
                taken ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: taken
                    ? AppColors.success
                    : enabled
                        ? AppColors.primary
                        : AppColors.textMuted,
                size: 36,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.titleMedium),
                    if (isNew && !taken)
                      Text(
                        'New today · tick if you took it',
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              Text('Take $amount', style: text.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
