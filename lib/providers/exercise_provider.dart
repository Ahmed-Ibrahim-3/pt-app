import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../services/exercises_service.dart';
import '../models/workout_plan.dart';
import '../models/workout_plan_assignment.dart';

class ExerciseHive {
  static const plansBox = 'exercise_plans';
  static const assignmentsBox = 'plan_assignments';
  static const sessionsBox = 'workout_sessions';
}

const apiNinjasKey = String.fromEnvironment('API_NINJAS_KEY');

final _plansBoxProvider =
    Provider<Box<ExercisePlan>>((_) => Hive.box<ExercisePlan>(ExerciseHive.plansBox));

final _assignBoxProvider =
    Provider<Box<PlanAssignment>>((_) => Hive.box<PlanAssignment>(ExerciseHive.assignmentsBox));

final exerciseApiProvider =
    Provider<ExerciseApiService>((_) => ExerciseApiService(apiNinjasKey));

class ExerciseFilter {
  final String query;
  final String? muscle;
  final String? type;
  final String? difficulty;
  const ExerciseFilter({this.query = '', this.muscle, this.type, this.difficulty});
  ExerciseFilter copyWith({String? query, String? muscle, String? type, String? difficulty}) =>
      ExerciseFilter(
        query: query ?? this.query,
        muscle: muscle ?? this.muscle,
        type: type ?? this.type,
        difficulty: difficulty ?? this.difficulty,
      );
}

final exerciseFilterProvider =
    StateProvider<ExerciseFilter>((_) => const ExerciseFilter());

final exerciseSearchResultsProvider = FutureProvider.autoDispose((ref) async {
  final f = ref.watch(exerciseFilterProvider);
  if ((f.query.trim().length < 2) && (f.muscle == null || f.muscle!.isEmpty)) {
    return <ExerciseApiItem>[];
  }
  return ref.read(exerciseApiProvider).search(
        name: f.query.trim().isEmpty ? null : f.query.trim(),
        muscle: f.muscle,
        type: f.type,
        difficulty: f.difficulty,
      );
});

class ExercisePlanRepo {
  ExercisePlanRepo(this.box);
  final Box<ExercisePlan> box;

  Stream<List<ExercisePlan>> watchAll() async* {
    List<ExercisePlan> snapshot() {
      final items = box.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    }
    yield snapshot();
    yield* box.watch().map((_) => snapshot());
  }

  Future<int> create({required String name, required List<String> exerciseIds}) async =>
      box.add(ExercisePlan(name: name, exerciseIds: exerciseIds, createdAt: DateTime.now()));

  Future<void> update(ExercisePlan plan, {String? name, List<String>? exerciseIds}) async {
    if (name != null) plan.name = name;
    if (exerciseIds != null) plan.exerciseIds = exerciseIds;
    plan.updatedAt = DateTime.now();
    await plan.save();
  }

  Future<void> delete(dynamic key) => box.delete(key);
}

final planRepoProvider = Provider((ref) => ExercisePlanRepo(ref.watch(_plansBoxProvider)));
final plansStreamProvider = StreamProvider<List<ExercisePlan>>(
  (ref) => ref.watch(planRepoProvider).watchAll(),
);

String _dateKey(DateTime local) {
  final d = DateTime(local.year, local.month, local.day);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd'; 
}

class AssignmentRepo {
  AssignmentRepo(this.box);
  final Box<PlanAssignment> box;

  Map<DateTime, PlanAssignment> _weekSnapshot(DateTime anyLocal) {
    final monday = DateTime(anyLocal.year, anyLocal.month, anyLocal.day)
        .subtract(Duration(days: anyLocal.weekday - DateTime.monday));
    final map = <DateTime, PlanAssignment>{};
    for (var i = 0; i < 7; i++) {
      final d = DateTime(monday.year, monday.month, monday.day + i);
      final a = box.get(_dateKey(d)); 
      if (a != null) map[d] = a;
    }
    return map;
  }

  Stream<Map<DateTime, PlanAssignment>> watchWeek(DateTime anyLocal) async* {
    yield _weekSnapshot(anyLocal);
    yield* box.watch().map((_) => _weekSnapshot(anyLocal));
  }

  Future<void> assign(DateTime dayLocal, int planKey) async {
    final d = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    await box.put(_dateKey(d), PlanAssignment(date: d, planKey: planKey)); 
  }

  Future<int> clearEverywhereForPlan(int planKey) async {
    var cleared = 0;
    for (final k in box.keys) {
      final a = box.get(k);
      if (a != null && a.planKey == planKey) {
        await box.delete(k);
        cleared++;
      }
    }
    return cleared;
  }


  Future<void> clear(DateTime dayLocal) async => box.delete(_dateKey(dayLocal));

  Future<void> setCompleted(DateTime dayLocal, bool completed) async {
    final a = box.get(_dateKey(dayLocal));
    if (a != null) {
      a.completed = completed;
      await a.save();
    }
  }
}


final assignmentRepoProvider =
    Provider((ref) => AssignmentRepo(ref.watch(_assignBoxProvider)));

final weekAssignmentsProvider = StreamProvider.family<Map<DateTime, PlanAssignment>, DateTime>(
  (ref, anyLocal) => ref.watch(assignmentRepoProvider).watchWeek(anyLocal),
);
