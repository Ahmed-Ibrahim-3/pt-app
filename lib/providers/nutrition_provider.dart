import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/models/meal_model.dart';
import '/services/database_service.dart';

final mealDbProvider = Provider<MealDatabaseService>((ref) {
  return MealDatabaseService();
});

final initMealsProvider = FutureProvider<void>((ref) async {
  final db = ref.read(mealDbProvider);
  await db.init();
});

final readyMealDbProvider = FutureProvider<MealDatabaseService>((ref) async {
  final db = ref.read(mealDbProvider);
  await db.init();
  return db;
});

final mealsForTodayProvider = StreamProvider<List<Meal>>((ref) async* {
  final db = await ref.watch(readyMealDbProvider.future); 
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  yield* db.watchMealsForDay(day);
});
class MealController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await ref.read(mealDbProvider).init();
  }

  Future<void> addOrUpdateMeal(Meal meal) async {
    state = const AsyncLoading();
    try {
      await ref.read(mealDbProvider).upsertMeal(meal);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow; 
    }
  }


  Future<void> deleteMeal(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(mealDbProvider).deleteMeal(id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final mealControllerProvider =
    AsyncNotifierProvider<MealController, void>(() => MealController());
