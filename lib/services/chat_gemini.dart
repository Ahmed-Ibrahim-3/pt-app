import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
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
      : fromUser = true, meal = null, plan = null;
  ChatTurn.model(this.text, {this.media = const [], this.meal, this.plan})
      : fromUser = false;
}

class GeminiChatService {
  late final List<Tool> _tools;
  late final ToolConfig _toolConfig;
  late final Content _systemInstruction;

  late GenerativeModel _model;    
  late String _modelName;       
  late final String _fallbackName;

  final List<Content> _history = [];

  GeminiChatService({String? systemInstruction}) {
    _tools = [
      Tool(functionDeclarations: [
        FunctionDeclaration(
          'propose_meal',
          'Return a specific meal with ingredients, per-ingredient macros, totals, and low-impact swaps.',
          Schema.object(
            properties: {
              'title': Schema.string(description: 'Short, human-friendly meal title'),
              'ingredients': Schema.array(
                description: 'List of ingredients with amount, unit, per-ingredient macros',
                items: Schema.object(
                  properties: {
                    'name': Schema.string(),
                    'amount': Schema.number(),
                    'unit': Schema.string(description: 'g, ml, tbsp, cup, slice, etc.'),
                    'calories': Schema.number(),
                    'protein': Schema.number(),
                    'carbs': Schema.number(),
                    'fat': Schema.number(),
                  },
                  requiredProperties: ['name','amount','unit','calories','protein','carbs','fat'],
                ),
              ),
              'totals': Schema.object(
                properties: {
                  'calories': Schema.number(),
                  'protein': Schema.number(),
                  'carbs': Schema.number(),
                  'fat': Schema.number(),
                },
                requiredProperties: ['calories','protein','carbs','fat'],
              ),
              'swaps': Schema.array(
                description: 'Small substitutions with minimal macro impact',
                items: Schema.object(
                  properties: {
                    'name': Schema.string(),
                    'why': Schema.string(description: 'Reason for the swap'),
                    'macroImpact': Schema.string(description: 'Short summary, e.g., "~ -30 kcal, -2g fat"'),
                  },
                  requiredProperties: ['name','why','macroImpact'],
                ),
              ),
              'notes': Schema.string(description: 'Optional serving/prep notes'),
            },
            requiredProperties: ['title','ingredients','totals'],
          ),
        ),

        FunctionDeclaration(
          'estimate_meal_from_input',
          'Estimate a meal from the provided text and/or images with ingredient breakdown, totals, confidence and disclaimer.',
          Schema.object(
            properties: {
              'title': Schema.string(),
              'ingredients': Schema.array(
                items: Schema.object(
                  properties: {
                    'name': Schema.string(),
                    'amount': Schema.number(),
                    'unit': Schema.string(),
                    'calories': Schema.number(),
                    'protein': Schema.number(),
                    'carbs': Schema.number(),
                    'fat': Schema.number(),
                  },
                  requiredProperties: ['name','amount','unit','calories','protein','carbs','fat'],
                ),
              ),
              'totals': Schema.object(
                properties: {
                  'calories': Schema.number(),
                  'protein': Schema.number(),
                  'carbs': Schema.number(),
                  'fat': Schema.number(),
                },
                requiredProperties: ['calories','protein','carbs','fat'],
              ),
              'swaps': Schema.array(
                items: Schema.object(
                  properties: {
                    'name': Schema.string(),
                    'why': Schema.string(),
                    'macroImpact': Schema.string(),
                  },
                  requiredProperties: ['name','why','macroImpact'],
                ),
              ),
              'confidence': Schema.number(description: '0..1'),
              'estimationNote': Schema.string(description: 'Short disclaimer about estimation accuracy'),
              'notes': Schema.string(),
            },
            requiredProperties: ['title','ingredients','totals'],
          ),
        ),

        FunctionDeclaration(
          'propose_workout_plan',
          'Return a workout plan with sets, reps, RPE (0-10), optional rest, and exercise swaps.',
          Schema.object(
            properties: {
              'name': Schema.string(),
              'assignToToday': Schema.boolean(),
              'exercises': Schema.array(
                items: Schema.object(
                  properties: {
                    'name': Schema.string(),
                    'sets': Schema.integer(),
                    'reps': Schema.integer(),
                    'rpe': Schema.number(description: '0..10 scale'),
                    'restSeconds': Schema.integer(description: 'Optional rest time between sets'),
                    'swaps': Schema.array(items: Schema.string(), description: 'Alternative exercises'),
                  },
                  requiredProperties: ['name','sets','reps','rpe'],
                ),
              ),
              'notes': Schema.string(),
            },
            requiredProperties: ['name','exercises'],
          ),
        ),
      ]),
    ];

    _toolConfig =  ToolConfig(
      functionCallingConfig: FunctionCallingConfig(),
    );

    _systemInstruction = Content.text(systemInstruction ??
        '''
You are a helpful fitness & nutrition assistant. Use mainstream, trusted sports/nutrition science. 
Be specific and quantitative. If the user wants a concrete meal or workout, call a function to return structured data.

MEALS
- When proposing meals, include ingredients with amounts and per-ingredient macros (kcal, protein, carbs, fat).
- Also include totals, and 2–4 small low-impact swaps (with brief macro impact).
- If the user sends a description or image of food, estimate the meal via the estimation function and include a confidence 0..1 and a brief disclaimer.

WORKOUTS
- For each exercise, provide sets, reps, RPE (0-10), optional restSeconds, and 1–3 swaps (alternatives targeting similar muscles).
- Use conservative guidance for intensity. RPE is subjective and should align with how hard the user *feels* the effort (0=rest, 10=max).

Avoid extreme claims; do not diagnose conditions. Keep wording concise.
''');

    _modelName = _primaryModel;
    _fallbackName = _fallbackModel;
    _model = _makeModel(_modelName);
  }

