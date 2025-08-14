import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/exercise_provider.dart';
import '../models/workout_plan.dart';
import '../models/workout_plan_assignment.dart';
import '../screens/workout_editor.dart';

DateTime _mondayOfWeek(DateTime local) {
  final diff = local.weekday - DateTime.monday;
  return DateTime(local.year, local.month, local.day)
      .subtract(Duration(days: diff));
}

String _dateLabel(DateTime d) {
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]} ${d.day}/${d.month}';
}

extension IterableFirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key});
  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {}); 
      });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Week'), Tab(text: 'Workouts')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_WeekTab(), _PlansTab()],
      ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New Workout Plan'),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlanEditorPage()),
                );
              },
            )
          : null,
    );
  }
}

class _WeekTab extends ConsumerWidget {
  const _WeekTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final anchor = DateTime(now.year, now.month, now.day);
    final weekMapAsync = ref.watch(weekAssignmentsProvider(anchor));

    return weekMapAsync.when(
      data: (Map<DateTime, PlanAssignment> weekMap) {
        final monday = _mondayOfWeek(anchor);
        final days = List.generate(
          7,
          (i) => DateTime(monday.year, monday.month, monday.day + i),
        );
        final today = DateTime.now();

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _WeekStrip(days: days, weekMap: weekMap, today: today),
        );
      },
      error: (e, _) => Center(child: Text('Error: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({
    required this.days,
    required this.weekMap,
    required this.today,
  });

  final List<DateTime> days;
  final Map<DateTime, PlanAssignment> weekMap;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansStreamProvider).value ?? [];

    return SizedBox(
      height: 74, 
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = days[i];
          final assigned = weekMap[d];
          final planName = assigned == null
              ? '—'
              : (plans
                      .firstWhereOrNull((p) => (p.key as int) == assigned.planKey)
                      ?.name ??
                  '—');
          final isToday =
              d.year == today.year && d.month == today.month && d.day == today.day;

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final selected = await _showPlanPicker(context, ref);
              if (selected != null) {
                await ref
                    .read(assignmentRepoProvider)
                    .assign(d, selected.key as int);
              } else { 
                await ref.read(assignmentRepoProvider).clear(d);
              }
            },
            onLongPress: () =>
                ref.read(assignmentRepoProvider).clear(d), 
            child: Container(
              width: 110,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1],
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateLabel(d),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<ExercisePlan?> _showPlanPicker(BuildContext context, WidgetRef ref) async {
  final plans = await ref.read(plansStreamProvider.future);
  return showModalBottomSheet<ExercisePlan>(
    context: context,
    showDragHandle: true,
    builder: (_) => ListView.builder(
      itemCount: plans.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return ListTile(
            leading: const Icon(Icons.clear),
            title: const Text('Clear assignment'),
            onTap: () => Navigator.pop(context, null),
          );
        }
        final p = plans[i - 1];
        return ListTile(
          leading: const Icon(Icons.playlist_add_check),
          title: Text(p.name),
          subtitle: Text('${p.exerciseIds.length} exercises'),
          onTap: () => Navigator.pop(context, p),
        );
      },
    ),
  );
}

class _PlansTab extends ConsumerWidget {
  const _PlansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansStreamProvider);

    return plansAsync.when(
      data: (plans) {
        if (plans.isEmpty) {
          return Center(
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create your first Workout Plan'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlanEditorPage()),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: plans.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = plans[i];
            return ListTile(
              title: Text(p.name),
              subtitle: Text('${p.exerciseIds.length} exercises'),
              trailing: PopupMenuButton(
                onSelected: (value) async {
                  if (value == 'edit') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlanEditorPage(existing: p),
                      ),
                    );
                  } else if (value == 'delete') {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete plan?'),
                        content: Text('Delete "${p.name}" permanently?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await ref.read(planRepoProvider).delete(p.key);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            );
          },
        );
      },
      error: (e, _) => Center(child: Text('Error: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
