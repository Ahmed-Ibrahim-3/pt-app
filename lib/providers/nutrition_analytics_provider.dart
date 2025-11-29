import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import '/models/meal_model.dart';
import '/providers/nutrition_provider.dart';

enum AnalyticsRange { week, month, year }

DateTime _floorDate(DateTime d) => DateTime(d.year, d.month, d.day);

extension _D on DateTime {
  String get ymd => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

class NutritionDailyTotals {
  final DateTime day;
  final double calories, protein, carbs, fat;
  NutritionDailyTotals({
    required this.day,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

class NutritionAverages {
  final int daysCounted;
  final double avgCalories, avgProtein, avgCarbs, avgFat;
  NutritionAverages({
    required this.daysCounted,
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.avgFat,
  });
}

DateTime _rangeStart(AnalyticsRange r) {
  final now = DateTime.now();
  switch (r) {
    case AnalyticsRange.week:
      return _floorDate(now).subtract(const Duration(days: 6));
    case AnalyticsRange.month:
      return _floorDate(now).subtract(const Duration(days: 29));
    case AnalyticsRange.year:
      return _floorDate(now).subtract(const Duration(days: 364));
  }
}

final nutritionDailyTotalsProvider =
    StreamProvider.family<List<NutritionDailyTotals>, AnalyticsRange>((ref, range) async* {
  final db = await ref.watch(readyMealDbProvider.future);
  await for (final meals in db.watchAllMeals()) {
    final start = _rangeStart(range);
    final end = _floorDate(DateTime.now());
    final buckets = <String, List<Meal>>{};
    for (final m in meals) {
      final d = _floorDate(m.loggedAt);
      if (d.isBefore(start) || d.isAfter(end)) continue;
      (buckets[d.ymd] ??= <Meal>[]).add(m);
    }
    final days = <NutritionDailyTotals>[];
    for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final list = buckets[d.ymd] ?? const <Meal>[];
      final cals = list.fold<double>(0, (a, m) => a + (m.calories));
      final p = list.fold<double>(0, (a, m) => a + (m.protein));
      final c = list.fold<double>(0, (a, m) => a + (m.carbs));
      final f = list.fold<double>(0, (a, m) => a + (m.fat));
      days.add(NutritionDailyTotals(day: d, calories: cals, protein: p, carbs: c, fat: f));
    }
    yield days;
  }
});

final nutritionAveragesProvider =
    Provider.family<NutritionAverages, List<NutritionDailyTotals>>((ref, daily) {
  final logged = daily.where((d) => d.calories > 0.0).toList();
  if (logged.isEmpty) {
    return NutritionAverages(daysCounted: 0, avgCalories: 0, avgProtein: 0, avgCarbs: 0, avgFat: 0);
  }
  double mean(num Function(NutritionDailyTotals d) sumGetter) =>
      logged.map(sumGetter).sum / math.max(1, logged.length);
  return NutritionAverages(
    daysCounted: logged.length,
    avgCalories: mean((d) => d.calories),
    avgProtein: mean((d) => d.protein),
    avgCarbs: mean((d) => d.carbs),
    avgFat: mean((d) => d.fat),
  );
});
