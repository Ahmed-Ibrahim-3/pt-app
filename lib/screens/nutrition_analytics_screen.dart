import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '/providers/nutrition_analytics_provider.dart';

class NutritionAnalyticsPage extends ConsumerStatefulWidget {
  const NutritionAnalyticsPage({super.key});

  @override
  ConsumerState<NutritionAnalyticsPage> createState() => _NutritionAnalyticsPageState();
}

class _NutritionAnalyticsPageState extends ConsumerState<NutritionAnalyticsPage> {
  AnalyticsRange _range = AnalyticsRange.week;


  @override
  Widget build(BuildContext context) {
    final dailyAsync = ref.watch(nutritionDailyTotalsProvider(_range));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Analytics'),
        actions: [
          PopupMenuButton<AnalyticsRange>(
            onSelected: (v) => setState(() => _range = v),
            itemBuilder: (c) => const [
              PopupMenuItem(value: AnalyticsRange.week, child: Text('Past 7 days')),
              PopupMenuItem(value: AnalyticsRange.month, child: Text('Past 30 days')),
              PopupMenuItem(value: AnalyticsRange.year, child: Text('Past 365 days')),
            ],
          )
        ],
      ),
      body: dailyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (daily) {
          final avg = ref.read(nutritionAveragesProvider(daily));
          final maxCals = daily.fold<double>(0, (m, d) => d.calories > m ? d.calories : m);
          final maxY = (maxCals <= 0 ? 500 : maxCals * 1.15);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _KpiRow(kpis: [
                _Kpi('Avg Calories', avg.avgCalories.round().toString()),
                _Kpi('Avg Protein', '${avg.avgProtein.toStringAsFixed(0)} g'),
                _Kpi('Avg Carbs', '${avg.avgCarbs.toStringAsFixed(0)} g'),
                _Kpi('Avg Fat', '${avg.avgFat.toStringAsFixed(0)} g'),
              ]),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily Calories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      
                      SizedBox(
                        height: 220,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: maxY.toDouble(),
                            clipData: const FlClipData.all(), 
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
                                axisNameWidget: const Text('Calories (kcal)'),
                                axisNameSize: 18,
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 44,
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
                                      return Text(DateFormat.Md().format(daily[idx].day),
                                          style: const TextStyle(fontSize: 10));
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                preventCurveOverShooting: true,
                                curveSmoothness: 0.25,
                                barWidth: 3,
                                spots: [
                                  for (int i = 0; i < daily.length; i++)
                                    FlSpot(i.toDouble(), daily[i].calories.toDouble()),
                                ],
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  cutOffY: 0,            
                                  applyCutOffY: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<_Kpi> kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final maxWidth = constraints.maxWidth;

        // 2 columns on phones, 4 on wider layouts/tablets
        final columns = maxWidth >= 600 ? 4 : 2;
        final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final k in kpis) SizedBox(width: itemWidth, child: k),
          ],
        );
      },
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
