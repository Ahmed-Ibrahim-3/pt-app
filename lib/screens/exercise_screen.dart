import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/providers/exercise_provider.dart';

import '/models/workout_plan.dart';

import '/services/pose_landmark_detection.dart';

import 'workout_viewer.dart';
import 'workout_editor.dart';
import 'workout_session.dart';
import 'exercise_analytics_screen.dart';

const int kRestPlanKey = -1;
enum _WorkoutsMenu { edit, delete }

DateTime _mondayOfWeek(DateTime local) {
  final diff = local.weekday - DateTime.monday;
  return DateTime(local.year, local.month, local.day).subtract(Duration(days: diff));
}

String _dowShort(DateTime d) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

String _parseNameFromStableId(String stableId) {
  final parts = stableId.split('|');
  return parts.isNotEmpty ? parts.first : stableId;
}

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key});
  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late DateTime _anchorMonday;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _anchorMonday = _mondayOfWeek(now);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _selectDay(DateTime d) {
    setState(() => _selectedDay = DateTime(d.year, d.month, d.day));
  }

  Future<void> _openAssignmentSheet(DateTime day) async {
    _selectDay(day);
    final plans = ref.read(plansStreamProvider).value ?? const <ExercisePlan>[];
    final chosen = await showModalBottomSheet<_AssignAction>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return _AssignmentSheet(
          day: day,
          plans: plans,
        );
      },
    );

    if (chosen == null) return;

    final repo = ref.read(assignmentRepoProvider);
    try {
      if (chosen is _AssignSetPlan) {
        await repo.assign(day, chosen.planKey); 
        await repo.setCompleted(day, false); 
      } else if (chosen is _AssignRest) {
        await repo.assign(day, kRestPlanKey); 
        await repo.setCompleted(day, false);
      } else if (chosen is _AssignClear) {
        await repo.clear(day);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Couldn’t update assignment: $e')));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final assignmentsAsync = ref.watch(weekAssignmentsProvider(_selectedDay));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise'),
        actions: [
          IconButton(
            tooltip: 'Analytics',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExerciseAnalyticsPage()));
            }, 
            icon: const Icon(Icons.show_chart))
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Week'),
            Tab(text: 'Workouts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final d = DateTime(_anchorMonday.year, _anchorMonday.month,
                        _anchorMonday.day + i);
                    final isSelected = _selectedDay.year == d.year &&
                        _selectedDay.month == d.month &&
                        _selectedDay.day == d.day;
                    final isToday = DateTime.now().year == d.year &&
                        DateTime.now().month == d.month &&
                        DateTime.now().day == d.day;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _selectDay(d), 
                        onLongPress: () => _openAssignmentSheet(d),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_dowShort(d),
                                  style: Theme.of(context).textTheme.labelMedium),
                              const SizedBox(height: 4),
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isToday
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                                child: Text(
                                  '${d.day}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              assignmentsAsync.when(
                data: (assignments) {
                  final a = assignments[_selectedDay];
                  if (a == null) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.event_busy),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Text('No plan assigned for this day')),
                              FilledButton(
                                onPressed: () => _openAssignmentSheet(_selectedDay),
                                child: const Text('Assign'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  if (a.planKey == kRestPlanKey) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                a.completed ? Icons.check_circle : Icons.self_improvement,
                                color: a.completed ? Colors.green : null,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('Rest day')),
                              TextButton(
                                onPressed: () => _openAssignmentSheet(_selectedDay),
                                child: const Text('Change'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final plans = ref.read(plansStreamProvider).value ?? const <ExercisePlan>[];
                  final plan = plans.firstWhere(
                    (p) => p.key == a.planKey,
                    orElse: () => ExercisePlan(
                        name: 'Unknown plan',
                        exerciseIds: const [],
                        createdAt: DateTime.now()),
                  );
                  
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  a.completed ? Icons.check_circle : Icons.schedule,
                                  color: a.completed ? Colors.green : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
                                ),
                                if (a.completed)
                                  FilledButton.icon(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => WorkoutSummaryPage(
                                            date: _selectedDay,
                                            planKey: a.planKey,
                                          ),
                                        ),
                                      );
                                      setState(() {}); 
                                    },
                                    icon: const Icon(Icons.visibility),
                                    label: const Text('View'),
                                  )
                                else
                                  FilledButton.icon(
                                    onPressed: plan.exerciseIds.isEmpty
                                        ? null
                                        : () async {
                                            if (!mounted) return;
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => WorkoutSessionPage(
                                                  date: _selectedDay,
                                                  planKey: a.planKey,
                                                ),
                                              ),
                                            );
                                            setState(() {}); 
                                          },
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Start'),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            if (plan.exerciseIds.isEmpty)
                              const Text(
                                  'This plan has no exercises yet. Edit it in the Workouts tab.')
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: -8,
                                children: plan.exerciseIds
                                    .map((id) => Chip(label: Text(_parseNameFromStableId(id))))
                                    .toList(),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children:[
                                 
                              if (a.completed && (a.location != null && a.location!.trim().isNotEmpty))
                                Row( 
                                  children: [
                                    const Icon(Icons.location_on, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Completed at: ${a.location!}',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis
                                    )
                                  ]
                                ),
                              const Spacer(),
                                TextButton(
                                onPressed: () => _openAssignmentSheet(_selectedDay),
                                child: const Text('Change assignment'),
                              ),
                              ]
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $e'),
                ),
              ),
              
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PoseCameraPage()),
                  );
                },
                icon: const Icon(Icons.hub_outlined),
                label: const Text('Pose Overlay'),
              ),


              const SizedBox(height: 8),

              Expanded(
                child: Center(
                  child: Text(
                    'Tip: long press a day to assign a plan or rest.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),

          _WorkoutsTab(onPlanEdited: () {
            setState(() {});
          }),
        ],
      ),
    );
  }
}

