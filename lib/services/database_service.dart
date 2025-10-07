import 'package:hive/hive.dart';
import '../models/meal_model.dart';

class MealDatabaseService {
  Box<Meal>? _box;
  String? _uid;

  static String _boxNameFor(String? uid) => (uid == null || uid.isEmpty) ? 'meals_box_anon' : 'meals_box_$uid';

  Future<void> init({String? uid}) async {
  if (_uid != uid) {
      await _box?.close();
      _uid = uid;
      _box = await Hive.openBox<Meal>(_boxNameFor(uid));
    } else {
      _box ??= await Hive.openBox<Meal>(_boxNameFor(uid));
    }
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

   Future<void> close() async {
    await _box?.close();
    _box = null;
    _uid = null;
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
