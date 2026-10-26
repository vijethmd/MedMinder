import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'reminders.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/report_screen.dart';
import 'screens/take_medicines_screen.dart';
import 'theme.dart';

// Lets a tapped notification open a screen from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Time zone, notification channels and background alarms
  await initReminders();

  // Bring reminders and the weekly report up to date
  try {
    await refreshReminders();
    await checkWeeklyReport();
  } catch (e) {
    debugPrint('MedMinder: startup refresh failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final target = await launchTarget();

  // Run the app
  runApp(MedMinderApp(
    showSetup: !Settings.onboarded(prefs),
    launchTarget: target,
  ));
}

// Main App Widget
class MedMinderApp extends StatefulWidget {
  final bool showSetup;
  final NotificationTarget? launchTarget;

  const MedMinderApp({super.key, required this.showSetup, this.launchTarget});

  @override
  State<MedMinderApp> createState() => _MedMinderAppState();
}

class _MedMinderAppState extends State<MedMinderApp> {
  StreamSubscription<NotificationTarget>? _taps;

  @override
  void initState() {
    super.initState();
    // Reminder tapped while the app is running in the background
    _taps = notificationTaps.listen(_open);
    // Reminder tapped while the app was closed
    final target = widget.launchTarget;
    if (target != null && !widget.showSetup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(target));
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  void _open(NotificationTarget target) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final Widget screen;
    if (target.session != null) {
      screen = TakeMedicinesScreen(session: target.session!);
    } else if (target.report) {
      screen = const ReportScreen();
    } else {
      return;
    }
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedMinder',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: widget.showSetup ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
