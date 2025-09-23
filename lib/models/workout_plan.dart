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

    Map<String, dynamic> toMap() => {
    'name': name,
    'exerciseIds': exerciseIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory ExercisePlan.fromMap(Map<String, dynamic> m) => ExercisePlan(
    name: m['name'] as String,
    exerciseIds: (m['exerciseIds'] as List).cast<String>(),
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: m['updatedAt'] == null ? null : DateTime.parse(m['updatedAt'] as String),
  );

}
