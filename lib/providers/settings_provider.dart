// lib/providers/settings_provider.dart
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_settings.dart';
import '../services/firestore_sync.dart';

double kgFromLbs(double lbs) => lbs * 0.45359237;
double lbsFromKg(double kg) => kg / 0.45359237;

(double feet, double inches) feetInchesFromCm(double cm) {
  final totalIn = cm / 2.54;
  final ft = totalIn ~/ 12;
  final inch = totalIn - (ft * 12);
  return (ft.toDouble(), inch);
}

double cmFromFeetInches({required int feet, required double inches}) =>
    ((feet * 12) + inches) * 2.54;

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, UserSettings>(SettingsNotifier.new);

final macroTargetsProvider = Provider<MacroTargets>((ref) {
  final s = ref.watch(settingsProvider).value ?? UserSettings.initial();
  return SettingsNotifier.computeTargets(s);
});

class SettingsNotifier extends AsyncNotifier<UserSettings> {
  static const _prefsKey = 'user_settings_v1';

  @override
  Future<UserSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return UserSettings.initial();
    try {
      return UserSettings.fromJsonString(raw);
    } catch (_) {
      return UserSettings.initial();
    }
  }

  Future<void> save(UserSettings next) async => _saveAndPublish(next);

  Future<void> setName(String v)            => _update((s) => s.copyWith(name: v));
  Future<void> setGender(Gender g)          => _update((s) => s.copyWith(gender: g));
  Future<void> setAge(int age)              => _update((s) => s.copyWith(ageYears: age));
  Future<void> setActivity(ActivityLevel a) => _update((s) => s.copyWith(activity: a));
  Future<void> setExperience(ExperienceLevel e) => _update((s) => s.copyWith(experience: e));
  Future<void> setGoal(Goal g)              => _update((s) => s.copyWith(goal: g));
  Future<void> setDefaultGym(String v)      => _update((s) => s.copyWith(defaultGym: v));
  Future<void> setUnits(Units u)            => _update((s) => s.copyWith(units: u));
  Future<void> setHeightCm(double cm)       => _update((s) => s.copyWith(heightCm: cm));
  Future<void> setWeightKg(double kg)       => _update((s) => s.copyWith(weightKg: kg));

  Future<void> _update(UserSettings Function(UserSettings) change) async {
    final cur = state.value ?? await build();
    final next = change(cur);
    await _saveAndPublish(next);
  }

  Future<void> _saveAndPublish(UserSettings next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.toJsonString());

    state = AsyncValue.data(next);

    await ref.read(firestoreSyncProvider).pushSettingsNow();
  }

  static MacroTargets computeTargets(UserSettings s) {
    final bmr = s.gender == Gender.male
        ? 10 * s.weightKg + 6.25 * s.heightCm - 5 * s.ageYears + 5
        : 10 * s.weightKg + 6.25 * s.heightCm - 5 * s.ageYears - 161;
    final tdee = bmr * s.activity.multiplier;

    final adj = switch (s.goal) { Goal.lose => -500.0, Goal.gain => 300.0, Goal.maintain => 0.0 };
    final kcal = math.max(1000.0, tdee + adj);

    final proteinPerKg = switch (s.goal) { Goal.lose => 2.2, Goal.maintain => 1.8, Goal.gain => 1.6 };
    final proteinG = (s.weightKg * proteinPerKg).round();

    final fatPct = s.goal == Goal.lose ? 0.20 : 0.25;
    final fatG = ((kcal * fatPct) / 9.0).round();

    final kcalFromProtein = proteinG * 4;
    final kcalFromFat = fatG * 9;
    final carbsG = math.max(0, ((kcal - kcalFromProtein - kcalFromFat) / 4).round());

    return MacroTargets(calories: kcal.round(), proteinG: proteinG, fatG: fatG, carbsG: carbsG);
  }
}

extension _UserSettingsCopy on UserSettings {
  UserSettings copyWith({
    String? name,
    Gender? gender,
    int? ageYears,
    double? heightCm,
    double? weightKg,
    Goal? goal,
    Units? units,
    ActivityLevel? activity,
    String? defaultGym,
    ExperienceLevel? experience,
  }) {
    return UserSettings(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      ageYears: ageYears ?? this.ageYears,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      goal: goal ?? this.goal,
      units: units ?? this.units,
      activity: activity ?? this.activity,
      defaultGym: defaultGym ?? this.defaultGym,
      experience: experience ?? this.experience,
    );
  }
}
