import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workout_plan.dart';
import '../providers/exercise_provider.dart';

class PlanEditorPage extends ConsumerStatefulWidget {
  const PlanEditorPage({super.key, this.existing});
  final ExercisePlan? existing;

  @override
  ConsumerState<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends ConsumerState<PlanEditorPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final Set<String> _selected = <String>{};
  String? _selectedMuscle;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _nameCtrl.text = p.name;
      _selected.addAll(p.exerciseIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(planRepoProvider);
    final resultsAsync = ref.watch(exerciseSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Workout' : 'Edit Plan'),
        actions: [
          TextButton(
            onPressed: () async {
              final name = _nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }
              if (_selected.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select at least one exercise')),
                );
                return;
              }
              if (widget.existing == null) {
                await repo.create(name: name, exerciseIds: _selected.toList());
              } else {
                await repo.update(widget.existing!,
                    name: name, exerciseIds: _selected.toList());
              }
              if (context.mounted)Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Plan name (e.g., Leg Day A)',
                prefixIcon: Icon(Icons.badge),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) {
                setState(() => _query = v);
                final f = ref.read(exerciseFilterProvider);
                ref.read(exerciseFilterProvider.notifier)
                    .state = f.copyWith(query: v);
              },
              decoration: const InputDecoration(
                labelText: 'Search exercises',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _MuscleGroupChips(
            selected: _selectedMuscle,
            onChanged: (m) {
              setState(() => _selectedMuscle = m);
              final f = ref.read(exerciseFilterProvider);
              ref.read(exerciseFilterProvider.notifier)
                  .state = f.copyWith(muscle: m);
            },
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tip: type at least 2 letters or pick a muscle.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              data: (items) {
                if ((items as List).isEmpty && (_query.trim().length < 2) && (_selectedMuscle == null)) {
                  return const Center(child: Text('Start typing or pick a muscle group'));
                }
                final list = items;
                if (list.isEmpty) {
                  return const Center(child: Text('No results. Try a more specific search.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final ex = list[i];
                    final picked = _selected.contains(ex.stableId);
                    return CheckboxListTile(
                      value: picked,
                      title: Text(ex.name),
                      subtitle: Text('${ex.muscle} • ${ex.equipment} • ${ex.difficulty}'),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {_selected.add(ex.stableId);}
                          else {_selected.remove(ex.stableId);}
                        });
                      },
                    );
                  },
                );
              },
              error: (e, _) => Center(child: Text('Error: $e')),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MuscleGroupChips extends StatelessWidget {
  const _MuscleGroupChips({required this.selected, required this.onChanged});
  final String? selected;
  final ValueChanged<String?> onChanged;

  static const groups = <String>[
    'abdominals','abductors','adductors','biceps','calves','chest','forearms',
    'glutes','hamstrings','lats','lower_back','middle_back','neck','quadriceps',
    'shoulders','traps','triceps'
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          const SizedBox(width: 8),
          ...groups.map((g) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g),
                  selected: selected == g,
                  onSelected: (_) => onChanged(g),
                ),
              )),
        ],
      ),
    );
  }
}
