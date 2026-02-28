import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

const _primaryModel = 'gemini-2.0-flash';
const _fallbackModel = 'gemini-2.5-flash';

class Ingredient {
  final String name;
  final double amount;
  final String unit;
  final double calories, protein, carbs, fat;
  Ingredient({
    required this.name,
    required this.amount,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

class SwapOption {
  final String name;
  final String why;
  final String macroImpact;
  SwapOption({
    required this.name,
    required this.why,
    required this.macroImpact,
  });
}

class MealTotals {
  final double calories, protein, carbs, fat;
  MealTotals(this.calories, this.protein, this.carbs, this.fat);
}

double _asDouble(Object? v, {double orElse = 0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? orElse;
  return orElse;
}

T _mapCast<T>(Object? v, T fallback) {
  if (v is T) return v;
  if (v is Map) return Map<String, Object?>.from(v) as T;
  return fallback;
}

double _sum(Iterable<double> xs) => xs.fold(0.0, (a, b) => a + b);

class MealSuggestionDetailed {
  final String title;
  final List<Ingredient> ingredients;
  final MealTotals totals;
  final List<SwapOption> swaps;
  final bool isEstimate;
  final double? confidence;
  final String? estimationNote;
  final String? notes;
  MealSuggestionDetailed({
    required this.title,
    required this.ingredients,
    required this.totals,
    required this.swaps,
    this.isEstimate = false,
    this.confidence,
    this.estimationNote,
    this.notes,
  });
}

class WorkoutExercise {
  final String name;
  final int sets, reps;
  final double rpe;
  final int? restSeconds;
  final List<String> swaps;
  WorkoutExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.rpe,
    this.restSeconds,
    this.swaps = const [],
  });
}

class WorkoutPlanSuggestion {
  final String name;
  final List<WorkoutExercise> exercises;
  final bool assignToToday;
  final String? notes;
  WorkoutPlanSuggestion({
    required this.name,
    required this.exercises,
    this.assignToToday = false,
    this.notes,
  });
}

class ChatTurn {
  final bool fromUser;
  final String? text;
  final List<(Uint8List bytes, String mime)> media;
  final MealSuggestionDetailed? meal;
  final WorkoutPlanSuggestion? plan;
  ChatTurn.user(this.text, {this.media = const []})
      : fromUser = true,
        meal = null,
        plan = null;
  ChatTurn.model(this.text, {this.media = const [], this.meal, this.plan})
      : fromUser = false;
}

class GeminiChatService {
  final FirebaseFunctions _functions;
  final HttpsCallable _callable;

  final String? _systemInstruction;
  final List<Map<String, dynamic>> _history = [];

  GeminiChatService({
    String? systemInstruction,
    FirebaseFunctions? functions,
    String region = 'europe-west2',
  })  : _functions = functions ?? FirebaseFunctions.instanceFor(region: region),
        _systemInstruction = systemInstruction,
        _callable = (functions ?? FirebaseFunctions.instanceFor(region: region))
            .httpsCallable('geminiChat');

  Map<String, dynamic> _textPart(String text) => {'text': text};

  Map<String, dynamic> _inlineDataPart(Uint8List bytes, String mime) => {
        'inlineData': {
          'mimeType': mime,
          'data': base64Encode(bytes),
        }
      };

  bool _isRetryableFirebaseError(Object e) {
    if (e is FirebaseFunctionsException) {
      // Common transient cases
      return e.code == 'unavailable' ||
          e.code == 'resource-exhausted' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal';
    }
    final s = e.toString().toLowerCase();
    return s.contains('unavailable') ||
        s.contains('resource-exhausted') ||
        s.contains('deadline') ||
        s.contains('timeout') ||
        s.contains('503') ||
        s.contains('429');
  }

  Future<Map<String, dynamic>> _withRetry(
    Future<Map<String, dynamic>> Function() run,
  ) async {
    const delaysMs = [300, 700, 1400, 2400];
    Object? last;
    for (var i = 0; i < delaysMs.length; i++) {
      try {
        return await run();
      } catch (e) {
        last = e;
        if (!_isRetryableFirebaseError(e)) rethrow;
        await Future.delayed(Duration(milliseconds: delaysMs[i] + 50 * i));
      }
    }
    throw last ?? Exception('Unknown error');
  }

  Future<Map<String, dynamic>> _callGemini(List<Map<String, dynamic>> contents) async {
    final res = await _withRetry(() async {
      final out = await _callable.call({
        'model': _primaryModel,
        'fallbackModel': _fallbackModel,
        'systemInstruction': _systemInstruction,
        'contents': contents,
      });
      return Map<String, dynamic>.from(out.data as Map);
    });
    return res;
  }

  ChatTurn _parseToolCallToTurn(Map<String, Object?> m, String fnName) {
    switch (fnName) {
      case 'propose_meal':
      case 'estimate_meal_from_input':
        final isEstimate = fnName == 'estimate_meal_from_input';

        final ingredientsList = (m['ingredients'] as List?) ?? const [];
        final ings = ingredientsList.whereType<Map>().map((raw) {
          final mm = Map<String, Object?>.from(raw);
          return Ingredient(
            name: (mm['name'] as String? ?? '').trim(),
            amount: _asDouble(mm['amount']),
            unit: (mm['unit'] as String? ?? '').trim(),
            calories: _asDouble(mm['calories']),
            protein: _asDouble(mm['protein']),
            carbs: _asDouble(mm['carbs']),
            fat: _asDouble(mm['fat']),
          );
        }).toList();

        final totalsMap = _mapCast<Map<String, Object?>>(m['totals'], const {});
        final totals = (totalsMap.isNotEmpty)
            ? MealTotals(
                _asDouble(totalsMap['calories']),
                _asDouble(totalsMap['protein']),
                _asDouble(totalsMap['carbs']),
                _asDouble(totalsMap['fat']),
              )
            : MealTotals(
                _sum(ings.map((i) => i.calories)),
                _sum(ings.map((i) => i.protein)),
                _sum(ings.map((i) => i.carbs)),
                _sum(ings.map((i) => i.fat)),
              );

        final swaps = ((m['swaps'] as List?) ?? const [])
            .whereType<Map>()
            .map((raw) {
              final mm = Map<String, Object?>.from(raw);
              return SwapOption(
                name: (mm['name'] as String? ?? '').trim(),
                why: (mm['why'] as String? ?? '').trim(),
                macroImpact: (mm['macroImpact'] as String? ?? '').trim(),
              );
            })
            .toList();

        return ChatTurn.model(
          isEstimate ? 'Here’s an estimated breakdown.' : 'Here’s a detailed meal.',
          meal: MealSuggestionDetailed(
            title: ((m['title'] as String?) ?? '').trim(),
            ingredients: ings,
            totals: totals,
            swaps: swaps,
            isEstimate: isEstimate,
            confidence: (m['confidence'] as num?)?.toDouble(),
            estimationNote: m['estimationNote'] as String?,
            notes: m['notes'] as String?,
          ),
        );

      case 'propose_workout_plan':
        final rawEx = (m['exercises'] as List?) ?? const [];
        final ex = rawEx.whereType<Map>().map((eRaw) {
          final e = Map<String, dynamic>.from(eRaw);
          return WorkoutExercise(
            name: (e['name'] as String? ?? '').trim(),
            sets: (e['sets'] as num? ?? 0).toInt(),
            reps: (e['reps'] as num? ?? 0).toInt(),
            rpe: (e['rpe'] as num? ?? 0).toDouble(),
            restSeconds: (e['restSeconds'] as num?)?.toInt(),
            swaps: ((e['swaps'] as List?) ?? const [])
                .map((s) => s.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          );
        }).toList();

        return ChatTurn.model(
          'Here’s a structured plan.',
          plan: WorkoutPlanSuggestion(
            name: ((m['name'] as String?) ?? '').trim(),
            assignToToday: (m['assignToToday'] as bool?) ?? false,
            exercises: ex,
            notes: m['notes'] as String?,
          ),
        );

      default:
        return ChatTurn.model('(unknown tool call: $fnName)');
    }
  }

  Future<ChatTurn> send({
    String? text,
    List<(Uint8List bytes, String mime)> media = const [],
    bool nudgeMeal = false,
    bool nudgeWorkout = false,
    bool nudgeEstimateFromMedia = false,
  }) async {
    final parts = <Map<String, dynamic>>[];
    final hints = <String>[];

    if (nudgeEstimateFromMedia) {
      hints.add('If media or a food description is present, CALL estimate_meal_from_input.');
    }
    if (nudgeMeal) {
      hints.add(
        'If a concrete meal is requested, CALL propose_meal (ingredients, per-ingredient macros, totals, swaps).',
      );
    }
    if (nudgeWorkout) {
      hints.add(
        'If a workout is requested, CALL propose_workout_plan (sets, reps, RPE, optional restSeconds, swaps).',
      );
    }
    if (hints.isNotEmpty) {
      parts.add(_textPart('[TOOL_HINT]\n${hints.join("\n")}'));
    }
    if (text != null && text.trim().isNotEmpty) {
      parts.add(_textPart(text.trim()));
    }
    for (final (bytes, mime) in media) {
      parts.add(_inlineDataPart(bytes, mime));
    }

    final userContent = <String, dynamic>{'role': 'user', 'parts': parts};
    final request = <Map<String, dynamic>>[..._history, userContent];

    final data = await _callGemini(request);

    // Update conversation history (user msg + model msg) for next calls
    _history.add(userContent);
    final candidateContent = data['candidateContent'];
    if (candidateContent is Map) {
      _history.add(Map<String, dynamic>.from(candidateContent));
    }

    // Parse tool calls
    final rawCalls = (data['functionCalls'] as List?) ?? const [];
    if (rawCalls.isNotEmpty) {
      for (final c in rawCalls) {
        if (c is! Map) continue;
        final name = (c['name'] as String?) ?? '';
        final args = c['args'];
        final m = (args is Map) ? Map<String, Object?>.from(args) : <String, Object?>{};
        if (name.isNotEmpty) {
          return _parseToolCallToTurn(m, name);
        }
      }
    }

    // If we *really* wanted an estimate but didn't get a tool call,
    // do a second pass that enforces converting the message into estimate_meal_from_input.
    if (nudgeEstimateFromMedia) {
      final enforceMsg = _textPart(
        '[TOOL_ENFORCE] Convert the user message into a call to estimate_meal_from_input. '
        'Return ONLY the function call with: title, ingredients[{name,amount,unit,calories,protein,carbs,fat}], '
        'totals{calories,protein,carbs,fat}, 2-4 swaps[{name,why,macroImpact}], confidence (0..1), estimationNote.',
      );

      final enforceUser = <String, dynamic>{'role': 'user', 'parts': [enforceMsg]};
      final request2 = <Map<String, dynamic>>[..._history, enforceUser];

      final data2 = await _callGemini(request2);
      final calls2 = (data2['functionCalls'] as List?) ?? const [];
      if (calls2.isNotEmpty) {
        final c = calls2.first;
        if (c is Map) {
          final name = (c['name'] as String?) ?? '';
          final args = c['args'];
          final m = (args is Map) ? Map<String, Object?>.from(args) : <String, Object?>{};
          if (name == 'estimate_meal_from_input') {
            return _parseToolCallToTurn(m, name);
          }
        }
      }
    }

    final txt = (data['text'] as String?) ?? '(no response)';
    return ChatTurn.model(txt);
  }
}