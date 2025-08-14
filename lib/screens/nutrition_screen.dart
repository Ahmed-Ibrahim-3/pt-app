import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '/models/meal_model.dart';
import '/providers/nutrition_provider.dart';

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initAsync = ref.watch(initMealsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openLogMealSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Log meal'),
      ),
      body: initAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Init failed: $e')),
        data: (_) {
          final mealsAsync = ref.watch(mealsForTodayProvider);
          return mealsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Failed to load meals: $e')),
            data: (meals) {
              final totals = _sumTotals(meals);
              final grouped = _groupByHour(meals);

              return RefreshIndicator(
                onRefresh: () async {},
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _TotalsHeader(totals: totals),
                    const SizedBox(height: 16),
                    _TimelineSection(
                      grouped: grouped,
                      onEditMeal: (meal) =>
                          _openLogMealSheet(context, ref, existing: meal),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openLogMealSheet(BuildContext context, WidgetRef ref, {Meal? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LogMealSheet(ref: ref, existing: existing),
    );
  }
}

/* ---------------------------- Totals + helpers ---------------------------- */

class _Totals {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const _Totals({this.calories = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  _Totals add(Meal m) => _Totals(
        calories: calories + m.calories,
        protein: protein + m.protein,
        carbs: carbs + m.carbs,
        fat: fat + m.fat,
      );
}

_Totals _sumTotals(List<Meal> meals) =>
    meals.fold(const _Totals(), (acc, m) => acc.add(m));

Map<int, List<Meal>> _groupByHour(List<Meal> meals) {
  final map = <int, List<Meal>>{};
  for (final m in meals) {
    final h = m.loggedAt.hour;
    map.putIfAbsent(h, () => []).add(m);
  }
  final keys = map.keys.toList()..sort();
  return {for (final k in keys) k: map[k]!};
}

/* ---------------------------------- UI ----------------------------------- */

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.totals});
  final _Totals totals;

  @override
  Widget build(BuildContext context) {
    Widget card(String label, String value, IconData icon) {
      return Card(
        margin: EdgeInsets.zero, 
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded( 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        card('Calories', '${totals.calories.toStringAsFixed(0)} kcal',
            Icons.local_fire_department),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: card('Protein', '${totals.protein.toStringAsFixed(1)} g',
                  Icons.fitness_center),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: card('Carbs', '${totals.carbs.toStringAsFixed(1)} g',
                  Icons.grain),
            ),
            const SizedBox(width: 8),
            Expanded(
              child:
                  card('Fat', '${totals.fat.toStringAsFixed(1)} g', Icons.egg),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.grouped,
    required this.onEditMeal,
  });

  final Map<int, List<Meal>> grouped;
  final void Function(Meal meal) onEditMeal;

  @override
  Widget build(BuildContext context) {
    if (grouped.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(child: Text('No meals logged yet.')),
      );
    }
    final entries = grouped.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...List.generate(entries.length, (i) {
          final hour = entries[i].key;
          final meals = entries[i].value;
          return _TimelineHourTile(
            hour: hour,
            meals: meals,
            isFirst: i == 0,
            isLast: i == entries.length - 1,
            onEditMeal: onEditMeal,
          );
        }),
      ],
    );
  }
}

class _TimelineHourTile extends StatelessWidget {
  const _TimelineHourTile({
    required this.hour,
    required this.meals,
    required this.isFirst,
    required this.isLast,
    required this.onEditMeal,
  });

  final int hour;
  final List<Meal> meals;
  final bool isFirst;
  final bool isLast;
  final void Function(Meal meal) onEditMeal;

  @override
  Widget build(BuildContext context) {
    final hh = hour.toString().padLeft(2, '0');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            SizedBox(
              height: isFirst ? 12 : 24,
              child:
                  isFirst ? const SizedBox.shrink() : const VerticalDivider(width: 2),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(
              height: isLast ? 12 : 24,
              child:
                  isLast ? const SizedBox.shrink() : const VerticalDivider(width: 2),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$hh:00', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...meals.map((m) => _MealCard(meal: m, onEdit: () => onEditMeal(m))),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.onEdit});

  final Meal meal;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    String timeOf(Meal m) =>
        '${m.loggedAt.hour.toString().padLeft(2, '0')}:${m.loggedAt.minute.toString().padLeft(2, '0')}';

    List<Widget> maybeItemsFromNotes() {
      if (meal.notes == null || meal.notes!.isEmpty) return const [];
      try {
        final parsed = json.decode(meal.notes!) as Map<String, dynamic>;
        final items = (parsed['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        if (items.isEmpty) return const [];
        return [
          const SizedBox(height: 6),
          ...items.map((it) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      (it['name'] as String?) ?? 'Item',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${(it['grams'] as num?)?.toStringAsFixed(0) ?? '0'} g'),
                ],
              )),
        ];
      } catch (_) {
        return const [];
      }
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(meal.name, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit meal',
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${meal.calories.toStringAsFixed(0)} kcal  ·  '
              'P ${meal.protein.toStringAsFixed(1)}g  ·  '
              'C ${meal.carbs.toStringAsFixed(1)}g  ·  '
              'F ${meal.fat.toStringAsFixed(1)}g  ·  '
              '${timeOf(meal)}',
            ),
            ...maybeItemsFromNotes(),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ Bottom sheet ------------------------------ */

class _LogMealSheet extends ConsumerStatefulWidget {
  const _LogMealSheet({required this.ref, this.existing});
  final WidgetRef ref;
  final Meal? existing;

  @override
  ConsumerState<_LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends ConsumerState<_LogMealSheet> {
  late final TextEditingController _mealNameCtrl;
  late DateTime _dateTime;

  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];

  final List<_FoodSelection> _selected = [];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _mealNameCtrl = TextEditingController(text: ex?.name ?? 'Meal');
    _dateTime = ex?.loggedAt ?? DateTime.now();
    if (ex != null) {
      _selected.addAll(_FoodSelection.fromNotes(ex.notes));
    }
  }

  @override
  void dispose() {
    _mealNameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _kcal => _selected.fold(0.0, (a, b) => a + b.calories);
  double get _p => _selected.fold(0.0, (a, b) => a + b.protein);
  double get _c => _selected.fold(0.0, (a, b) => a + b.carbs);
  double get _f => _selected.fold(0.0, (a, b) => a + b.fat);

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, controller) {
          final editing = widget.existing != null;

          return SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(editing ? 'Edit meal' : 'Log meal',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _mealNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Meal name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule),
                        label: Text(_formatFull(_dateTime)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Add foods', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Search foods',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _runSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _searching ? null : _runSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_searching) const LinearProgressIndicator(),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SearchResultsList(
                    results: _results,
                    onAdd: _addSearchItem,
                  ),
                ],
                const SizedBox(height: 16),
                if (_selected.isNotEmpty) ...[
                  Text('Selected foods', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _SelectedFoodsList(
                    items: _selected,
                    onRemove: (i) => setState(() => _selected.removeAt(i)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _chip('Calories', '${_kcal.toStringAsFixed(0)} kcal',
                          Icons.local_fire_department),
                      _chip('Protein', '${_p.toStringAsFixed(1)} g',
                          Icons.fitness_center),
                      _chip('Carbs', '${_c.toStringAsFixed(1)} g', Icons.grain),
                      _chip('Fat', '${_f.toStringAsFixed(1)} g', Icons.egg),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selected.isEmpty ? null : _saveMeal,
                        icon: const Icon(Icons.save),
                        label: Text(editing ? 'Save changes' : 'Save meal'),
                      ),
                    ),
                    if (editing) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: _deleteMeal,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, String val, IconData icon) {
    return Chip(avatar: Icon(icon, size: 18), label: Text('$label: $val'));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (t != null) {
      final now = DateTime.now();
      setState(() {
        _dateTime = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      });
    }
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _results = [];
    });

    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/cgi/search.pl'
        '?search_terms=${Uri.encodeQueryComponent(q)}'
        '&search_simple=1&action=process&json=1&page_size=20',
      );
      final res = await http.get(uri);
      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;
      final List prods = (data['products'] as List?) ?? const [];
      _results = prods.cast<Map<String, dynamic>>();
    } catch (_) {
      _results = [];
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addSearchItem(Map<String, dynamic> jsonRow) async {
    final grams = await _askForGrams();
    if (grams == null) return;

    try {
      final sel = _FoodSelection.fromOFF(jsonRow, grams);
      setState(() => _selected.add(sel));
    } catch (_) {}
  }

  Future<double?> _askForGrams() async {
    final ctrl = TextEditingController(text: '100');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Amount (grams)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. 100',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final g = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, g);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMeal() async {
    if (_selected.isEmpty) return;

    final name = _mealNameCtrl.text.trim().isEmpty
        ? 'Meal'
        : _mealNameCtrl.text.trim();

    final existing = widget.existing;
    final meal = Meal(
      id: existing?.id ?? _genId(),
      name: name,
      calories: _kcal,
      protein: _p,
      carbs: _c,
      fat: _f,
      loggedAt: _dateTime,
      notes: _encodeNotes(_selected),
    );
    try {
      await ref.read(mealControllerProvider.notifier).addOrUpdateMeal(meal);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save meal: $e')),
      );
    }

  }

  Future<void> _deleteMeal() async {
    final ex = widget.existing;
    if (ex == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete meal?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(mealControllerProvider.notifier).deleteMeal(ex.id);
      if (mounted) Navigator.pop(context);  
    }
  }

  String _formatFull(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final wd = weekdays[dt.weekday - 1];
    final mon = months[dt.month - 1];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${dt.day} $mon • $hh:$mm';
  }

  String _encodeNotes(List<_FoodSelection> items) {
    final list = items
        .map((e) => {
              'name': e.name,
              'grams': e.grams,
              'kcal100': e.kcal100,
              'p100': e.p100,
              'c100': e.c100,
              'f100': e.f100,
            })
        .toList();
    return json.encode({'items': list});
  }

  String _genId() {
    final rand = Random().nextInt(1 << 32);
    return 'meal_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.results,
    required this.onAdd,
  });

  final List<Map<String, dynamic>> results;
  final void Function(Map<String, dynamic> json) onAdd;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();

    String macro(Map<String, dynamic> nutr, List<String> keys) {
      for (final k in keys) {
        final v = nutr[k];
        if (v is num) return v.toStringAsFixed(1);
        if (v is String) {
          final d = double.tryParse(v);
          if (d != null) return d.toStringAsFixed(1);
        }
      }
      return '0.0';
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = results[i];
        final name = (r['product_name'] ??
                r['product_name_en'] ??
                r['brands'] ??
                'Unknown') as String? ??
            'Unknown';
        final nutr = (r['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
        final kcal = macro(nutr, const [
          'energy-kcal_100g',
          'energy-kcal_serving',
          'energy_100g',
        ]);
        final p = macro(nutr, const ['proteins_100g', 'proteins_serving']);
        final c = macro(nutr, const ['carbohydrates_100g', 'carbohydrates_serving']);
        final f = macro(nutr, const ['fat_100g', 'fat_serving']);

        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name),
          subtitle: Text('per 100g · kcal $kcal · P $p g · C $c g · F $f g'),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onAdd(r),
          ),
        );
      },
    );
  }
}

