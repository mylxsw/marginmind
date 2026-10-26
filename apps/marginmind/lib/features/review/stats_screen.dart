import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/l10n.dart';

/// Review log and due dates of one study set, or of all of them.
class ReviewStatsData {
  const ReviewStatsData({this.logs = const [], this.dues = const []});

  factory ReviewStatsData.of(Iterable<StudySetContent> contents) => ReviewStatsData(
    logs: [for (final c in contents) ...c.reviewLogs],
    dues: [for (final c in contents) ...c.scheduledDues],
  );

  final List<ReviewLog> logs;
  final List<DateTime> dues;
}

final reviewStatsDataProvider = FutureProvider.family<ReviewStatsData, String?>((ref, studySetId) async {
  if (studySetId != null) return ReviewStatsData.of([await ref.watch(contentProvider(studySetId).future)]);
  final repo = ref.watch(contentRepositoryProvider);
  final sets = await ref.watch(studySetsProvider.future);
  return ReviewStatsData.of(await Future.wait([for (final s in sets) repo.load(s.id)]));
});

/// Reviews per day, share remembered per day and cards due over the next
/// thirty days. Numbers and bars only; the titles are all the text there is.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key, required this.studySetId});

  final String? studySetId;

  void _back(WidgetRef ref) => ref.read(navigationProvider.notifier).back();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final data = ref.watch(reviewStatsDataProvider(studySetId)).value;
    final setTitle = studySetId == null ? null : ref.watch(studySetProvider(studySetId!))?.title;
    final now = ref.watch(clockProvider)();

    Widget body = const SizedBox.shrink();
    if (data != null) {
      final days = ReviewStats.daily(data.logs, now);
      final upcoming = ReviewStats.upcoming(data.dues, now);
      final windowLogs = days.fold<int>(0, (n, d) => n + d.reviewed);
      final windowKept = days.fold<int>(0, (n, d) => n + d.remembered);
      final retention = windowLogs == 0 ? null : windowKept / windowLogs;
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(MMSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatsSection(
                  key: const ValueKey('stats-reviewed'),
                  title: l.statsReviewed,
                  value: '${days.last.reviewed}',
                  child: _BarChart(
                    values: [for (final d in days) d.reviewed.toDouble()],
                    semanticLabel: l.statsReviewed,
                  ),
                ),
                const SizedBox(height: MMSpacing.xxl),
                _StatsSection(
                  key: const ValueKey('stats-retention'),
                  title: l.statsRetention,
                  value: retention == null ? '—' : '${(retention * 100).round()}%',
                  child: _BarChart(
                    values: [for (final d in days) d.retention ?? 0],
                    max: 1,
                    semanticLabel: l.statsRetention,
                  ),
                ),
                const SizedBox(height: MMSpacing.xxl),
                _StatsSection(
                  key: const ValueKey('stats-upcoming'),
                  title: l.statsUpcoming,
                  value: '${upcoming.fold<int>(0, (a, b) => a + b)}',
                  child: _BarChart(values: [for (final n in upcoming) n.toDouble()], semanticLabel: l.statsUpcoming),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MMWindowScaffold(
      sidebarVisible: false,
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      toolbar: MMToolbar(
        title: l.statistics,
        subtitle: setTitle,
        leading: MMIconButton(
          icon: MMIcons.chevronLeft,
          tooltip: studySetId == null ? l.showLibrary : l.backToStudySet,
          onPressed: () => _back(ref),
        ),
      ),
      body: ColoredBox(color: context.mmColors.windowBackground, child: body),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({super.key, required this.title, required this.value, required this.child});

  final String title;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.mmText;
    final c = context.mmColors;
    return Container(
      padding: const EdgeInsets.all(MMSpacing.l),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(MMRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: t.headline)),
              Text(value, key: const ValueKey('stats-value'), style: t.largeTitle),
            ],
          ),
          const SizedBox(height: MMSpacing.l),
          SizedBox(height: 96, child: child),
        ],
      ),
    );
  }
}

/// Equal-width bars on a baseline. A day without a value keeps a thin stub
/// so the timeline stays readable.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.values, required this.semanticLabel, this.max});

  final List<double> values;
  final double? max;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Semantics(
      label: semanticLabel,
      child: CustomPaint(
        size: Size.infinite,
        painter: BarChartPainter(values: values, max: max, bar: c.accent, stub: c.fill),
      ),
    );
  }
}

class BarChartPainter extends CustomPainter {
  const BarChartPainter({required this.values, required this.bar, required this.stub, this.max});

  final List<double> values;
  final double? max;
  final Color bar;
  final Color stub;

  /// Bar heights as a share of the chart height, 0–1.
  List<double> get fractions {
    final top = max ?? values.fold<double>(0, (a, b) => b > a ? b : a);
    return [for (final v in values) top <= 0 ? 0 : (v / top).clamp(0.0, 1.0)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const gap = 3.0;
    const stubHeight = 2.0;
    final width = (size.width - gap * (values.length - 1)) / values.length;
    final fractions = this.fractions;
    for (var i = 0; i < values.length; i++) {
      final left = i * (width + gap);
      final height = fractions[i] == 0 ? stubHeight : (size.height * fractions[i]).clamp(stubHeight, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, width, height),
          Radius.circular(width.clamp(0, 4) / 2),
        ),
        Paint()..color = fractions[i] == 0 ? stub : bar,
      );
    }
  }

  @override
  bool shouldRepaint(BarChartPainter old) =>
      old.values != values || old.max != max || old.bar != bar || old.stub != stub;
}
