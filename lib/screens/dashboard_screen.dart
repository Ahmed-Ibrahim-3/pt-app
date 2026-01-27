import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '/providers/nutrition_provider.dart';
import '/providers/exercise_provider.dart';
import '/providers/exercise_analytics_provider.dart';
import '/providers/settings_provider.dart';

import '/models/meal_model.dart';
import '/models/workout_plan_assignment.dart';

const int kRestPlanKey = -1;

final _allMealsProvider = StreamProvider<List<Meal>>((ref) async* {
  final db = await ref.watch(readyMealDbProvider.future);
  yield db.getAllMeals();
  yield* db.watchAllMeals();
});

final _assignmentsProvider = StreamProvider<List<PlanAssignment>>((ref) async* {
  final box = Hive.box<PlanAssignment>(ExerciseHive.assignmentsBox);
  yield box.values.toList(growable: false);
  yield* box.watch().map((_) => box.values.toList(growable: false));
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {

  int _calorieGoal = 2400;

  static const double _partialThreshold = 0.65;
  static const double _overThreshold = 1.35;

 
  static const _sleepKey = 'sleep_log_v1'; 
  Map<String, double> _sleepLog = {};
  final Map<String, TextEditingController> _sleepCtrls = {};
  bool _sleepLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSleep();
  }

  @override
  void dispose() {
    for (final c in _sleepCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<DateTime> _past7Dates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (int i = 6; i >= 0; i--) today.subtract(Duration(days: i))]; 
  }

  Future<void> _loadSleep() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_sleepKey);
    if (raw != null) {
      try {
        final m = Map<String, dynamic>.from(jsonDecode(raw));
        _sleepLog = m.map((k, v) => MapEntry(k, (v as num).toDouble()));
      } catch (_) {}
    }
    _ensureSleepControllers();
    if (mounted) setState(() => _sleepLoaded = true);
  }

  void _ensureSleepControllers() {
    for (final d in _past7Dates()) {
      final key = _ymd(d);
      _sleepCtrls.putIfAbsent(key, () => TextEditingController());
      _sleepCtrls[key]!.text = _sleepLog[key]?.toStringAsFixed(1) ?? '';
    }
  }

  Future<void> _saveSleepFor(DateTime day, String txt) async {
    final v = double.tryParse(txt.trim());
    if (v == null || v < 0 || v > 24) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter hours between 0 and 24')),
        );
      }
      return;
    }
    final sp = await SharedPreferences.getInstance();
    _sleepLog[_ymd(day)] = v;
    await sp.setString(_sleepKey, jsonEncode(_sleepLog));
    if (mounted) {
      _sleepCtrls[_ymd(day)]?.text = v.toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {
    final mealsTodayAsync = ref.watch(mealsForTodayProvider);
    final settings = ref.watch(settingsProvider);
    final displayName = settings.maybeWhen(
      data: (s) {
        final n = s.name.trim();
        return n.isEmpty ? 'User' : n.split(' ').first; 
      },
      orElse: () => 'User',
    );
    return Scaffold(
    appBar: AppBar(
      title: Text('Welcome Back, $displayName!', style: Theme.of(context).textTheme.titleLarge),),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              mealsTodayAsync.when(
                data: (mealsToday) => _buildTopCard(context, mealsToday),
                loading: () => const _SkeletonCard(height: 170),
                error: (_, _) => _ErrorCard(onRetry: () => setState(() {})),
              ),
              const SizedBox(height: 12), 
              _buildCalendarSection(context),
              const SizedBox(height: 12),
              const _MuscleRadarCard(),

              const SizedBox(height: 12),
              _buildSleepRowCard(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopCard(BuildContext context, List<Meal> mealsToday) {

    final targets = ref.watch(macroTargetsProvider);

    final consumedKcal = mealsToday.fold<double>(0, (a, m) => a + m.calories);
    final consumedP = mealsToday.fold<double>(0, (a, m) => a + m.protein);
    final consumedC = mealsToday.fold<double>(0, (a, m) => a + m.carbs);
    final consumedF = mealsToday.fold<double>(0, (a, m) => a + m.fat);

    final kcalGoal = targets.calories.toDouble().clamp(0, double.infinity);
    final remainingKcal = math.max(0.0, kcalGoal - consumedKcal);
    final pctKcal = kcalGoal <= 0 ? 0.0 : (consumedKcal / kcalGoal).clamp(0.0, 1.0);

    final remP = math.max(0.0, targets.proteinG - consumedP);
    final remC = math.max(0.0, targets.carbsG - consumedC);
    final remF = math.max(0.0, targets.fatG - consumedF);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _editCalorieGoal, 
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: pctKcal,
                            strokeWidth: 8,
                            backgroundColor: Theme.of(context)
                                .progressIndicatorTheme
                                .circularTrackColor,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).progressIndicatorTheme.color!,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              consumedKcal.toStringAsFixed(0),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontSize: 22),
                            ),
                            Text('kcal', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  '${remainingKcal.toStringAsFixed(0)} kcal remaining',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(width: 40),
            Expanded(
              child: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MacroBar(
                        label: 'Protein',
                        remaining: remP, goal: targets.proteinG.toDouble(), 
                        icon: Icons.fitness_center, units: 'g',
                        color: Colors.red,
                      ),
                      const SizedBox(width: 0),
                      _MacroBar(
                        label: 'Carbs',
                        remaining: remC, goal: targets.carbsG.toDouble(),
                        icon: Icons.grain, units: 'g',
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 0),
                      _MacroBar(
                        label: 'Fat',
                        remaining: remF, goal: targets.fatG.toDouble(),
                        icon: Icons.egg, units: 'g',
                        color: Colors.yellow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
        ),
      ),
    );
  }

  Widget _buildSleepRowCard() {
    final days = _past7Dates();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sleep (last 7 days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Column(
                    children: [
                      Text(DateFormat.E().format(d),
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 6),
                      AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Center(
                            child: TextFormField(
                              controller: _sleepCtrls[_ymd(d)],
                              enabled: _sleepLoaded,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}(\.\d{0,1})?$')),
                              ],
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                hintText: '—',
                              ),
                              onFieldSubmitted: (txt) => _saveSleepFor(d, txt),
                              onTapOutside: (_) => _saveSleepFor(d, _sleepCtrls[_ymd(d)]?.text ?? ''),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Today →',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCalendarSection(BuildContext context) {
    final mealsAsync = ref.watch(_allMealsProvider);
    final assignsAsync = ref.watch(_assignmentsProvider);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMM().format(DateTime.now()),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            mealsAsync.when(
              loading: () => const _SkeletonCalendar(),
              error: (_, _) => _ErrorInline(onRetry: () => setState(() {})),
              data: (allMeals) {
                return assignsAsync.when(
                  loading: () => const _SkeletonCalendar(),
                  error: (_, _) => _ErrorInline(onRetry: () => setState(() {})),
                  data: (assignments) {
                    final model = _buildMonthModel(allMeals, assignments);
                    return _MonthGrid(
                      model: model,
                      isToday: (d) {
                        final n = DateTime.now();
                        return d.year == n.year && d.month == n.month && d.day == n.day;
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

_MonthModel _buildMonthModel(List<Meal> allMeals, List<PlanAssignment> assignments) {
  final now = DateTime.now();
  final firstOfMonth = DateTime(now.year, now.month, 1);
  final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

  final Map<DateTime, double> kcalByDay = {};
  for (final m in allMeals) {
    final d = DateTime(m.loggedAt.year, m.loggedAt.month, m.loggedAt.day);
    if (d.month != now.month || d.year != now.year) continue;
    kcalByDay[d] = (kcalByDay[d] ?? 0) + m.calories;
  }

  final Set<DateTime> completedWorkoutDays = {};
  for (final a in assignments) {
    final d = DateTime(a.date.year, a.date.month, a.date.day);
    if (d.month != now.month || d.year != now.year) continue;

    final bool isWorkoutDay = (a.planKey != kRestPlanKey);
    final bool finished = (a.completed == true);

    if (isWorkoutDay && finished) {
      completedWorkoutDays.add(d);
    }
  }

  final entries = <_DayStatus>[];
  for (int i = 0; i < daysInMonth; i++) {
    final d = DateTime(now.year, now.month, i + 1);
    final kcal = kcalByDay[d] ?? 0.0;
    final hasFood = kcal > 0.0;

    bool foodPartial = false;
    bool foodOver = false;
    if (hasFood) {
      final ratio = _calorieGoal <= 0 ? 0.0 : (kcal / _calorieGoal);
      if (ratio > _overThreshold) {
        foodOver = true;
      } else if (ratio < _partialThreshold) {
        foodPartial = true;
      }
    }

    entries.add(_DayStatus(
      date: d,
      foodLogged: hasFood && !foodPartial,
      foodPartial: foodPartial,
      foodOver: foodOver,
      exerciseLogged: completedWorkoutDays.contains(d),
    ));
  }

  return _MonthModel(firstOfMonth: firstOfMonth, daysInMonth: daysInMonth, days: entries);
}

  Future<void> _editCalorieGoal() async {
    final controller = TextEditingController(text: _calorieGoal.toString());
    final newGoal = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set daily calorie goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.local_fire_department),
            suffixText: 'kcal',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, (v != null && v > 0) ? v : null);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newGoal != null && mounted) setState(() => _calorieGoal = newGoal);
  }
}

class _DayStatus {
  final DateTime date;
  final bool foodLogged;
  final bool foodPartial;
  final bool foodOver;
  final bool exerciseLogged;
  _DayStatus({
    required this.date,
    required this.foodLogged,
    required this.foodPartial,
    required this.foodOver,
    required this.exerciseLogged,
  });
}

class _MonthModel {
  final DateTime firstOfMonth;
  final int daysInMonth;
  final List<_DayStatus> days;
  _MonthModel({required this.firstOfMonth, required this.daysInMonth, required this.days});
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double remaining;
  final double goal;
  final IconData icon;
  final String units;
  final Color color;
  const _MacroBar({
    required this.label,
    required this.remaining,
    required this.goal,
    required this.icon,
    required this.units,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final trackHeight = 90.0;
    final pctRemaining = goal <= 0 ? 0.0 : (remaining / goal).clamp(0.0, 1.0);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: trackHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight * pctRemaining;
                  return Container(
                    width: 14, 
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        width: 14,
                        height: h,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8), top: Radius.circular(8)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text('${remaining.toStringAsFixed(0)}$units', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}


class _MuscleRadarCard extends ConsumerWidget {
  const _MuscleRadarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(muscleSplitProvider(ExRange.month));
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final buckets = toRadarBuckets(split.byMuscle);
    final values = normalizedAxisValues(buckets);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Muscle Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
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
                    getTitle: (i, angle) => RadarChartTitle(
                      text: kRadarAxes[i],
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
        ]),
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
    const startAngle = -math.pi / 2; 

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
  bool shouldRepaint(covariant _RadarGridPainter old) =>
      old.sides != sides ||
      old.rings != rings ||
      old.color != color ||
      old.outerOpacity != outerOpacity ||
      old.innerOpacity != innerOpacity;
}


class _MonthGrid extends StatelessWidget {
  final _MonthModel model;
  final bool Function(DateTime) isToday;
  const _MonthGrid({required this.model, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final weekday = model.firstOfMonth.weekday; 
    final firstWeekday = (weekday + 6) % 7; 
    final totalCells = firstWeekday + model.daysInMonth;
    final rows = (totalCells / 7.0).ceil();

    return Column(
      children: [
        _WeekdayHeader(),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 0,   
            crossAxisSpacing: 0,  
            childAspectRatio: 1,
          ),
          itemCount: rows * 7,
          itemBuilder: (context, index) {
            final dayIndex = index - firstWeekday;
            if (dayIndex < 0 || dayIndex >= model.daysInMonth) return const SizedBox.shrink();
            final status = model.days[dayIndex];
            return _CalendarDayTile(
              date: status.date,
              foodLogged: status.foodLogged,
              foodPartial: status.foodPartial,
              foodOver: status.foodOver,
              exerciseLogged: status.exerciseLogged,
              highlightToday: isToday(status.date),
            );
          },
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final List<String> labels = const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [for (final l in labels) Expanded(child: Center(child: Text(l, style: Theme.of(context).textTheme.labelMedium)))],
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  final DateTime date;
  final bool foodLogged;
  final bool foodPartial;
  final bool foodOver;
  final bool exerciseLogged;
  final bool highlightToday;
  const _CalendarDayTile({
    required this.date,
    required this.foodLogged,
    required this.foodPartial,
    required this.foodOver,
    required this.exerciseLogged,
    required this.highlightToday,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DayPainter(
          foodLogged: foodLogged,
          foodPartial: foodPartial,
          foodOver: foodOver,
          exerciseLogged: exerciseLogged,
          highlightToday: highlightToday,
        ),
        child: Center(child: Text('${date.day}', style: Theme.of(context).textTheme.labelSmall)),
      ),
    );
  }
}

class _DayPainter extends CustomPainter {
  final bool foodLogged;
  final bool foodPartial;
  final bool foodOver;
  final bool exerciseLogged;
  final bool highlightToday;
  _DayPainter({
    required this.foodLogged,
    required this.foodPartial,
    required this.foodOver,
    required this.exerciseLogged,
    required this.highlightToday,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(1);
    final rrect = RRect.fromRectAndRadius(inner, const Radius.circular(8));
    final triRect = inner.deflate(2);
    final double triRadius = 6.0;
    final foodPath = _roundedTriangle(
      Offset(triRect.left, triRect.top),
      Offset(triRect.right, triRect.bottom),
      Offset(triRect.left, triRect.bottom),
      triRadius,
    );
    final exercisePath = _roundedTriangle(
      Offset(triRect.left, triRect.top),
      Offset(triRect.right, triRect.top),
      Offset(triRect.right, triRect.bottom),
      triRadius,
    );

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawRRect(rrect, basePaint);

    canvas.save();
    canvas.clipRRect(rrect);

    if (exerciseLogged) {
      final paint = Paint()..color = Colors.green.withValues(alpha: 0.85);
      canvas.drawPath(exercisePath, paint);
    }

    if (foodLogged) {
      final paint = Paint()..color = Colors.blue.withValues(alpha: 0.85);
      canvas.drawPath(foodPath, paint);
      if (foodOver) {
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.blue.shade900
          ..strokeWidth = 2.0;
        canvas.drawPath(foodPath, outline);
      }
    } else if (foodPartial) {
      final dashPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.blue
        ..strokeWidth = 2.0;
      _dashPath(canvas, foodPath, dashPaint, 6, 4);
    }

    canvas.restore();

    if (highlightToday) {
      final highlight = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.red
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, highlight);
    }
  }

  Path _roundedTriangle(Offset a, Offset b, Offset c, double radius) {
    final pts = [a, b, c];
    final path = Path();

    for (int i = 0; i < 3; i++) {
      final p0 = pts[(i + 2) % 3];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 3];

      final v1 = (p0 - p1);
      final v2 = (p2 - p1);
      final l1 = v1.distance;
      final l2 = v2.distance;

      final r = math.min(radius, math.min(l1, l2) / 2.0);
      final p1a = p1 + (v1 / l1) * r;
      final p1b = p1 + (v2 / l2) * r;

      if (i == 0) {
        path.moveTo(p1a.dx, p1a.dy);
      } else {
        path.lineTo(p1a.dx, p1a.dy);
      }
      path.quadraticBezierTo(p1.dx, p1.dy, p1b.dx, p1b.dy);
    }

    path.close();
    return path;
  }

  void _dashPath(Canvas canvas, Path path, Paint paint, double dashLength, double gapLength) {
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(dashLength, metric.length - distance);
        final extract = metric.extractPath(distance, distance + next);
        canvas.drawPath(extract, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayPainter oldDelegate) {
    return foodLogged != oldDelegate.foodLogged ||
        foodPartial != oldDelegate.foodPartial ||
        foodOver != oldDelegate.foodOver ||
        exerciseLogged != oldDelegate.exerciseLogged ||
        highlightToday != oldDelegate.highlightToday;
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;
  const _SkeletonCard({required this.height});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: SizedBox(height: height, child: const Center(child: CircularProgressIndicator())),
    );
  }
}

class _SkeletonCalendar extends StatelessWidget {
  const _SkeletonCalendar();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorCard({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: SizedBox(
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Something went wrong'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ErrorInline extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorInline({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Text('Could not load calendar'),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
