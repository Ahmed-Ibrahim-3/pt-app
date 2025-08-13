import 'package:hive/hive.dart';

part 'meal_model.g.dart';

@HiveType(typeId: 1) 
class Meal extends HiveObject {
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
  DateTime loggedAt;

  @HiveField(7)
  String? notes;

  Meal({
    required this.id,
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.loggedAt,
    this.notes,
  });
}