  GenerativeModel _makeModel(String name) => GenerativeModel(
        model: name,
        apiKey: _geminiKey,
        tools: _tools,
        toolConfig: _toolConfig,
        systemInstruction: _systemInstruction,
      );

  Future<T> _withRetry<T>(Future<T> Function() run) async {
    const delays = [400, 900, 1800, 3200];  
    Object? lastErr;
    for (var i = 0; i < delays.length; i++) {
      try {
        return await run();
      } catch (e) {
        lastErr = e;
        final s = e.toString();
        final isOverloaded = s.contains('503') || s.contains('overloaded');
        final isQuota = s.contains('429') || s.contains('exhausted');
        if (!(isOverloaded || isQuota)) break;
        await Future.delayed(Duration(milliseconds: delays[i] + (50 * i)));
      }
    }
    throw lastErr ?? Exception('unknown error');
  }

  bool _isUnhandledContent(Object e) =>
      e.toString().contains('Unhandled format for Content');

  Future<ChatTurn> send({
    String? text,
    List<(Uint8List bytes, String mime)> media = const [],
    bool nudgeMeal = false,
    bool nudgeWorkout = false,
    bool nudgeEstimateFromMedia = false,
  }) async {
    final parts = <Part>[];
    final hints = <String>[];
    if (nudgeEstimateFromMedia) {
      hints.add('If media or a food description is present, CALL estimate_meal_from_input.');
    }
    if (nudgeMeal) {
      hints.add('If a concrete meal is requested, CALL propose_meal (ingredients, per-ingredient macros, totals, swaps).');
    }
    if (nudgeWorkout) {
      hints.add('If a workout is requested, CALL propose_workout_plan (sets, reps, RPE, optional restSeconds, swaps).');
    }
    if (hints.isNotEmpty) {
      parts.add(TextPart('[TOOL_HINT]\n${hints.join("\n")}'));
    }
    if (text != null && text.trim().isNotEmpty) {
      parts.add(TextPart(text.trim()));
    }
    for (final (bytes, mime) in media) {
      parts.add(DataPart(mime, bytes));
    }

    final request = <Content>[
      ..._history,
      Content('user', parts),
    ];

    GenerateContentResponse resp;
    try {
      resp = await _withRetry(() => _model.generateContent(request));
    } catch (e) {
      if (_isUnhandledContent(e)) {
        resp = await _withRetry(() => _model.generateContent(request));
      }
      else if (e.toString().contains('503') || e.toString().contains('overloaded')) {
        final fb = _makeModel(_fallbackName);
        resp = await _withRetry(() => fb.generateContent(request));
      } else {
        rethrow;
      }
    }

    _history.add(Content('user', parts));
    final modelContent = resp.candidates.first.content;
    _history.add(modelContent);

    final calls = resp.functionCalls;
    if (calls.isNotEmpty) {
      for (final f in calls) {
        final m = f.args;
        switch (f.name) {
          case 'propose_meal':
          case 'estimate_meal_from_input': {
            final isEstimate = f.name == 'estimate_meal_from_input';

            final ingredientsList = (m['ingredients'] as List?) ?? const [];
            final ings = ingredientsList
                .whereType<Map>()  
                .map((raw) {
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
                })
                .toList();

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
                title: (m['title'] as String).trim(),
                ingredients: ings,
                totals: totals,
                swaps: swaps,
                isEstimate: isEstimate,
                confidence: (m['confidence'] as num?)?.toDouble(),
                estimationNote: m['estimationNote'] as String?,
                notes: m['notes'] as String?,
              ),
            );
          }
          case 'propose_workout_plan': {
            final ex = (m['exercises'] as List)
                .cast<Map<String, dynamic>>()
                .map((e) => WorkoutExercise(
                      name: (e['name'] as String).trim(),
                      sets: (e['sets'] as num).toInt(),
                      reps: (e['reps'] as num).toInt(),
                      rpe: (e['rpe'] as num).toDouble(),
                      restSeconds: (e['restSeconds'] as num?)?.toInt(),
                      swaps: ((e['swaps'] as List?) ?? [])
                          .cast<String>()
                          .map((s) => s.trim())
                          .toList(),
                    ))
                .toList();

            return ChatTurn.model(
              'Here’s a structured plan.',
              plan: WorkoutPlanSuggestion(
                name: (m['name'] as String).trim(),
                assignToToday: (m['assignToToday'] as bool?) ?? false,
                exercises: ex,
                notes: m['notes'] as String?,
              ),
            );
          }
        }
        if (( calls.isEmpty) && nudgeEstimateFromMedia) {
          final enforceParts = <Part>[
            TextPart('[TOOL_ENFORCE] Convert the user message into a call to estimate_meal_from_input. '
                'Return ONLY the function call with: title, ingredients[{name,amount,unit,calories,protein,carbs,fat}], '
                'totals{calories,protein,carbs,fat}, 2-4 swaps[{name,why,macroImpact}], confidence (0..1), estimationNote.')
          ];

          final request2 = <Content>[
            ..._history,
            Content('user', enforceParts),
          ];

          GenerateContentResponse resp2;
          try {
            resp2 = await _withRetry(() => _model.generateContent(request2));
          } catch (e) {
            final fb = _makeModel(_fallbackName);
            resp2 = await _withRetry(() => fb.generateContent(request2));
          }

          final calls2 = resp2.functionCalls;
          if (calls2.isNotEmpty) {
            final f = calls2.first;
            final m = f.args;

            if (f.name == 'estimate_meal_from_input') {
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
                  }).toList();

              return ChatTurn.model(
                'Here’s an estimated breakdown.',
                meal: MealSuggestionDetailed(
                  title: (m['title'] as String).trim(),
                  ingredients: ings,
                  totals: totals,
                  swaps: swaps,
                  isEstimate: true,
                  confidence: (m['confidence'] as num?)?.toDouble(),
                  estimationNote: m['estimationNote'] as String?,
                  notes: m['notes'] as String?,
                ),
              );
            }
          }
        }

      }
    }

    final txt = resp.text ?? '(no response)';
    return ChatTurn.model(txt);
  }
}
