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

  PlanAssignment({
    required this.date,
    required this.planKey,
    this.completed = false,
  });
}
