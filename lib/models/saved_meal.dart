import 'package:hive/hive.dart';
import '/models/meal_model.dart';

part 'saved_meal.g.dart';

@HiveType(typeId: 7)
class SavedMeal extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double calories;

  @HiveField(3)
  double protein;

  @HiveField(4)
  double carbs;

  @HiveField(5)
  double fat;

  @HiveField(6)
  String? notes;

  SavedMeal({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.notes,
  });

  Meal toMeal(DateTime loggedAt) => Meal(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        loggedAt: loggedAt,
        notes: notes,
      );
}
