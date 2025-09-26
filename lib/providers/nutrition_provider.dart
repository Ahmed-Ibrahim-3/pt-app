import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/models/meal_model.dart';
import '/models/saved_meal.dart';
import '/services/saved_meals_service.dart';
import '/services/database_service.dart';
import '/services/nutrition_service.dart';
import '/services/firestore_sync.dart';
import 'auth_provider.dart';

final mealDbProvider = Provider<MealDatabaseService>((ref) => MealDatabaseService());

final initMealsProvider = FutureProvider<void>((ref) async {
  final db = ref.read(mealDbProvider);
  final user = ref.watch(authStateProvider).value;
  await db.init(uid: user?.uid);
});

final readyMealDbProvider = FutureProvider<MealDatabaseService>((ref) async {
  final db = ref.read(mealDbProvider);
  final user = ref.watch(authStateProvider).value;
  await db.init(uid: user?.uid);
  ref.onDispose(() => db.close());
  return db;
});

class MealController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
  Future<void> addOrUpdateMeal(Meal meal) async {
    state = const AsyncLoading();
    try {
      await ref.read(mealDbProvider).upsertMeal(meal);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
    await ref.read(firestoreSyncProvider).pushMealsNow();
  }

  Future<void> deleteMeal(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(mealDbProvider).deleteMeal(id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
    await ref.read(firestoreSyncProvider).pushMealsNow();
  }
}
final mealControllerProvider =
    AsyncNotifierProvider<MealController, void>(() => MealController());

final mealsForTodayProvider = StreamProvider.autoDispose<List<Meal>>((ref) async* {
  final db = await ref.watch(readyMealDbProvider.future);
  yield* db.watchMealsForDay(DateTime.now());
});

final nutritionServiceProvider = Provider<NutritionService>((_) => NutritionService());

final foodSearchQueryProvider = StateProvider.autoDispose<String>((_) => '');

final foodAutocompleteProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final q = ref.watch(foodSearchQueryProvider);
  if (q.trim().length < 2) return const [];
  return ref.read(nutritionServiceProvider).autocomplete(q.trim(), max: 8);
});

final foodSearchResultsProvider = FutureProvider.autoDispose<List<FSFoodSummary>>((ref) async {
  final q = ref.watch(foodSearchQueryProvider);
  if (q.trim().isEmpty) return const [];
  return ref.read(nutritionServiceProvider).searchFoods(q.trim(), max: 20, page: 0);
});

final foodDetailsProvider =
    FutureProvider.family.autoDispose<FSFoodDetails, String>((ref, foodId) {
  return ref.read(nutritionServiceProvider).getFoodDetails(foodId);
});


final savedMealsDbProvider =
    Provider<SavedMealsDatabaseService>((ref) => SavedMealsDatabaseService());

final readySavedMealsDbProvider =
    FutureProvider<SavedMealsDatabaseService>((ref) async {
  final db = ref.read(savedMealsDbProvider);
  await db.init();
  return db;
});

final savedMealsProvider =
    StreamProvider.autoDispose<List<SavedMeal>>((ref) async* {
  final db = await ref.watch(readySavedMealsDbProvider.future);
  yield* db.watchAll();
});

class SavedMealController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await ref.read(savedMealsDbProvider).init();
  }

  Future<void> save(SavedMeal m) async {
    state = const AsyncLoading();
    try {
      await ref.read(savedMealsDbProvider).upsert(m);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(savedMealsDbProvider).delete(id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final savedMealControllerProvider =
    AsyncNotifierProvider<SavedMealController, void>(() => SavedMealController());