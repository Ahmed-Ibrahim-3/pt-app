import 'package:cloud_functions/cloud_functions.dart';

class FSFoodSummary {
  final String id;
  final String name;
  final String type;
  FSFoodSummary({required this.id, required this.name, required this.type});
}

class FSServing {
  final String id;
  final String description;
  final double calories, protein, carbs, fat;
  final double? metricAmount;
  final String? metricUnit;

  FSServing({
    required this.id,
    required this.description,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.metricAmount,
    this.metricUnit,
  });

  factory FSServing.fromJson(Map<String, dynamic> j) {
    double d(v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    return FSServing(
      id: '${j['serving_id'] ?? j['id'] ?? ''}',
      description: '${j['serving_description'] ?? j['description'] ?? ''}',
      calories: d(j['calories']),
      protein: d(j['protein']),
      carbs: d(j['carbohydrate']),
      fat: d(j['fat']),
      metricAmount: j['metric_serving_amount'] != null ? d(j['metric_serving_amount']) : null,
      metricUnit: j['metric_serving_unit']?.toString(),
    );
  }
}

class FSFoodDetails {
  final String id;
  final String name;
  final List<FSServing> servings;
  FSFoodDetails({required this.id, required this.name, required this.servings});
}

class NutritionService {
  NutritionService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'europe-west2');

  final FirebaseFunctions _functions;

  late final HttpsCallable _search = _functions.httpsCallable('fsSearchFoods');
  late final HttpsCallable _details = _functions.httpsCallable('fsGetFoodDetails');
  late final HttpsCallable _barcode = _functions.httpsCallable('fsGetFoodDetailsByBarcode');
  late final HttpsCallable _autocomplete = _functions.httpsCallable('fsAutocomplete');

  Future<List<FSFoodSummary>> searchFoods(String query, {int max = 20, int page = 0}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final res = await _search.call({'query': q, 'max': max, 'page': page});
    final list = (res.data as List).cast<Map>();
    return list
        .map((m) => FSFoodSummary(
              id: '${m['id'] ?? ''}',
              name: '${m['name'] ?? ''}',
              type: '${m['type'] ?? ''}',
            ))
        .toList(growable: false);
  }

  Future<List<String>> autocomplete(String expr, {int max = 8}) async {
    final q = expr.trim();
    if (q.isEmpty) return const [];
    final res = await _autocomplete.call({'expr': q, 'max': max});
    return (res.data as List).map((e) => '$e').toList(growable: false);
  }

  Future<FSFoodDetails> getFoodDetails(String foodId) async {
    final id = foodId.trim();
    if (id.isEmpty) throw ArgumentError('foodId is empty');
    final res = await _details.call({'foodId': id});
    final m = Map<String, dynamic>.from(res.data as Map);

    final servingsRaw = (m['servings'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return FSFoodDetails(
      id: '${m['id']}',
      name: '${m['name']}',
      servings: servingsRaw.map(FSServing.fromJson).toList(growable: false),
    );
  }

  Future<FSFoodDetails> getFoodDetailsByBarcode(String rawCode, {String? region, String? language}) async {
    final code = rawCode.trim();
    if (code.isEmpty) throw ArgumentError('barcode is empty');
    final res = await _barcode.call({'rawCode': code, 'region': region, 'language': language});
    final m = Map<String, dynamic>.from(res.data as Map);

    final servingsRaw = (m['servings'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return FSFoodDetails(
      id: '${m['id']}',
      name: '${m['name']}',
      servings: servingsRaw.map(FSServing.fromJson).toList(growable: false),
    );
  }
}