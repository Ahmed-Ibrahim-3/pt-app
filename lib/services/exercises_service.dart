import 'dart:convert';
import 'package:http/http.dart' as http;

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
  ExerciseApiService(this.apiKey);
  final String apiKey;

  static const _base = 'https://api.api-ninjas.com/v1';

  Future<List<ExerciseApiItem>> search({
    String? name,
    String? muscle,
    String? type,
    String? difficulty,
  }) async {
    final params = <String, String>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (muscle != null && muscle.trim().isNotEmpty) 'muscle': muscle.trim(),
      if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      if (difficulty != null && difficulty.trim().isNotEmpty) 'difficulty': difficulty.trim(),
    };

    final uri = Uri.parse('$_base/exercises').replace(queryParameters: params);
    final res = await http.get(uri, headers: {'X-Api-Key': apiKey});
    if (res.statusCode != 200) {
      throw Exception('Exercises API ${res.statusCode}: ${res.body}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    return list.map(ExerciseApiItem.fromJson).toList();
  }
}