class _SelectedFoodsList extends StatelessWidget {
  const _SelectedFoodsList({
    required this.items,
    required this.onRemove,
  });

  final List<_FoodSelection> items;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final it = items[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(it.name),
          subtitle: Text(
            '${it.grams.toStringAsFixed(0)} g · '
            '${it.calories.toStringAsFixed(0)} kcal  '
            'P ${it.protein.toStringAsFixed(1)}g  '
            'C ${it.carbs.toStringAsFixed(1)}g  '
            'F ${it.fat.toStringAsFixed(1)}g',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onRemove(i),
          ),
        );
      },
    );
  }
}

/* ----------------------------- Local data type ---------------------------- */

class _FoodSelection {
  final String name;
  final double grams;
  final double kcal100;
  final double p100;
  final double c100;
  final double f100;

  _FoodSelection({
    required this.name,
    required this.grams,
    required this.kcal100,
    required this.p100,
    required this.c100,
    required this.f100,
  });

  double get calories => grams * kcal100 / 100.0;
  double get protein => grams * p100 / 100.0;
  double get carbs => grams * c100 / 100.0;
  double get fat => grams * f100 / 100.0;

  static _FoodSelection fromOFF(Map<String, dynamic> row, double grams) {
    final nutr = (row['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    double get(List<String> keys) {
      for (final k in keys) {
        final v = nutr[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final d = double.tryParse(v);
          if (d != null) return d;
        }
      }
      return 0.0;
    }

    final name = (row['product_name'] ??
            row['product_name_en'] ??
            row['brands'] ??
            'Unknown') as String? ??
        'Unknown';

    return _FoodSelection(
      name: name,
      grams: grams,
      kcal100: get(const [
        'energy-kcal_100g',
        'energy-kcal_serving',
      ]),
      p100: get(const ['proteins_100g', 'proteins_serving']),
      c100: get(const ['carbohydrates_100g', 'carbohydrates_serving']),
      f100: get(const ['fat_100g', 'fat_serving']),
    );
  }

  static List<_FoodSelection> fromNotes(String? notes) {
    if (notes == null || notes.isEmpty) return const [];
    try {
      final map = json.decode(notes) as Map<String, dynamic>;
      final items = (map['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      return items.map((it) {
        double asD(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
        return _FoodSelection(
          name: (it['name'] as String?) ?? 'Item',
          grams: asD(it['grams']),
          kcal100: asD(it['kcal100']),
          p100: asD(it['p100']),
          c100: asD(it['c100']),
          f100: asD(it['f100']),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
