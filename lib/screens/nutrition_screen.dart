import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 


import '/models/meal_model.dart';
import '/models/saved_meal.dart';
import '/providers/nutrition_provider.dart';
import '/services/nutrition_service.dart';

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
        label: const Text('Create meal'),
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

  Timer? _debounce;
  static const int _debounceMs = 350;  
  static const int _minChars   = 2;    
  String _lastIssuedQuery = '';
  String _inflightQuery = '';

  final _searchCtrl = TextEditingController();
  List<FSFoodSummary> _results = [];
  bool _busy = false;

  final List<_FoodSelection> _selected = [];

  @override
  void initState() {
    super.initState();
    _mealNameCtrl = TextEditingController(text: widget.existing?.name ?? 'Meal');
    _dateTime = widget.existing?.loggedAt ?? DateTime.now();

    if (widget.existing?.notes != null && widget.existing!.notes!.isNotEmpty) {
      _selected.addAll(_FoodSelection.fromNotes(widget.existing!.notes));
    }

    widget.ref.read(foodSearchQueryProvider.notifier).state = '';
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text;

      widget.ref.read(foodSearchQueryProvider.notifier).state = q;

      _debounce?.cancel();

      final trimmed = q.trim();
      if (trimmed.length >= _minChars) {
        _debounce = Timer(Duration(milliseconds: _debounceMs), () async {
          if (!mounted || trimmed == _lastIssuedQuery) return;
          _lastIssuedQuery = trimmed;
          await _doSearch(trimmed);
        });
      } else {
        if (mounted) setState(() => _results = []);
      }
    });

  }

  @override
  void dispose() {
    _mealNameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _kcal => _selected.fold(0.0, (a, b) => a + b.calories);
  double get _p    => _selected.fold(0.0, (a, b) => a + b.protein);
  double get _c    => _selected.fold(0.0, (a, b) => a + b.carbs);
  double get _f    => _selected.fold(0.0, (a, b) => a + b.fat);

  Future<void> _doSearch([String? q]) async {
    final query = (q ?? _searchCtrl.text).trim();
    if (query.isEmpty) return;

    setState(() { _busy = true; _results = []; });

    _inflightQuery = query;

    try {
      final items = await ref.read(nutritionServiceProvider).searchFoods(query, max: 20);

      if (!mounted || _inflightQuery != query) return;

      setState(() => _results = items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _addFromFatSecret(FSFoodSummary row) async {
    try {
      final details = await ref.read(nutritionServiceProvider).getFoodDetails(row.id);
      if (!mounted) return;
      final picked = await showDialog<_FoodSelection>(
        context: context,
        builder: (_) => _ServingPickerDialog(food: details),
      );
      if (picked == null) return;
      setState(() => _selected.add(picked));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load servings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(foodAutocompleteProvider).maybeWhen(
      data: (s) => s,
      orElse: () => const <String>[],
    );
    final editing = widget.existing != null;

    final savedMeals = ref.watch(savedMealsProvider).maybeWhen(
      data: (v) => v,
      orElse: () => const <SavedMeal>[],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'Edit Meal' : 'Create Meal',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            TextFormField(
              controller: _mealNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Meal name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () async {
                final dt = await _pickDateTime(context, _dateTime);
                if (dt != null) setState(() => _dateTime = dt);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(_fmtDateTime(_dateTime)),
                  ],
                ),
              ),
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
                      hintText: 'Search foods',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _doSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Scan barcode',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcodeAndAdd,
                ),
              ],
            ),

            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 4,
                children: suggestions.map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () { _searchCtrl.text = s; _doSearch(s); },
                )).toList(),
              ),
            ],

            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),

            if (savedMeals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Saved meals', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: savedMeals.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final sm = savedMeals[i];
                    return GestureDetector(
                      onLongPress: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete saved meal?'),
                            content: Text('Remove "${sm.name}" from saved meals?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await ref.read(savedMealControllerProvider.notifier).delete(sm.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted "${sm.name}"')),
                          );
                        }
                      },
                      child: ActionChip(
                        avatar: const Icon(Icons.bookmark_border, size: 18),
                        label: Text(sm.name, overflow: TextOverflow.ellipsis),
                        onPressed: () {
                          final items = _FoodSelection.fromNotes(sm.notes);
                          setState(() {
                            _mealNameCtrl.text = sm.name;
                            _selected.addAll(items);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Loaded "${sm.name}"')),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ], 

            const SizedBox(height: 12),

            _SearchResultsList(
              results: _results,
              onAdd: _addFromFatSecret,
            ),

            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SelectedFoodsList(
                items: _selected,
                onRemove: (i) => setState(() => _selected.removeAt(i)),
              ),
            ],

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _macro('kcal', _kcal),
                    _macro('P', _p),
                    _macro('C', _c),
                    _macro('F', _f),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                if (editing)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete meal'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
                      ),
                      onPressed: () async {
                        final theme = Theme.of(context);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete meal?'),
                            content: const Text(
                              'This will remove the meal and its items from today.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ); 

                        if (confirm == true) {
                          await widget.ref
                              .read(mealControllerProvider.notifier)
                              .deleteMeal(widget.existing!.id);
                          if (mounted) Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                if (editing) const SizedBox(width: 8),
                  Expanded(
                    child: editing
                        ? FilledButton.icon(
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save changes'),
                            onPressed: _selected.isEmpty
                                ? null
                                : () async {
                                    final meal = Meal(
                                      id: widget.existing!.id,
                                      name: (_mealNameCtrl.text.trim().isEmpty)
                                          ? (_selected.length == 1 ? _selected.first.name : 'Meal')
                                          : _mealNameCtrl.text.trim(),
                                      calories: _kcal,
                                      protein: _p,
                                      carbs: _c,
                                      fat: _f,
                                      loggedAt: _dateTime,
                                      notes: _encodeNotes(_selected),
                                    );
                                    await widget.ref.read(mealControllerProvider.notifier).addOrUpdateMeal(meal);
                                    if (mounted) Navigator.pop(context);
                                  },
                          )
                        : FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Log meal'),
                            onPressed: _selected.isEmpty
                                ? null
                                : () async {
                                    final meal = Meal(
                                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                                      name: (_mealNameCtrl.text.trim().isEmpty)
                                          ? (_selected.length == 1 ? _selected.first.name : 'Meal')
                                          : _mealNameCtrl.text.trim(),
                                      calories: _kcal,
                                      protein: _p,
                                      carbs: _c,
                                      fat: _f,
                                      loggedAt: _dateTime, 
                                      notes: _encodeNotes(_selected),
                                    );
                                    await widget.ref.read(mealControllerProvider.notifier).addOrUpdateMeal(meal);
                                    if (mounted) Navigator.pop(context);
                                  },
                          ),
                  ),

                  if (!editing) const SizedBox(width: 8),

                  if (!editing)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save for later'),
                        onPressed: _selected.isEmpty
                            ? null
                            : () async {
                                final name = (_mealNameCtrl.text.trim().isEmpty)
                                    ? (_selected.length == 1 ? _selected.first.name : 'Saved meal')
                                    : _mealNameCtrl.text.trim();

                                final template = SavedMeal(
                                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                                  name: name,
                                  calories: _kcal,
                                  protein: _p,
                                  carbs: _c,
                                  fat: _f,
                                  notes: _encodeNotes(_selected), 
                                );

                                await widget.ref.read(savedMealControllerProvider.notifier).save(template);

                                if (!mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Saved "$name" for later')),
                                );
                              },
                      ),
                    ),

              ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scanBarcodeAndAdd() async {
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BarcodeScannerSheet(),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) return;

    final loc = Localizations.maybeLocaleOf(context);
    final region = loc?.countryCode;    
    final language = loc?.languageCode;  

    setState(() => _busy = true);
    try {
      final details = await ref
          .read(nutritionServiceProvider)
          .getFoodDetailsByBarcode(raw, region: region, language: language);

      final picked = await showDialog<_FoodSelection>(
        context: context,
        builder: (_) => _ServingPickerDialog(food: details),
      );
      if (picked != null) setState(() => _selected.add(picked));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final help = msg.contains('Missing scope')
          ? ' Please ensure your OAuth2 token includes the "barcode" scope.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode not found. $msg$help')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  String _encodeNotes(List<_FoodSelection> items) {
    final list = items.map((e) => e.toJson()).toList();
    return json.encode({'items': list});
  }

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const wdays  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final wd = wdays[dt.weekday - 1];
    final mon = months[dt.month - 1];
    return '$wd, ${dt.day} $mon · ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
    final d = await showDatePicker( 
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    ); 
    if (d == null) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    ); 
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Widget _macro(String label, double v) {
    return Column(
      children: [
        Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        Text(label),
      ],
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.results, required this.onAdd});
  final List<FSFoodSummary> results;
  final void Function(FSFoodSummary row) onAdd;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: min(360, MediaQuery.of(context).size.height * 0.45),
      child: ListView.separated(
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = results[i];
          return ListTile(
            title: Text(f.name),
            subtitle: Text(f.type.isEmpty ? 'Food' : f.type),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => onAdd(f),
              tooltip: 'Add',
            ),
            onTap: () => onAdd(f),
          );
        },
      ),
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

  String _fmtNum(double n) =>
    n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  bool _descIs100g(String desc) =>
      RegExp(r'(^|\s)100\s*g\b', caseSensitive: false).hasMatch(desc);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final it = items[i];

        String formatQty(double servingsCount, String servingDesc) {
          final desc = servingDesc.trim();
          if (_descIs100g(desc)) {
            final grams = servingsCount * 100.0;   
            return '${_fmtNum(grams)} grams';
          }
          final unit = desc.replaceFirst(RegExp(r'^\s*1\s+'), '');
          return '${_fmtNum(servingsCount)} ${unit.isEmpty ? 'serving' : unit}';
        }

        final qty = formatQty(it.servingsCount!, it.servingDesc!);
        Text('$qty · ${it.calories.toStringAsFixed(0)} kcal, '
            'P ${_fmtNum(it.protein)}, '
            'C ${_fmtNum(it.carbs)}, '
            'F ${_fmtNum(it.fat)}');
        
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(it.name),
          subtitle: Text(
            '$qty · '
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

class _ServingPickerDialog extends StatefulWidget {
  const _ServingPickerDialog({required this.food});
  final FSFoodDetails food;

  @override
  State<_ServingPickerDialog> createState() => _ServingPickerDialogState();
}

class _ServingPickerDialogState extends State<_ServingPickerDialog> {
  FSServing? _serving;
  final TextEditingController _amountCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    if (widget.food.servings.isNotEmpty) {
      _serving = widget.food.servings.first;
    }
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount {
    final v = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (v == null || v.isNaN || v.isInfinite) return 0.0;
    return v;
  }

  bool _is100gServing(FSServing s) {
    final unit = (s.metricUnit ?? '').toLowerCase();
    final amt  = s.metricAmount ?? double.nan;
    final desc = s.description.toLowerCase();
    final isHundred = (amt - 100).abs() < 0.01 || desc.contains('100 g');
    return unit == 'g' && isHundred;
  }

  @override
  Widget build(BuildContext context) {
    final servings = widget.food.servings;

    return AlertDialog(
      title: Text(widget.food.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Serving size',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FSServing>(
                isExpanded: true,
                value: _serving,
                items: servings.map((s) {
                  final desc = s.description.isNotEmpty
                      ? s.description
                      : '${s.metricAmount ?? ''} ${s.metricUnit ?? ''}'.trim();
                  return DropdownMenuItem(value: s, child: Text(desc));
                }).toList(),
                onChanged: (s) => setState(() => _serving = s),
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (_serving != null) ...[
            Builder(builder: (_) {
              final s = _serving!;
              final gramsMode = _is100gServing(s);

              return TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: gramsMode ? 'Weight' : 'Amount',
                  border: const OutlineInputBorder(),
                  suffixText: gramsMode ? 'g' : '× serving',
                  helperText: gramsMode
                      ? 'Enter grams directly (macros scale from per-100g)'
                      : 'Enter number of the selected serving',
                ),
                onChanged: (_) => setState(() {}),
              );
            }),
          ],
          const SizedBox(height: 8),

          if (_serving != null)
            Builder(builder: (_) {
              final s = _serving!;
              final gramsMode = _is100gServing(s);
              final factor = gramsMode ? (_amount / 100.0) : _amount;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _macro('kcal', s.calories * factor),
                  _macro('P',    s.protein  * factor),
                  _macro('C',    s.carbs    * factor),
                  _macro('F',    s.fat      * factor),
                ],
              );
            }
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_serving == null || _amount <= 0)
              ? null
              : () {
                  final s = _serving!;
                  final gramsMode = _is100gServing(s);

                  final desc = s.description.isNotEmpty
                      ? s.description
                      : '${s.metricAmount ?? ''} ${s.metricUnit ?? ''}'.trim();

                  final sel = gramsMode
                      ? _FoodSelection.fromServing(
                          name: widget.food.name,
                          servingDesc: '100 g',           
                          perServingKcal: s.calories,     
                          perServingP: s.protein,         
                          perServingC: s.carbs,           
                          perServingF: s.fat,             
                          servingsCount: _amount / 100.0, 
                        )
                      : _FoodSelection.fromServing(
                          name: widget.food.name,
                          servingDesc: desc,
                          perServingKcal: s.calories,
                          perServingP: s.protein,
                          perServingC: s.carbs,
                          perServingF: s.fat,
                          servingsCount: _amount,
                        );

                  Navigator.pop(context, sel); },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _macro(String label, double v) {
    return Column(
      children: [
        Text(v.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(label),
      ],
    );
  }
}

/* ----------------------------- Local data type ---------------------------- */


class _FoodSelection {
  final String name;

  final double? grams;
  final double? kcal100;
  final double? p100;
  final double? c100;
  final double? f100;

  final double? perServingKcal;
  final double? perServingP;
  final double? perServingC;
  final double? perServingF;
  final double? servingsCount;
  final String? servingDesc;

  bool get isServing => perServingKcal != null;

  _FoodSelection._({
    required this.name,
    this.grams,
    this.kcal100,
    this.p100,
    this.c100,
    this.f100,
    this.perServingKcal,
    this.perServingP,
    this.perServingC,
    this.perServingF,
    this.servingsCount,
    this.servingDesc,
  });

  factory _FoodSelection.fromServing({
    required String name,
    required String servingDesc,
    required double perServingKcal,
    required double perServingP,
    required double perServingC,
    required double perServingF,
    required double servingsCount,
  }) {
    return _FoodSelection._(
      name: name,
      perServingKcal: perServingKcal,
      perServingP: perServingP,
      perServingC: perServingC,
      perServingF: perServingF,
      servingsCount: servingsCount,
      servingDesc: servingDesc,
    );
  }

  double get calories {
    if (isServing) return (perServingKcal ?? 0) * (servingsCount ?? 1);
    return (grams ?? 0) * (kcal100 ?? 0) / 100.0;
    }
  double get protein {
    if (isServing) return (perServingP ?? 0) * (servingsCount ?? 1);
    return (grams ?? 0) * (p100 ?? 0) / 100.0;
  }
  double get carbs {
    if (isServing) return (perServingC ?? 0) * (servingsCount ?? 1);
    return (grams ?? 0) * (c100 ?? 0) / 100.0;
  }
  double get fat {
    if (isServing) return (perServingF ?? 0) * (servingsCount ?? 1);
    return (grams ?? 0) * (f100 ?? 0) / 100.0;
  }

  Map<String, dynamic> toJson() {
    if (isServing) {
      return {
        'name': name,
        'mode': 'serving',
        'servingDesc': servingDesc,
        'perServingKcal': perServingKcal,
        'perServingP': perServingP,
        'perServingC': perServingC,
        'perServingF': perServingF,
        'servingsCount': servingsCount,
      };
    } else {
      return {
        'name': name,
        'mode': 'grams',
        'grams': grams,
        'kcal100': kcal100,
        'p100': p100,
        'c100': c100,
        'f100': f100,
      };
    }
  }

  static List<_FoodSelection> fromNotes(String? notes) {
    if (notes == null || notes.isEmpty) return const [];
    try {
      final map = json.decode(notes) as Map<String, dynamic>;
      final items = (map['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      return items.map((it) {
        double asD(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
        final mode = (it['mode'] as String?) ?? 'grams';
        if (mode == 'serving') {
          return _FoodSelection.fromServing(
            name: (it['name'] as String?) ?? 'Item',
            servingDesc: (it['servingDesc'] as String?) ?? 'serving',
            perServingKcal: asD(it['perServingKcal']),
            perServingP: asD(it['perServingP']),
            perServingC: asD(it['perServingC']),
            perServingF: asD(it['perServingF']),
            servingsCount: asD(it['servingsCount']),
          );
        }
        return _FoodSelection._(
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

class _BarcodeScannerSheet extends StatefulWidget {
const _BarcodeScannerSheet();
@override
State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
late final MobileScannerController _controller;
bool _returned = false;

@override
void initState() {
  super.initState();
  _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcA],
    autoStart: true,
  );
}

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

void _returnIfValid(String? raw) {
  if (_returned || raw == null) return;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) {
    _returned = true;
    Navigator.of(context).pop(digits);
  }
}

@override
Widget build(BuildContext context) {
  final h = MediaQuery.of(context).size.height;
  return SizedBox(
    height: h * 0.80,
    child: Stack(
      children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                _returnIfValid(b.rawValue);
              }
            },
          ),
        ),
        Positioned(
          left: 0, right: 0, top: 0,
          child: AppBar(
            title: const Text('Scan barcode'),
            backgroundColor: Colors.black54,
            actions: [
              IconButton(
                icon: const Icon(Icons.flash_on),
                onPressed: () => _controller.toggleTorch(),
              ),
              IconButton(
                icon: const Icon(Icons.cameraswitch),
                onPressed: () => _controller.switchCamera(),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Center(
          child: Container(
            width: 280, height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
}
}
