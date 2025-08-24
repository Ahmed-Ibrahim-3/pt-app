import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _defaultGymCtrl = TextEditingController();

  final _heightCmCtrl = TextEditingController();
  final _weightKgCtrl = TextEditingController();

  final _heightFtCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();
  final _weightLbCtrl = TextEditingController();

  bool _seeding = false;
  bool _seededOnce = false; 

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCmCtrl.dispose();
    _weightKgCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _weightLbCtrl.dispose();
    _defaultGymCtrl.dispose();
    super.dispose();
  }

  void _seedControllersFrom(UserSettings s) {
    _seeding = true;
    _nameCtrl.text = s.name;
    _ageCtrl.text = s.ageYears.toString();
    _defaultGymCtrl.text = s.defaultGym;

    if (s.units == Units.metric) {
      _heightCmCtrl.text = s.heightCm.toStringAsFixed(0);
      _weightKgCtrl.text = s.weightKg.toStringAsFixed(1);
      _heightFtCtrl.clear();
      _heightInCtrl.clear();
      _weightLbCtrl.clear();
    } else {
      final (ft, inch) = feetInchesFromCm(s.heightCm);
      _heightFtCtrl.text = ft.toStringAsFixed(0);
      _heightInCtrl.text = inch.toStringAsFixed(1);
      _weightLbCtrl.text = lbsFromKg(s.weightKg).toStringAsFixed(1);
      _heightCmCtrl.clear();
      _weightKgCtrl.clear();
    }
    _seeding = false;
  }

  @override
  Widget build(BuildContext context) {
    final sAsync = ref.watch(settingsProvider);
    final targets = ref.watch(macroTargetsProvider);

    sAsync.whenData((s) {
      if (!_seededOnce) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _seedControllersFrom(s));
        _seededOnce = true;
      }
    });

    ref.listen<AsyncValue<UserSettings>>(settingsProvider, (prev, next) {
      final prevUnits = prev?.valueOrNull?.units;
      final nextUnits = next.valueOrNull?.units;
      if (prevUnits != nextUnits && nextUnits != null) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final s = next.value!;
          _seedControllersFrom(s);
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: sAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: 'Profile',
                child: Column(
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (v) => ref.read(settingsProvider.notifier).setName(v.trim()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Dropdown<Gender>(
                            label: 'Gender',
                            value: s.gender,
                            items: const {
                              Gender.male: 'Male',
                              Gender.female: 'Female',
                            },
                            onChanged: (g) => ref.read(settingsProvider.notifier).setGender(g),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _ageCtrl,
                            decoration: const InputDecoration(labelText: 'Age', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 16)),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (v) {
                              final age = int.tryParse(v);
                              if (_seeding) return;
                              if (age != null && age > 0 && age < 120) {
                                ref.read(settingsProvider.notifier).setAge(age);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Dropdown<ActivityLevel>(
                            label: 'Activity',
                            value: s.activity,
                            items: const {
                              ActivityLevel.sedentary: 'Sedentary',
                              ActivityLevel.light: 'Light',
                              ActivityLevel.moderate: 'Moderate',
                              ActivityLevel.active: 'Active',
                              ActivityLevel.veryActive: 'Very Active',
                            },
                            onChanged: (a) => ref.read(settingsProvider.notifier).setActivity(a),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Dropdown<Goal>(
                            label: 'Goal',
                            value: s.goal,
                            items: const {
                              Goal.lose: 'Lose weight',
                              Goal.maintain: 'Maintain',
                              Goal.gain: 'Gain weight',
                            },
                            onChanged: (g) => ref.read(settingsProvider.notifier).setGoal(g),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _defaultGymCtrl,
                      decoration: const InputDecoration(labelText: 'Default gym (optional)'),
                      textInputAction: TextInputAction.done,
                      onChanged: (v) {
                        if (_seeding) return;
                        ref.read(settingsProvider.notifier).setDefaultGym(v.trim());
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _Section(
                title: 'Units',
                child: _Dropdown<Units>(
                  label: 'Measurement system',
                  value: s.units,
                  items: const {Units.metric: 'Metric', Units.imperial: 'Imperial'},
                  onChanged: (u) => ref.read(settingsProvider.notifier).setUnits(u),
                ),
              ),

              const SizedBox(height: 16),
              _Section(
                title: 'Body Metrics',
                child: s.units == Units.metric
                    ? Column(
                        children: [
                          TextField(
                            controller: _heightCmCtrl,
                            decoration: const InputDecoration(labelText: 'Height (cm)'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            onChanged: (v) {
                              if (_seeding) return;
                              if (v.isEmpty) return;
                              final cm = double.tryParse(v);
                              if (cm != null && cm > 0) {
                                ref.read(settingsProvider.notifier).setHeightCm(cm);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _weightKgCtrl,
                            decoration: const InputDecoration(labelText: 'Weight (kg)'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            onChanged: (v) {
                              if (_seeding) return;
                              if (v.isEmpty) return;
                              final kg = double.tryParse(v);
                              if (kg != null && kg > 0) {
                                ref.read(settingsProvider.notifier).setWeightKg(kg);
                              }
                            },
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _heightFtCtrl,
                                  decoration: const InputDecoration(labelText: 'Height (ft)'),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  onChanged: (_) => _pushImperialHeight(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _heightInCtrl,
                                  decoration: const InputDecoration(labelText: 'Height (in)'),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  onChanged: (_) => _pushImperialHeight(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _weightLbCtrl,
                            decoration: const InputDecoration(labelText: 'Weight (lb)'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            onChanged: (v) {
                              if (_seeding) return;
                              if (v.isEmpty) return;
                              final lb = double.tryParse(v);
                              if (lb != null && lb > 0) {
                                ref.read(settingsProvider.notifier).setWeightKg(kgFromLbs(lb));
                              }
                            },
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 16),
              _Section(
                title: 'Account',
                child: const Text('Linked email, subscription, sign-out, etc. – coming soon.'),
              ),

              const SizedBox(height: 24),
              _Section(
                title: 'Your Targets (preview)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TargetRow(label: 'Calories', value: '${targets.calories} kcal/day'),
                    const SizedBox(height: 8),
                    _TargetRow(label: 'Protein', value: '${targets.proteinG} g/day'),
                    const SizedBox(height: 8),
                    _TargetRow(label: 'Fat', value: '${targets.fatG} g/day'),
                    const SizedBox(height: 8),
                    _TargetRow(label: 'Carbs', value: '${targets.carbsG} g/day'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _pushImperialHeight() {
    if (_seeding) return;
    final ft = int.tryParse(_heightFtCtrl.text) ?? 0;
    final inch = double.tryParse(_heightInCtrl.text) ?? 0.0;
    if (ft >= 0 && inch >= 0) {
      final cm = cmFromFeetInches(feet: ft, inches: inch);
      ref.read(settingsProvider.notifier).setHeightCm(cm);
    }
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final void Function(T value) onChanged;
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: items.entries
              .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final String value;
  const _TargetRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
