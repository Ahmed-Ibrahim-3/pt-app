import 'package:hive/hive.dart';

part 'workout_plan.g.dart';

@HiveType(typeId: 2) 
class ExercisePlan extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  List<String> exerciseIds;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  DateTime? updatedAt;

  ExercisePlan({
    required this.name,
    required this.exerciseIds,
    required this.createdAt,
    this.updatedAt,
  });
}
