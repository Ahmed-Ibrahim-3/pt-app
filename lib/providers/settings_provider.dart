import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_settings.dart';

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, UserSettings>(SettingsNotifier.new);

final macroTargetsProvider = Provider<MacroTargets>((ref) {
  final settingsAsync = ref.watch(settingsProvider);
  final s = settingsAsync.value ?? UserSettings.initial();
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

  Future<void> _save(UserSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, s.toJsonString());
    state = AsyncData(s);
  }

  void setName(String name) => _save((state.value ?? UserSettings.initial()).copyWith(name: name));
  void setGender(Gender g) => _save((state.value ?? UserSettings.initial()).copyWith(gender: g));
  void setAge(int age) => _save((state.value ?? UserSettings.initial()).copyWith(ageYears: age));

  void setHeightCm(double cm) => _save((state.value ?? UserSettings.initial()).copyWith(heightCm: cm));
  void setWeightKg(double kg) => _save((state.value ?? UserSettings.initial()).copyWith(weightKg: kg));

  void setGoal(Goal goal) => _save((state.value ?? UserSettings.initial()).copyWith(goal: goal));
  void setUnits(Units u) => _save((state.value ?? UserSettings.initial()).copyWith(units: u));
  void setActivity(ActivityLevel a) =>
      _save((state.value ?? UserSettings.initial()).copyWith(activity: a));

  Future<void> setDefaultGym(String v) async {
    final cur = state.value ?? UserSettings.initial();
    final next = cur.copyWith(defaultGym: v);
    await _save(next); 
    state = AsyncData(next);
  }


  static double _rmr(UserSettings s) {
    final w = s.weightKg;
    final h = s.heightCm;
    final a = s.ageYears;

    final base = (10 * w) + (6.25 * h) - (5 * a);
    return s.gender == Gender.male ? base + 5 : base - 161;
  }

  static double _tdee(UserSettings s) => _rmr(s) * s.activity.multiplier;

  static MacroTargets computeTargets(UserSettings s) {
    final tdee = _tdee(s);
    final adj = switch (s.goal) { Goal.lose => -500.0, Goal.gain => 300.0, Goal.maintain => 0.0 };
    final kcal = math.max(1000.0, tdee + adj); 

    final proteinPerKg = switch (s.goal) {
      Goal.lose => 2.2,
      Goal.maintain => 1.8,
      Goal.gain => 1.6,
    };
    final proteinG = (s.weightKg * proteinPerKg).round();

    final fatPct = s.goal == Goal.lose ? 0.20 : 0.25;
    final fatG = ((kcal * fatPct) / 9.0).round();

    final kcalFromProtein = proteinG * 4;
    final kcalFromFat = fatG * 9;
    final carbsG = math.max(0, ((kcal - kcalFromProtein - kcalFromFat) / 4.0).round());

    return MacroTargets(
      calories: kcal.round(),
      proteinG: proteinG,
      fatG: fatG,
      carbsG: carbsG,
    );
  }
}

double cmFromFeetInches({required int feet, required double inches}) {
  final totalInches = (feet * 12) + inches;
  return totalInches * 2.54;
}

(double feet, double inches) feetInchesFromCm(double cm) {
  final totalInches = cm / 2.54;
  final ft = totalInches ~/ 12;
  final inch = totalInches - (ft * 12);
  return (ft.toDouble(), inch);
}

double kgFromLbs(double lbs) => lbs * 0.45359237;
double lbsFromKg(double kg) => kg / 0.45359237;
