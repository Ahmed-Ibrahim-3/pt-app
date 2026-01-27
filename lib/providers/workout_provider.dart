import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/workout_session.dart';
import 'exercise_provider.dart';

String _dateKey(DateTime local) {
  final d = DateTime(local.year, local.month, local.day);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

class WorkoutSessionRepo {
  WorkoutSessionRepo(this.box);
  final Box<WorkoutSession> box;

  WorkoutSession? getForDay(DateTime local) => box.get(_dateKey(local));

  Future<WorkoutSession> startOrResume({
    required DateTime dateLocal,
    required int planKey,
    required List<String> exerciseStableIds,
  }) async {
    final key = _dateKey(dateLocal);
    final existing = box.get(key);
    if (existing != null && existing.planKey == planKey && existing.completed == false) {
      return existing;
    }
    final fresh = WorkoutSession(
      date: DateTime(dateLocal.year, dateLocal.month, dateLocal.day),
      planKey: planKey,
      entries: exerciseStableIds
          .map((id) => WorkoutEntry(exerciseStableId: id, sets: [SetEntry(), SetEntry(), SetEntry()]))
          .toList(),
      startedAt: DateTime.now(),
    );
    await box.put(key, fresh);
    return fresh;
  }

  Future<void> save(WorkoutSession s) => s.save();

  Future<void> complete(DateTime dateLocal) async {
    final s = box.get(_dateKey(dateLocal));
    if (s != null) {
      s.completed = true;
      s.finishedAt = DateTime.now();
      await s.save();
    }
  }

  Stream<WorkoutSession?> watchForDay(DateTime local) async* {
    final key = _dateKey(local);
    WorkoutSession? snap() => box.get(key);
    yield snap();
    yield* box.watch(key: key).map((_) => snap());
  }

  Stream<List<WorkoutSession>> watchAll() async* {
    List<WorkoutSession> snap() {
      final items = box.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date)); 
      return items;
    }
    yield snap();
    yield* box.watch().map((_) => snap());
  }
  
}

final workoutSessionRepoProvider = Provider<WorkoutSessionRepo>((ref) {
  final box = Hive.box<WorkoutSession>(ExerciseHive.sessionsBox);
  return WorkoutSessionRepo(box);
});

final workoutSessionForDayProvider =
    StreamProvider.family<WorkoutSession?, DateTime>((ref, day) {
  return ref.watch(workoutSessionRepoProvider).watchForDay(day);
});

final sessionForDayProvider =
    StreamProvider.family<WorkoutSession?, DateTime>((ref, date) {
  final repo = ref.watch(workoutSessionRepoProvider);
  return repo.watchForDay(date);
});

final allSessionsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final repo = ref.watch(workoutSessionRepoProvider);
  return repo.watchAll();
});