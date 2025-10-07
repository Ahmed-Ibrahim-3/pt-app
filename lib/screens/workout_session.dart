import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/workout_plan.dart';
import '/models/workout_session.dart';

import '/providers/exercise_provider.dart';
import '/providers/workout_provider.dart';
import '/providers/settings_provider.dart';

class WorkoutSessionPage extends ConsumerStatefulWidget {
  const WorkoutSessionPage({super.key, required this.date, required this.planKey});
  final DateTime date;
  final int planKey;

  @override
  ConsumerState<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends ConsumerState<WorkoutSessionPage> {
  WorkoutSession? _session;
  ExercisePlan? _plan;

  final _completedAtCtrl = TextEditingController();
  bool _seededCompletedAt = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _completedAtCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final plans = ref.read(plansStreamProvider).value ?? [];
    final p = plans.firstWhere(
      (e) => e.key == widget.planKey,
      orElse: () => ExercisePlan(name: 'Unknown plan', exerciseIds: const [], createdAt: DateTime.now()),
    );
    final repo = ref.read(workoutSessionRepoProvider);
    final s = await repo.startOrResume(
      dateLocal: widget.date,
      planKey: widget.planKey,
      exerciseStableIds: p.exerciseIds,
    );
    setState(() {
      _plan = p;
      _session = s;
    });
  }

  Future<void> _finish() async {
    final sessions = ref.read(workoutSessionRepoProvider);
    final locationText = _completedAtCtrl.text.trim();
    await ref.read(assignmentRepoProvider).setLocation(
      widget.date,
       locationText.isNotEmpty ? locationText : null
      );
    await sessions.complete(widget.date);
    await ref.read(assignmentRepoProvider).setCompleted(widget.date, true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ses = _session;
    final plan = _plan;

    if (ses == null || plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final settingsAsync = ref.watch(settingsProvider);
    settingsAsync.whenData((settings) {
      if (!_seededCompletedAt && _completedAtCtrl.text.isEmpty) {
        _completedAtCtrl.text = settings.defaultGym; 
        _seededCompletedAt = true;
      }
    });


    final canFinish = ses.entries.isNotEmpty && ses.entries.every((e) => e.done == true);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          IconButton(
            onPressed: canFinish ? _finish : null, 
            icon: const Icon(Icons.check),
            tooltip: 'Finish workout',
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: ses.entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final entry = ses.entries[i];
          final exName = _parseNameFromStableId(entry.exerciseStableId);
          return _ExerciseCard(
            name: exName,
            entry: entry,
            onChanged: (updated) async {
              ses.entries[i] = updated;
              await ref.read(workoutSessionRepoProvider).save(ses);
              setState(() {});
            },
            onInfo: () => _showInstructionsSheet(context, exName, entry.exerciseStableId),
          );
        },
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            elevation: 8,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _completedAtCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Completed at (optional)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canFinish ? _finish : null,
                    icon: const Icon(Icons.flag),
                    label: const Text('Finish workout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

    );
  }

  Future<void> _showInstructionsSheet(BuildContext context, String name, String stableId) async {
    final parts = stableId.split('|');
    final muscle = parts.length > 1 ? parts[1] : null;
    final api = ref.read(exerciseApiProvider);
    try {
      final results = await api.search(name: name, muscle: muscle);
      final first = results.isNotEmpty ? results.first : null;
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: first == null
              ? Text('No instructions found for $name.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(first.instructions),
                  ],
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading instructions: $e')));
    }
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    required this.name,
    required this.entry,
    required this.onChanged,
    required this.onInfo,
  });

  final String name;
  final WorkoutEntry entry;
  final ValueChanged<WorkoutEntry> onChanged;
  final VoidCallback onInfo;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  late WorkoutEntry _local;

  @override
  void initState() {
    super.initState();
    _local = WorkoutEntry(
      exerciseStableId: widget.entry.exerciseStableId,
      sets: widget.entry.sets.map((s) => SetEntry(reps: s.reps, weight: s.weight, done: s.done)).toList(),
      done: widget.entry.done,
    );
  }

  void _addSet() {
    setState(() => _local.sets.add(SetEntry()));
    widget.onChanged(_local);
  }

  void _removeSet() {
    setState(() {
      if (_local.sets.length > 1) {
        _local.sets.removeLast();
      }
    });
    widget.onChanged(_local);
  }

  void _toggleExercise(bool? v) {
    setState(() => _local.done = v ?? false);
    widget.onChanged(_local);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Checkbox(value: _local.done, onChanged: _toggleExercise),
              Expanded(
                child: Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (!_local.done)
                IconButton(
                  tooltip: 'Instructions',
                  onPressed: widget.onInfo,
                  icon: const Icon(Icons.info_outline),
                ),
            ]),
            const SizedBox(height: 8),

            if (!_local.done) ...[
              ...List.generate(_local.sets.length, (i) {
                final s = _local.sets[i];
                final done = s.done == true;
                final strike = done ? TextDecoration.lineThrough : TextDecoration.none;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text('Set ${i + 1}', style: TextStyle(decoration: strike)),
                      const SizedBox(width: 12),

                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: s.reps == 0 ? '' : s.reps.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Reps',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !done, 
                          style: TextStyle(decoration: strike), 
                          onChanged: (v) {
                            if (done) return; 
                            final reps = int.tryParse(v) ?? 0;
                            setState(() => _local.sets[i] = SetEntry(reps: reps, weight: s.weight, done: s.done));
                            widget.onChanged(_local);
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      SizedBox(
                        width: 110,
                        child: TextFormField(
                          initialValue: s.weight == 0 ? '' : s.weight.toStringAsFixed(1),
                          decoration: const InputDecoration(
                            labelText: 'Weight (kg)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          enabled: !done, 
                          style: TextStyle(decoration: strike), 
                          onChanged: (v) {
                            if (done) return; 
                            final w = double.tryParse(v) ?? 0;
                            setState(() => _local.sets[i] = SetEntry(reps: s.reps, weight: w, done: s.done));
                            widget.onChanged(_local);
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      Checkbox(
                        value: s.done,
                        onChanged: (v) {
                          setState(() {
                            _local.sets[i] = SetEntry(
                              reps: s.reps,
                              weight: s.weight,
                              done: v ?? false,
                            );
                          });
                          widget.onChanged(_local);
                        },
                      ),
                    ],
                  ),
                );
              }),

              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _addSet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add set'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _local.sets.length > 1 ? _removeSet : null,
                    icon: const Icon(Icons.remove),
                    label: const Text('Remove set'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _parseNameFromStableId(String stableId) {
  final parts = stableId.split('|');
  return parts.isNotEmpty ? parts.first : stableId;
}
