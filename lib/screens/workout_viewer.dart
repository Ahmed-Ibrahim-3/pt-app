import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '/providers/workout_provider.dart';
import '/providers/exercise_provider.dart';
import '/models/workout_plan.dart';

class WorkoutSummaryPage extends ConsumerWidget {
  const WorkoutSummaryPage({
    super.key,
    required this.date,
    required this.planKey,
  });

  final DateTime date;
  final int planKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planBox = Hive.box<ExercisePlan>(ExerciseHive.plansBox);
    final title = planBox.get(planKey)?.name ?? 'Unknown Plan';

    final prettyDate =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final sessionAsync = ref.watch(sessionForDayProvider(date));

    return Scaffold(
      appBar: AppBar(title: Text('$title • $prettyDate')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading session: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('No saved session found for this day.'));
          }
          final entries = session.entries;
          if (entries.isEmpty) {
            return const Center(child: Text('This session has no entries.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final e = entries[i];
              final sets = e.sets;
              final exerciseLabel = e.exerciseStableId.split('|').first; 
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exerciseLabel, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (int s = 0; s < sets.length; s++) ...[
                        Row(
                          children: [
                            Text('Set ${s + 1}'),
                            const SizedBox(width: 12),
                            Text('${sets[s].reps} reps'),
                            const SizedBox(width: 12),
                            Text('${sets[s].weight.toStringAsFixed(1)} kg'),
                            const Spacer(),
                            if (sets[s].done) const Icon(Icons.check_circle, size: 18),
                          ],
                        ),
                        if (s != sets.length - 1) const Divider(height: 12),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
