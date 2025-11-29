import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '/providers/exercise_analytics_provider.dart';
import 'dart:math' as math;

class ExerciseAnalyticsPage extends ConsumerStatefulWidget {
  const ExerciseAnalyticsPage({super.key});

  @override
  ConsumerState<ExerciseAnalyticsPage> createState() => _ExerciseAnalyticsPageState();
}

class _ExerciseAnalyticsPageState extends ConsumerState<ExerciseAnalyticsPage> {
  ExRange _range = ExRange.month;

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(exerciseDailyVolumeProvider(_range));
    final totals = ref.watch(exerciseTotalsProvider(daily));
    final split = ref.watch(muscleSplitProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Analytics'),
        actions: [
          PopupMenuButton<ExRange>(
            onSelected: (v) => setState(() => _range = v),
            itemBuilder: (c) => const [
              PopupMenuItem(value: ExRange.month, child: Text('Past 30 days')),
              PopupMenuItem(value: ExRange.year, child: Text('Past 365 days')),
            ],
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _KpiRow(kpis: [
            _Kpi('Workouts', totals.workouts.toString()),
            _Kpi('Sets', totals.sets.toString()),
            _Kpi('Reps', totals.reps.toString()),
            _Kpi('Volume', totals.volume.toStringAsFixed(0)),
          ]),
          const SizedBox(height: 16),
          _MuscleRadar(byMuscle: split.byMuscle),
          const SizedBox(height: 16),
          _VolumeBar(daily: daily),
          const SizedBox(height: 16),
          _HistoryList(daily: daily),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<_Kpi> kpis;
  const _KpiRow({required this.kpis});
  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 12,
      spacing: 12,
      children: kpis.map((k) => Expanded(child: k)).toList(growable: false),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value;
  const _Kpi(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RadarGridBackground extends StatelessWidget {
  const _RadarGridBackground({
    this.sides = 6,
    this.rings = 5,
    required this.color,
    this.outerOpacity = 0.30,
    this.innerOpacity = 0.06,
  });

  final int sides;
  final int rings;
  final Color color;
  final double outerOpacity; 
  final double innerOpacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarGridPainter(
        sides: sides,
        rings: rings,
        color: color,
        outerOpacity: outerOpacity,
        innerOpacity: innerOpacity,
      ),
    );
  }
}

class _RadarGridPainter extends CustomPainter {
  _RadarGridPainter({
    required this.sides,
    required this.rings,
    required this.color,
    required this.outerOpacity,
    required this.innerOpacity,
  }) : assert(sides >= 3 && rings >= 1);

  final int sides;
  final int rings;
  final Color color;
  final double outerOpacity;
  final double innerOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6; 
    final startAngle = -math.pi / 2;

    for (int i = rings; i >= 1; i--) {
      final t = i / rings; 
      final r = radius * t;
      final a = innerOpacity + (outerOpacity - innerOpacity) * t;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (i == rings) ? 1.4 : 1.0 
        ..color = color.withValues(alpha: a);

      final path = Path();
      for (int k = 0; k < sides; k++) {
        final ang = startAngle + (2 * math.pi * k / sides);
        final p = Offset(center.dx + r * math.cos(ang), center.dy + r * math.sin(ang));
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarGridPainter oldDelegate) =>
      oldDelegate.sides != sides ||
      oldDelegate.rings != rings ||
      oldDelegate.color != color ||
      oldDelegate.outerOpacity != outerOpacity ||
      oldDelegate.innerOpacity != innerOpacity;
}


class _MuscleRadar extends StatelessWidget {
  final Map<String, double> byMuscle;
  const _MuscleRadar({required this.byMuscle});

  @override
  Widget build(BuildContext context) {
    final buckets = toRadarBuckets(byMuscle);
    final values = normalizedAxisValues(buckets);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Muscle Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _RadarGridBackground(
                    sides: kRadarAxes.length,
                    rings: 5,
                    color: onSurface,
                    outerOpacity: 0.28,
                    innerOpacity: 0.06,
                  ),
                  RadarChart(
                    RadarChartData(
                      radarShape: RadarShape.polygon,
                      ticksTextStyle: const TextStyle(fontSize: 0, color: Colors.transparent), 
                      gridBorderData: const BorderSide(color: Colors.transparent),
                      tickBorderData: const BorderSide(color: Colors.transparent),
                      radarBorderData: const BorderSide(color: Colors.transparent),
                      tickCount: 5,
                      titlePositionPercentageOffset: 0.10,
                      getTitle: (index, angle) => RadarChartTitle(
                        text: kRadarAxes[index],
                      ),
                      dataSets: [
                        RadarDataSet(
                          dataEntries: [for (final v in values) RadarEntry(value: v)],
                          entryRadius: 3,
                          borderWidth: 2,
                          fillColor: theme.colorScheme.primary.withValues(alpha: 0.20),
                          borderColor: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeBar extends StatelessWidget {
  final List<VolumeSnapshot> daily;
  const _VolumeBar({required this.daily});
  @override
  Widget build(BuildContext context) {
    final maxVol = daily.fold<double>(0, (m, d) => d.volume > m ? d.volume : m);
    final maxY = (maxVol <= 0 ? 1000 : maxVol * 1.15);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Daily Volume', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY.toDouble(),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (v) => FlLine(color: Colors.black12, strokeWidth: 1),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.black26),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('Volume (kg·reps)'),
                    axisNameSize: 18,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: maxY > 0 ? maxY / 4 : 1,
                      getTitlesWidget: (v, meta) => Text(v.round().toString(),
                          style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Date'),
                    axisNameSize: 16,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= daily.length) return const SizedBox.shrink();
                        if (idx == 0 || idx == (daily.length ~/ 2) || idx == daily.length - 1) {
                          final d = daily[idx].day;
                          return Text(DateFormat.Md().format(d), style: const TextStyle(fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < daily.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [BarChartRodData(toY: daily[i].volume)],
                    ),
                ],
              ),
            ),
          )

        ]),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<VolumeSnapshot> daily;
  const _HistoryList({required this.daily});
  @override
  Widget build(BuildContext context) {
    final recent = daily.where((d) => d.sets > 0 || d.reps > 0).toList().reversed.take(20).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Workout History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (recent.isEmpty) const Text('No workouts yet.'),
          for (final d in recent)
            ListTile(
              dense: true,
              title: Text('${d.day.year}-${d.day.month.toString().padLeft(2, '0')}-${d.day.day.toString().padLeft(2, '0')}'),
              subtitle: Text('Sets: ${d.sets} • Reps: ${d.reps} • Volume: ${d.volume.toStringAsFixed(0)}'),
            ),
        ]),
      ),
    );
  }
}
