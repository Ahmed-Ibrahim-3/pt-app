import 'package:hive/hive.dart';
import '../models/meal_model.dart';

class MealDatabaseService {
  static const _boxName = 'meals_box';
  Box<Meal>? _box;

  Future<void> init() async {
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(MealAdapter());
  }
  _box ??= await Hive.openBox<Meal>(_boxName);
  }

  Box<Meal> get _requireBox {
    final b = _box;
    if (b == null) {
      throw StateError('MealDatabaseService not initialized. Call init() first.');
    }
    return b;
  }

  Future<void> upsertMeal(Meal meal) async {
    final box = _requireBox;
    await box.put(meal.id, meal);
  }

  Future<void> deleteMeal(String id) async {
    final box = _requireBox;
    await box.delete(id);
  }

  List<Meal> getAllMeals() {
    final box = _requireBox;
    return box.values.toList()..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  List<Meal> getMealsForDay(DateTime day) {
    final box = _requireBox;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return box.values
        .where((m) => !m.loggedAt.isBefore(start) && m.loggedAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  Stream<List<Meal>> watchAllMeals() async* {
    final box = _requireBox;
    yield getAllMeals();
    yield* box.watch().map((_) => getAllMeals());
  }

  Stream<List<Meal>> watchMealsForDay(DateTime day) async* {
    final box = _requireBox;
    yield getMealsForDay(day);
    yield* box.watch().map((_) => getMealsForDay(day));
  }

  Future<void> clearAll() async {
    final box = _requireBox;
    await box.clear();
  }

  List<Map<String, dynamic>> exportAll() => getAllMeals().map((m) => m.toMap()).toList();

  Future<void> replaceAll(List<Map<String, dynamic>> meals) async {
    final box = _requireBox;
    await box.clear();
    for (final m in meals) {
      final meal = Meal.fromMap(m);
      await box.put(meal.id, meal);
    }
  }

}
