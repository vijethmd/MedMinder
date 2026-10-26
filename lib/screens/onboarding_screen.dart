import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../reminders.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart';

// ========== FIRST-RUN SETUP ==========
// 1. Welcome  2. Your meal times  3. Allow notifications
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final _pages = PageController();
  int page = 0;
  SharedPreferences? prefs;
  late List<TimeOfDay> mealTimes;
  bool? notificationsAllowed; // null until asked

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mealTimes = [for (final slot in doseSlots) TimeOfDay(hour: slot.defaultHour, minute: 0)];
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        prefs = p;
        // Keep any meal times saved before (e.g. after an update)
        mealTimes = [for (final slot in doseSlots) Settings.mealTime(p, slot)];
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  // Back from the system settings page: finish if notifications are now on
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed || notificationsAllowed != false) return;
    if (await remindersEnabled()) {
      setState(() => notificationsAllowed = true);
      await _finish();
    }
  }

  void _goTo(int index) {
    setState(() => page = index);
    _pages.animateToPage(index,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  Future<void> _pickMealTime(int i) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: mealTimes[i],
      helpText: '${doseSlots[i].mealName.toUpperCase()} TIME',
    );
    if (picked != null) setState(() => mealTimes[i] = picked);
  }

  Future<void> _saveMealTimes() async {
    for (int i = 0; i < doseSlots.length; i++) {
      await Settings.setMealTime(prefs!, doseSlots[i], mealTimes[i]);
    }
    _goTo(2);
  }

  Future<void> _askNotifications() async {
    final allowed = await requestReminderPermissions();
    if (mounted) setState(() => notificationsAllowed = allowed);
    if (allowed) await _finish();
  }

  Future<void> _finish() async {
    await Settings.setOnboarded(prefs!);
    await refreshReminders();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Step dots
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: i == page ? 32 : 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: i == page ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [_welcome(), _meals(), _notifications()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Step 1 ----------
  Widget _welcome() {
    final text = Theme.of(context).textTheme;
    return _StepLayout(
      button: FilledButton(onPressed: () => _goTo(1), child: const Text("Let's start")),
      children: [
        const SizedBox(height: 40),
        Center(child: Image.asset('assets/images/logo.png', width: 140, height: 140)),
        const SizedBox(height: 32),
        Text('Welcome to MedMinder', style: text.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          'MedMinder reminds you when to take your medicines, '
          'with one reminder for everything you take together.',
          style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Setting up takes about a minute.',
          style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ---------- Step 2 ----------
  Widget _meals() {
    final text = Theme.of(context).textTheme;
    return _StepLayout(
      button: FilledButton(onPressed: _saveMealTimes, child: const Text('Save and continue')),
      children: [
        const SizedBox(height: 24),
        Text('When do you usually eat?', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Reminders ring around your meals. Tap a meal to change its time.',
          style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        for (int i = 0; i < doseSlots.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              onTap: () => _pickMealTime(i),
              child: Row(
                children: [
                  IconBadge(doseSlots[i].icon, doseSlots[i].color, size: 60),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(doseSlots[i].mealName, style: text.titleMedium),
                        Text(
                          mealTimes[i].format(context),
                          style: text.headlineSmall?.copyWith(color: doseSlots[i].color),
                        ),
                      ],
                    ),
                  ),
                  Text('Change', style: text.labelLarge?.copyWith(color: AppColors.primary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---------- Step 3 ----------
  Widget _notifications() {
    final text = Theme.of(context).textTheme;
    final refused = notificationsAllowed == false;
    return _StepLayout(
      button: refused
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () async {
                    await openNotificationSettings();
                  },
                  child: const Text('Open notification settings'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _finish, child: const Text('Continue without reminders')),
              ],
            )
          : FilledButton.icon(
              onPressed: _askNotifications,
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Allow reminders'),
            ),
      children: [
        const SizedBox(height: 40),
        Center(
          child: IconBadge(
            refused ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
            refused ? AppColors.danger : AppColors.primary,
            size: 120,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          refused ? 'Reminders are turned off' : 'Allow reminders',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          refused
              ? 'Without notifications, MedMinder cannot remind you to take your medicines. '
                  'Tap "Open notification settings" and switch on "Allow notifications".'
              : 'MedMinder needs your permission to show reminders and play its sound.\n\n'
                  'On the next screen, tap "Allow".',
          style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// Scrollable content with a big button pinned at the bottom
class _StepLayout extends StatelessWidget {
  final List<Widget> children;
  final Widget button;

  const _StepLayout({required this.children, required this.button});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: children,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: SizedBox(width: double.infinity, child: button),
        ),
      ],
    );
  }
}
