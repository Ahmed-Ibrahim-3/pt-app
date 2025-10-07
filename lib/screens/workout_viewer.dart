import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '/providers/exercise_provider.dart';
import '/models/workout_session.dart';
import '/models/workout_plan.dart';

class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({
    super.key,
    required this.date,
    required this.planKey,
  });

  final DateTime date;
  final int planKey;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<WorkoutSession?> _loadSession() async {
    final box = Hive.box<WorkoutSession>(ExerciseHive.sessionsBox);
    try {
      return box.values.firstWhere(
        (s) => s.planKey == planKey && _sameDay(s.date, date),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {

    final planBox = Hive.box<ExercisePlan>(ExerciseHive.plansBox);
    final title = planBox.get(planKey)?.name ?? 'Unknown Plan';

    final prettyDate =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text('$title • $prettyDate')),
      body: FutureBuilder<WorkoutSession?>(
        future: _loadSession(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data;
          if (session == null) {
            return const Center(
              child: Text('No saved session found for this day.'),
            );
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.exerciseStableId.split('|').first,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                            if (sets[s].done)
                              const Icon(Icons.check_circle, size: 18),
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
