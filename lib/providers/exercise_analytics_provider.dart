import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:pt/providers/workout_provider.dart';
import '/models/workout_session.dart';

enum ExRange { month, year } 

class VolumeSnapshot {
  final DateTime day;
  final double volume;
  final int sets;
  final int reps;
  VolumeSnapshot({required this.day, required this.volume, required this.sets, required this.reps});
}

class ExerciseTotals {
  final int workouts;
  final int sets;
  final int reps;
  final double volume;
  ExerciseTotals({required this.workouts, required this.sets, required this.reps, required this.volume});
}

class MuscleSplit {
  final Map<String, double> byMuscle; 
  MuscleSplit(this.byMuscle);
}

const Map<String, String> kDefaultExerciseMuscle = {
  'bench_press': 'Chest',
  'incline_bench_press': 'Chest',
  'overhead_press': 'Shoulders',
  'push_up': 'Chest',
  'dips': 'Chest',
  'barbell_row': 'Back',
  'lat_pulldown': 'Back',
  'pull_up': 'Back',
  'seated_row': 'Back',
  'deadlift': 'Back',
  'back_squat': 'Quads',
  'front_squat': 'Quads',
  'leg_press': 'Quads',
  'romanian_deadlift': 'Hamstrings',
  'leg_curl': 'Hamstrings',
  'calf_raise': 'Calves',
  'barbell_curl': 'Biceps',
  'dumbbell_curl': 'Biceps',
  'tricep_pushdown': 'Triceps',
  'skullcrusher': 'Triceps',
  'plank': 'Core',
  'hanging_leg_raise': 'Core',
};

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
String _muscleFor(String stableID) { 
  final parts = stableID.toLowerCase().split('|').map((s) => s.trim()).toList();
  if (parts.length >= 2 && parts [1].isNotEmpty) {
    final m = parts[1];
    switch (m) {
      case 'biceps':
        return 'Biceps';
      case 'triceps':
        return 'Triceps';
      case 'chest':
        return 'Chest';
      case 'back':
        return 'Back';
      case 'shoulders':
      case 'delts':
        return 'Shoulders';
      case 'quads':
      case 'quadriceps':
        return 'Quads';
      case 'hamstrings':
        return 'Hamstrings';
      case 'glutes':
        return 'Glutes';
      case 'calves':
        return 'Calves';
      case 'core':
      case 'abs':
        return 'Core';
    }
    return _cap(m);
    }
    final name = parts.isNotEmpty ? parts.first : stableID.toLowerCase();
    for (final entry in kDefaultExerciseMuscle.entries) { if (name.contains(entry.key)) return entry.value;}
    return 'Other';
  }

DateTime _floor(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime rangeStart(ExRange r) {
  final now = DateTime.now();
  switch (r) {
    case ExRange.month:
      return _floor(now).subtract(const Duration(days: 29));
    case ExRange.year:
      return _floor(now).subtract(const Duration(days: 364));
  }
}


final workoutSessionsStreamProvider = allSessionsProvider;

final exerciseDailyVolumeProvider =
    Provider.family<List<VolumeSnapshot>, ExRange>((ref, range) {
  final all = ref.watch(workoutSessionsStreamProvider).value ?? const <WorkoutSession>[];
  final start = rangeStart(range);
  final end = _floor(DateTime.now());
  final map = <String, VolumeSnapshot>{};

  double vOfSet(SetEntry s) => (s.weight) * (s.reps);
  for (final session in all) {
    final d = _floor(session.date);
    if (d.isBefore(start) || d.isAfter(end)) continue;

    int sets = 0, reps = 0;
    double volume = 0.0;
    for (final e in session.entries) {
      for (final s in e.sets) {
        if (s.reps > 0 && s.weight > 0) {
          sets += 1;
          reps += s.reps;
          volume += vOfSet(s);
        }
      }
    }
    final key = '${d.year}-${d.month}-${d.day}';
    final prev = map[key];
    if (prev == null) {
      map[key] = VolumeSnapshot(day: d, volume: volume, sets: sets, reps: reps);
    } else {
      map[key] = VolumeSnapshot(
        day: d,
        volume: prev.volume + volume,
        sets: prev.sets + sets,
        reps: prev.reps + reps,
      );
    }
  }

  final out = <VolumeSnapshot>[];
  for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final k = '${d.year}-${d.month}-${d.day}';
    out.add(map[k] ?? VolumeSnapshot(day: d, volume: 0, sets: 0, reps: 0));
  }
  return out;
});

final exerciseTotalsProvider = Provider.family<ExerciseTotals, List<VolumeSnapshot>>((ref, daily) {
  final workouts = daily.where((d) => d.sets > 0).length;
  final sets = daily.map((d) => d.sets).sum;
  final reps = daily.map((d) => d.reps).sum;
  final volume = daily.map((d) => d.volume).sum.toDouble();
  return ExerciseTotals(workouts: workouts, sets: sets, reps: reps, volume: volume);
});

final muscleSplitProvider = Provider.family<MuscleSplit, ExRange>((ref, range) {
  final all = ref.watch(workoutSessionsStreamProvider).value ?? const <WorkoutSession>[];
  final start = rangeStart(range);
  final end = _floor(DateTime.now());

  final sums = <String, double>{};
  double vOfSet(SetEntry s) => (s.weight) * (s.reps);

  for (final session in all) {
    final d = _floor(session.date);
    if (d.isBefore(start) || d.isAfter(end)) continue;

    for (final e in session.entries) {
      final muscle = _muscleFor(e.exerciseStableId);
      double vol = 0;
      for (final s in e.sets) {
        if (s.reps > 0 && s.weight > 0) vol += vOfSet(s);
      }
      if (vol <= 0) continue;
      sums[muscle] = (sums[muscle] ?? 0) + vol;
    }
  }
  return MuscleSplit(sums);
});

const kRadarAxes = <String>['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core'];

String _bucketForMuscle(String muscle) {
  final m = muscle.toLowerCase().trim();
  if (m.isEmpty) return 'Other';
  if (m == 'chest' || m.contains('pec')) return 'Chest';
  if (m == 'back' || m.contains('lats') || m.contains('trap')) return 'Back';
  if (m == 'shoulders' || m == 'delts' || m.contains('shoulder')) return 'Shoulders';
  if (m == 'biceps' || m == 'triceps' || m.contains('forearm') || m == 'arms') return 'Arms';
  if (m == 'quads' || m == 'quadriceps' || m == 'hamstrings' || m == 'glutes' || m == 'calves' || m == 'legs') return 'Legs';
  if (m == 'core' || m == 'abs' || m.contains('oblique') || m.contains('erector')) return 'Core';
  return 'Other';
}

Map<String, double> toRadarBuckets(Map<String, double> byMuscle) {
  final buckets = {for (final k in kRadarAxes) k: 0.0};
  byMuscle.forEach((muscle, vol) {
    final b = _bucketForMuscle(muscle);
    if (b != 'Other') buckets[b] = (buckets[b] ?? 0) + vol;
  });
  return buckets;
}

List<double> normalizedAxisValues(Map<String, double> buckets) {
  final ordered = [for (final k in kRadarAxes) (buckets[k] ?? 0)];
  final maxV = ordered.fold<double>(0, (a, b) => a > b ? a : b);
  if (maxV <= 0) return List<double>.filled(kRadarAxes.length, 0);
  return ordered.map((v) => v / maxV).toList();
}
