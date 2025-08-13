import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import '/providers/nutrition_provider.dart';
import '/models/meal_model.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int? _stepCount;
  int? _heartRate;

  int _calorieGoal = 2400; 

  final Health health = Health();

  @override
  void initState() {
    super.initState();
  }

  // Future<void> _initAndFetch() async {
  //   final osOk = await _ensureAndroidRuntimePermissions();
  //   if (!osOk) return;
  // }

  // Future<bool> _ensureAndroidRuntimePermissions() async {
  //   if (!Platform.isAndroid) return true;

  //   final req = <Permission>[
  //     Permission.activityRecognition,
  //     Permission.sensors,
  //   ];

  //   final toRequest = <Permission>[];
  //   for (final p in req) {
  //     if (await p.status != PermissionStatus.granted) {
  //       toRequest.add(p);
  //     }
  //   }
  //   if (toRequest.isEmpty) return true;

  //   final results = await toRequest.request();
  //   return results.values.every((s) => s.isGranted);
  // }

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(initMealsProvider);

    return initAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Init failed: $e'))),
      data: (_) {
        final mealsAsync = ref.watch(mealsForTodayProvider);

        return mealsAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, st) => Scaffold(body: Center(child: Text('Meals error: $e'))),
          data: (meals) {
            double cal = 0, p = 0, c = 0, f = 0;
            for (final Meal m in meals) {
              cal += m.calories; p += m.protein; c += m.carbs; f += m.fat;
            }

            final int proteinGoal = (_calorieGoal * 0.30 / 4).round();
            final int carbsGoal = (_calorieGoal * 0.40 / 4).round();
            final int fatGoal = (_calorieGoal * 0.30 / 9).round();

            final int caloriesConsumed = cal.round();
            final int proteinGrams   = p.round();
            final int carbsGrams     = c.round();
            final int fatGrams       = f.round();

            final double calorieProgress =
                (caloriesConsumed / _calorieGoal).clamp(0.0, 1.0);
            final double proteinProgress =
                (proteinGrams / proteinGoal).clamp(0.0, 1.0);
            final double carbsProgress =
                (carbsGrams / carbsGoal).clamp(0.0, 1.0);
            final double fatProgress =
                (fatGrams / fatGoal).clamp(0.0, 1.0);

            return Scaffold(
              appBar: AppBar(
                title: Text('Welcome Back, User!', style: Theme.of(context).textTheme.titleLarge),
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                elevation: 0,
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildCalorieCard(
                    context,
                    caloriesConsumed,
                    _calorieGoal,
                    calorieProgress,
                    onEdit: _editCalorieGoal, 
                  ),
                  const SizedBox(height: 24),
                  Text('Macronutrients', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _buildMacroRow(context, proteinProgress, proteinGrams, proteinGoal, 'Protein', Colors.red),
                  const SizedBox(height: 12),
                  _buildMacroRow(context, carbsProgress, carbsGrams, carbsGoal, 'Carbs', Colors.blue),
                  const SizedBox(height: 12),
                  _buildMacroRow(context, fatProgress, fatGrams, fatGoal, 'Fat', Colors.amber),
                  const SizedBox(height: 24),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCalorieCard(
    BuildContext context,
    int consumed,
    int goal,
    double progress, {
    required VoidCallback onEdit,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 100, height: 100,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 100, height: 100,
                child: CircularProgressIndicator(
                  value: progress, strokeWidth: 8,
                  backgroundColor: Theme.of(context).progressIndicatorTheme.circularTrackColor,
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).progressIndicatorTheme.color!),
                ),
              ),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('$consumed', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22)),
                Text('kcal', style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ]),
          ),
          const SizedBox(width: 24),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Calories Remaining', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit goal',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${goal - consumed}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 28, color: Colors.lightGreenAccent)),
            Text('Goal: $goal kcal', style: Theme.of(context).textTheme.bodyMedium),
          ])
        ]),
      ),
    );
  }

  Widget _buildMacroRow(BuildContext context, double progress, int value, int goal, String label, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            Text('$value / ${goal}g', style: Theme.of(context).textTheme.bodyMedium),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0), minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ]),
      ),
    );
  }


  Future<void> _editCalorieGoal() async {
    final ctrl = TextEditingController(text: _calorieGoal.toString());
    final newGoal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calorie goal (kcal)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. 2400',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v != null && v > 0) {
                Navigator.pop(ctx, v);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newGoal != null && mounted) {
      setState(() => _calorieGoal = newGoal);
    }
  }

  Future<void> _debugLogMissingHCPerms(List<HealthDataType> types) async {
    for (final t in types) {
      final ok = await health.hasPermissions([t], permissions: [HealthDataAccess.READ]) ?? false;
      debugPrint('HC perm for $t: ${ok ? "granted" : "MISSING"}');
    }
  }
}
