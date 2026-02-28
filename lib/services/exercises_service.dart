import 'package:cloud_functions/cloud_functions.dart';

/// https://www.api-ninjas.com/api/exercises
class ExerciseApiItem {
  final String name;
  final String type;
  final String muscle;
  final String equipment;
  final String difficulty;
  final String instructions;

  const ExerciseApiItem({
    required this.name,
    required this.type,
    required this.muscle,
    required this.equipment,
    required this.difficulty,
    required this.instructions,
  });

  factory ExerciseApiItem.fromJson(Map<String, dynamic> j) => ExerciseApiItem(
        name: j['name'] ?? '',
        type: j['type'] ?? '',
        muscle: j['muscle'] ?? '',
        equipment: j['equipment'] ?? '',
        difficulty: j['difficulty'] ?? '',
        instructions: j['instructions'] ?? '',
      );

  String get stableId =>
      '${name.toLowerCase().trim()}|${muscle.toLowerCase()}|${equipment.toLowerCase()}';
}

class ExerciseApiService {
  ExerciseApiService({FirebaseFunctions? functions, String region = 'europe-west2'})
      : _callable = (functions ?? FirebaseFunctions.instanceFor(region: region))
            .httpsCallable('apiNinjasSearchExercises');

  final HttpsCallable _callable;

  Future<List<ExerciseApiItem>> search({
    String? name,
    String? muscle,
    String? type,
    String? difficulty,
  }) async {
    final res = await _callable.call({
      'name': name,
      'muscle': muscle,
      'type': type,
      'difficulty': difficulty,
    });

    final data = res.data;
    if (data is! List) return const [];

    return data
        .whereType<Map>()
        .map((m) => ExerciseApiItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }
}