import 'package:hive/hive.dart';

part 'workout_session.g.dart';

@HiveType(typeId: 4)
class WorkoutSession extends HiveObject {
  @HiveField(0)
  DateTime date; 

  @HiveField(1)
  int planKey;

  @HiveField(2)
  List<WorkoutEntry> entries;

  @HiveField(3)
  DateTime startedAt;

  @HiveField(4)
  DateTime? finishedAt;

  @HiveField(5)
  bool completed;

  WorkoutSession({
    required this.date,
    required this.planKey,
    required this.entries,
    required this.startedAt,
    this.finishedAt,
    this.completed = false,
  });
}

@HiveType(typeId: 5)
class WorkoutEntry {
  @HiveField(0)
  String exerciseStableId; 

  @HiveField(1)
  List<SetEntry> sets;

  @HiveField(2)
  bool done; 

  WorkoutEntry({
    required this.exerciseStableId,
    required this.sets,
    this.done = false,
  });
}

@HiveType(typeId: 6)
class SetEntry {
  @HiveField(0)
  int reps;

  @HiveField(1)
  double weight;

  @HiveField(2)
  bool done;

  SetEntry({this.reps = 0, this.weight = 0, this.done = false});
}