sealed class _AssignAction {}
class _AssignSetPlan extends _AssignAction {
  final int planKey;
  _AssignSetPlan(this.planKey);
}
class _AssignRest extends _AssignAction {}
class _AssignClear extends _AssignAction {}

class _AssignmentSheet extends StatelessWidget {
  const _AssignmentSheet({required this.day, required this.plans});
  final DateTime day;
  final List<ExercisePlan> plans;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Assign to $dateLabel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.self_improvement),
              title: const Text('Rest day'),
              onTap: () => Navigator.pop(context, _AssignRest()),
            ),
            const Divider(height: 1),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: plans.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = plans[i];
                    return ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(p.name),
                      subtitle: Text(
                        p.exerciseIds.isEmpty
                            ? 'No exercises yet'
                            : '${p.exerciseIds.length} exercise(s)',
                      ),
                      onTap: () => Navigator.pop(context, _AssignSetPlan(p.key as int)),
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Clear assignment'),
              onTap: () => Navigator.pop(context, _AssignClear()),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutsTab extends ConsumerWidget {
  const _WorkoutsTab({required this.onPlanEdited});
  final VoidCallback onPlanEdited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansStreamProvider);

    return Scaffold(
      body: plansAsync.when(
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No workout plans yet.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PlanEditorPage()),
                        );
                        onPlanEdited();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create a plan'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: plans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final p = plans[i];
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text(p.name),
                  subtitle: Text(
                    p.exerciseIds.isEmpty
                        ? 'No exercises yet'
                        : '${p.exerciseIds.length} exercise(s)',
                  ),
                  trailing: PopupMenuButton<_WorkoutsMenu>(
                    onSelected: (choice) async {
                      switch (choice) {
                        case _WorkoutsMenu.edit:
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => PlanEditorPage(existing: p)),
                          );
                          onPlanEdited();
                          break;
                        case _WorkoutsMenu.delete:
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete plan?'),
                              content: Text('This will remove "${p.name}". Any days assigned to it will be cleared.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                              ],
                            ),
                          );
                          if (confirm != true) return;

                          final planKey = p.key as int;
                          final cleared = await ref.read(assignmentRepoProvider).clearEverywhereForPlan(planKey);
                          await ref.read(planRepoProvider).delete(planKey);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Deleted "${p.name}" • cleared $cleared assignment(s).')),
                            );
                          }
                          onPlanEdited();
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _WorkoutsMenu.edit, child: Text('Edit')),
                      PopupMenuItem(value: _WorkoutsMenu.delete, child: Text('Delete')),
                    ],
                  ),

                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlanEditorPage()),
          );
          onPlanEdited();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Workout'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
