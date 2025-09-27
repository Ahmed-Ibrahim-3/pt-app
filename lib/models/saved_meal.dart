import 'package:hive/hive.dart';
import 'meal_model.dart';

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

  factory SavedMeal.fromMeal(Meal m, {String? forceId, String? overrideName}) {
    return SavedMeal(
      id: forceId ?? m.id,
      name: overrideName?.trim().isNotEmpty == true ? overrideName!.trim() : m.name,
      calories: m.calories,
      protein: m.protein,
      carbs: m.carbs,
      fat: m.fat,
      notes: m.notes,
    );
  }

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

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'notes': notes,
      };

  static SavedMeal fromMap(Map<String, dynamic> m) => SavedMeal(
        id: '${m['id']}',
        name: '${m['name']}',
        calories: (m['calories'] as num).toDouble(),
        protein: (m['protein'] as num).toDouble(),
        carbs: (m['carbs'] as num).toDouble(),
        fat: (m['fat'] as num).toDouble(),
        notes: m['notes'] as String?,
      );
}
