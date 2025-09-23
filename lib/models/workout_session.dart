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
  Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(),
    'planKey': planKey,
    'entries': entries.map((e) => e.toMap()).toList(),
  };

  factory WorkoutSession.fromMap(Map<String, dynamic> m) => WorkoutSession(
    date: DateTime.parse(m['date'] as String),
    planKey: (m['planKey'] as num).toInt(),
    entries: (m['entries'] as List).map((e) => WorkoutEntry.fromMap((e as Map).cast<String, dynamic>())).toList(),
    startedAt: (m['startedAt'] as String?) != null ? DateTime.parse(m['startedAt'] as String) : DateTime.now(),
  );
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
  Map<String, dynamic> toMap() => {
    'exerciseId': exerciseStableId,
    'sets': sets.map((s) => s.toMap()).toList(),
  };
  factory WorkoutEntry.fromMap(Map<String, dynamic> m) => WorkoutEntry(
    exerciseStableId: m['exerciseId'] as String,
    sets: (m['sets'] as List).map((s) => SetEntry.fromMap((s as Map).cast<String, dynamic>())).toList(),
  );
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

  Map<String, dynamic> toMap() => {'reps': reps, 'weight': weight, 'done': done};
  factory SetEntry.fromMap(Map<String, dynamic> m) => SetEntry(
    reps: (m['reps'] ?? 0) as int,
    weight: (m['weight'] ?? 0).toDouble(),
    done: (m['done'] ?? false) as bool,
  );
}
