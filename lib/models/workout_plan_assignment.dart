import 'package:hive/hive.dart';

part 'workout_plan_assignment.g.dart';

@HiveType(typeId: 3)
class PlanAssignment extends HiveObject {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  int planKey;

  @HiveField(2)
  bool completed;

  @HiveField(3)
  String? location;

  PlanAssignment({
    required this.date,
    required this.planKey,
    this.completed = false,
    this.location,
  });

    Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(),
    'planKey': planKey,
    'completed': completed,
    'location': location,
  };

  factory PlanAssignment.fromMap(Map<String, dynamic> m) => PlanAssignment(
    date: DateTime.parse(m['date'] as String),
    planKey: (m['planKey'] as num).toInt(),
    completed: (m['completed'] ?? false) as bool,
    location: m['location'] as String?,
  );

}
