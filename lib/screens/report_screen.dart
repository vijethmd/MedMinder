import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

// ========== WEEKLY REPORT ==========
// This week so far, plus every past week's summary
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  WeekSummary? thisWeek;
  List<WeekSummary> pastWeeks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await DoseLog.catchUp(await DBHelper.getMedicines(), prefs);
    final monday = mondayOf(today());
    final entries = await DoseLog.between(monday, today());

    // Only count doses whose time has already come
    final now = tz.TZDateTime.now(tz.local);
    final due = entries.where((e) {
      final time = sessionTime(prefs, e.session);
      final when = tz.TZDateTime(tz.local, e.date.year, e.date.month, e.date.day, time.hour, time.minute);
      return e.isTaken || !when.isAfter(now);
    });

    final history = await Reports.history();
    if (!mounted) return;
    setState(() {
      thisWeek = WeekSummary.fromEntries(monday, due);
      pastWeeks = history;
      isLoading = false;
    });
  }

  String _range(WeekSummary w) =>
      '${DateFormat('d MMM').format(w.weekStart)} – ${DateFormat('d MMM').format(w.weekEnd)}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly report')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                SectionHeader(
                  'This week so far',
                  subtitle: 'Since Monday ${DateFormat('d MMM').format(thisWeek!.weekStart)}',
                ),
                _WeekCard(summary: thisWeek!, emptyText: 'No doses due yet this week.'),

                const SectionHeader('Past weeks'),
                if (pastWeeks.isEmpty)
                  Text(
                    'Your first weekly report will appear here next Monday.',
                    style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                  )
                else
                  for (final week in pastWeeks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _WeekCard(summary: week, title: _range(week)),
                    ),
              ],
            ),
    );
  }
}

// Overall score, a big bar, then one row per medicine
class _WeekCard extends StatelessWidget {
  final WeekSummary summary;
  final String? title;
  final String emptyText;

  const _WeekCard({
    required this.summary,
    this.title,
    this.emptyText = 'No medicines were due this week.',
  });

  // Green when nearly everything was taken, amber for some, red for many missed
  static Color colorFor(int percent) {
    if (percent >= 90) return AppColors.success;
    if (percent >= 60) return AppColors.morning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = colorFor(summary.percent);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: text.titleMedium),
            const SizedBox(height: 10),
          ],
          if (summary.expected == 0)
            Text(emptyText, style: text.bodyLarge?.copyWith(color: AppColors.textMuted))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${summary.percent}%',
                    style: text.displaySmall?.copyWith(color: color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${summary.taken} of ${summary.expected} doses taken',
                      style: text.bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Bar(percent: summary.percent, color: color, height: 16),
            const SizedBox(height: 18),
            for (final med in summary.medicines)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(med.name, style: text.titleMedium)),
                        Text('${med.taken} / ${med.expected}', style: text.bodyLarge),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _Bar(percent: med.percent, color: colorFor(med.percent), height: 10),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final int percent;
  final Color color;
  final double height;

  const _Bar({required this.percent, required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$percent percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: percent / 100,
          minHeight: height,
          color: color,
          backgroundColor: AppColors.border,
        ),
      ),
    );
  }
}
