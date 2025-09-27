import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../services/chat_gemini.dart';

import '../providers/nutrition_provider.dart';
import '../providers/exercise_provider.dart';
import '../models/meal_model.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

enum _ChatIntent { meal, estimate, workout }

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const double _navOffset = 62.0; 

  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  late final GeminiChatService _gemini;
  final List<ChatTurn> _turns = [];
  final List<(Uint8List bytes, String mime)> _pendingMedia = [];
  bool _sending = false;

  _ChatIntent? _intent; 


  @override
  void initState() {
    super.initState();
    _gemini = GeminiChatService(
      systemInstruction: '''
You are a fitness & nutrition assistant. Be specific and quantitative.
- Propose meals with ingredient list (amount + unit) and per-ingredient macros, plus totals and a few low-impact swaps.
- If the user sends food text or images, estimate with confidence (0..1) and a brief disclaimer; then return the same structured meal.
- Propose workouts with sets, reps, RPE (0–10), optional restSeconds, and swaps (alternatives). Keep guidance conservative.
''',
    );
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Pick image'),
            onTap: () => Navigator.pop(ctx, 'image'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('Pick video'),
            onTap: () => Navigator.pop(ctx, 'video'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;

    XFile? file;
    if (choice == 'image') {
      file = await _picker.pickImage(source: ImageSource.gallery);
    } else {
      file = await _picker.pickVideo(source: ImageSource.gallery);
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
    setState(() => _pendingMedia.add((bytes, mime)));
  }

    Future<void> _sendAsync({
    required String? text,
    required List<(Uint8List bytes, String mime)> media,
    required bool nudgeMeal,
    required bool nudgeWorkout,
    required bool nudgeEstimateFromMedia,
  }) async {
    try {
      final resp = await _gemini.send(
        text: (text == null || text.trim().isEmpty) ? null : text.trim(),
        media: media,
        nudgeMeal: nudgeMeal,
        nudgeWorkout: nudgeWorkout,
        nudgeEstimateFromMedia: nudgeEstimateFromMedia,
      );
      if (!mounted) return;
      setState(() {
        _turns.add(resp);
        _pendingMedia.clear();
        _ctrl.clear();
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chat error: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  void _send() {
    if (_sending) return;

    final text = _ctrl.text;
    final hasMedia = _pendingMedia.isNotEmpty;

    if (text.trim().isEmpty && !hasMedia) return;

    final intent = _intent;
    _intent = null;

    final nudgeEstimate = (intent == _ChatIntent.estimate) || hasMedia;

    final nudgeMeal     = (intent == _ChatIntent.meal) && !hasMedia;
    final nudgeWorkout  = (intent == _ChatIntent.workout);

    setState(() {
      _sending = true;
      _turns.add(ChatTurn.user(text.trim().isEmpty ? null : text.trim(),
          media: List.of(_pendingMedia)));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendAsync(
        text: text,
        media: List.of(_pendingMedia),
        nudgeMeal: nudgeMeal,
        nudgeWorkout: nudgeWorkout,
        nudgeEstimateFromMedia: nudgeEstimate,
      );
    });
  }



  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _addMeal(MealSuggestionDetailed m) async {
    final db = await ref.read(readyMealDbProvider.future);

    final noteLines = <String>[];
    for (final i in m.ingredients) {
      noteLines.add('- ${i.name}: ${i.amount} ${i.unit}'
          ' | ${i.calories.toStringAsFixed(0)} kcal,'
          ' P${i.protein.toStringAsFixed(0)} C${i.carbs.toStringAsFixed(0)} F${i.fat.toStringAsFixed(0)}');
    }
    if (m.isEstimate) {
      noteLines.add('\nEstimation: ${(m.confidence ?? 0).toStringAsFixed(2)} confidence.'
          '${m.estimationNote != null ? " ${m.estimationNote}" : ""}');
    }
    if ((m.notes ?? '').isNotEmpty) noteLines.add('\n${m.notes!}');

    final meal = Meal(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: m.title,
      calories: m.totals.calories,
      protein: m.totals.protein,
      carbs: m.totals.carbs,
      fat: m.totals.fat,
      loggedAt: DateTime.now(),
      notes: noteLines.join('\n'),
    );
    await db.upsertMeal(meal);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m.isEstimate ? 'Estimated meal added to today' : 'Meal added to today')),
    );
  }

  Future<void> _addPlan(WorkoutPlanSuggestion p) async {
    final planRepo = ref.read(planRepoProvider);
    final assignRepo = ref.read(assignmentRepoProvider);

    final names = p.exercises.map((e) => e.name).toList();
    final key = await planRepo.create(name: p.name, exerciseIds: names);
    if (p.assignToToday) {
      await assignRepo.upsertPlanForDay(DateTime.now(), key);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Plan "${p.name}" saved${p.assignToToday ? " & assigned to today" : ""}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Coach')),
      body: Padding(
        padding: const EdgeInsets.only(bottom: _navOffset),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _turns.length,
                itemBuilder: (ctx, i) {
                  final t = _turns[i];
                  return _MessageBubble(
                    fromUser: t.fromUser,
                    text: t.text ?? '',
                    mediaCount: t.media.length,
                    meal: t.meal,
                    plan: t.plan,
                    onAddMeal: (m) => _addMeal(m),
                    onAddPlan: (p) => _addPlan(p),
                  );
                },
              ),
            ),

            if (_pendingMedia.isNotEmpty)
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(
                    _pendingMedia.length,
                    (i) => Chip(
                      label: Text(_pendingMedia[i].$2.split('/').last),
                      onDeleted: () => setState(() => _pendingMedia.removeAt(i)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.restaurant_menu, size: 18),
                        label: const Text('Meal'),
                        selected: _intent == _ChatIntent.meal,
                        onSelected: (sel) => setState(() {
                          _intent = sel ? _ChatIntent.meal : null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.image, size: 18),
                        label: const Text('Estimate'),
                        selected: _intent == _ChatIntent.estimate,
                        onSelected: (sel) => setState(() {
                          _intent = sel ? _ChatIntent.estimate : null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        avatar: const Icon(Icons.fitness_center, size: 18),
                        label: const Text('Workout'),
                        selected: _intent == _ChatIntent.workout,
                        onSelected: (sel) => setState(() {
                          _intent = sel ? _ChatIntent.workout : null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),

            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _sending ? null : _pickMedia,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Message the coach…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool fromUser;
  final String text;
  final int mediaCount;
  final MealSuggestionDetailed? meal;
  final WorkoutPlanSuggestion? plan;
  final void Function(MealSuggestionDetailed) onAddMeal;
  final void Function(WorkoutPlanSuggestion) onAddPlan;

  const _MessageBubble({
    required this.fromUser,
    required this.text,
    required this.mediaCount,
    required this.meal,
    required this.plan,
    required this.onAddMeal,
    required this.onAddPlan,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.82;
    final bg = fromUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceVariant;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty) Text(text),
            if (mediaCount > 0) ...[
              const SizedBox(height: 6),
              Text('Attached files: $mediaCount', style: Theme.of(context).textTheme.bodySmall),
            ],

            if (meal != null) ...[
              const Divider(),
              Text(meal!.isEstimate ? 'Estimated meal' : 'Meal suggestion',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(meal!.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...meal!.ingredients.map((i) => Text(
                    '• ${i.name} — ${i.amount} ${i.unit} '
                    '(${i.calories.toStringAsFixed(0)} kcal; '
                    'P${i.protein.toStringAsFixed(0)} C${i.carbs.toStringAsFixed(0)} F${i.fat.toStringAsFixed(0)})',
                  )),
              const SizedBox(height: 8),
              Text('Totals: ${meal!.totals.calories.toStringAsFixed(0)} kcal — '
                  'P ${meal!.totals.protein.toStringAsFixed(0)}g • '
                  'C ${meal!.totals.carbs.toStringAsFixed(0)}g • '
                  'F ${meal!.totals.fat.toStringAsFixed(0)}g'),
              if ((meal!.swaps).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Small swaps:', style: Theme.of(context).textTheme.bodyMedium),
                ...meal!.swaps.map((s) => Text('• ${s.name} — ${s.why} (${s.macroImpact})')),
              ],
              if (meal!.isEstimate && (meal!.estimationNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Note: ${meal!.estimationNote!}', style: Theme.of(context).textTheme.bodySmall),
              ],

              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(meal!.isEstimate ? 'Add estimated meal' : 'Add to today'),
                  onPressed: () => onAddMeal(meal!),
                ),
              ),
            ],

            if (plan != null) ...[
              const Divider(),
              Text('Workout plan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(plan!.name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...plan!.exercises.map((e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${e.name} — ${e.sets}×${e.reps}, RPE ${e.rpe.toStringAsFixed(1)}'
                       '${e.restSeconds != null ? ", rest ${e.restSeconds}s" : ""}'),
                  if (e.swaps.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12.0, top: 2),
                      child: Text('Swaps: ${e.swaps.join(", ")}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              )),
              if ((plan!.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(plan!.notes!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(plan!.assignToToday ? 'Save & assign today' : 'Save plan'),
                  onPressed: () => onAddPlan(plan!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
