import 'dart:convert';

enum Gender { male, female }
enum Goal { lose, maintain, gain }
enum Units { metric, imperial }

enum ActivityLevel {
  sedentary(1.2),
  light(1.375),
  moderate(1.55),
  active(1.725),
  veryActive(1.9);

  final double multiplier;
  const ActivityLevel(this.multiplier);
}

class UserSettings {
  final String name;
  final Gender gender;
  final int ageYears;
  final double heightCm;
  final double weightKg;
  final Goal goal;
  final Units units;
  final ActivityLevel activity;
  final String defaultGym; 

  const UserSettings({
    required this.name,
    required this.gender,
    required this.ageYears,
    required this.heightCm,
    required this.weightKg,
    required this.goal,
    required this.units,
    required this.activity,
    this.defaultGym = '',
  });

  factory UserSettings.initial() => const UserSettings(
        name: '',
        gender: Gender.male,
        ageYears: 30,
        heightCm: 175,
        weightKg: 75,
        goal: Goal.maintain,
        units: Units.metric,
        activity: ActivityLevel.moderate,
        defaultGym: '', 
      );

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
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'gender': gender.name,
        'ageYears': ageYears,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'goal': goal.name,
        'units': units.name,
        'activity': activity.name,
        'defaultGym': defaultGym, 
      };

  factory UserSettings.fromJson(Map<String, dynamic> map) {
    Gender g(String s) => Gender.values.firstWhere((e) => e.name == s, orElse: () => Gender.male);
    Goal goal(String s) => Goal.values.firstWhere((e) => e.name == s, orElse: () => Goal.maintain);
    Units u(String s) => Units.values.firstWhere((e) => e.name == s, orElse: () => Units.metric);
    ActivityLevel a(String s) =>
        ActivityLevel.values.firstWhere((e) => e.name == s, orElse: () => ActivityLevel.moderate);
    return UserSettings(
      name: (map['name'] ?? '') as String,
      gender: g(map['gender'] as String? ?? 'male'),
      ageYears: (map['ageYears'] ?? 30) as int,
      heightCm: (map['heightCm'] ?? 175).toDouble(),
      weightKg: (map['weightKg'] ?? 75).toDouble(),
      goal: goal(map['goal'] as String? ?? 'maintain'),
      units: u(map['units'] as String? ?? 'metric'),
      activity: a(map['activity'] as String? ?? 'moderate'),
      defaultGym: (map['defaultGym'] ?? '') as String, 
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory UserSettings.fromJsonString(String s) => UserSettings.fromJson(jsonDecode(s));
}

class MacroTargets {
  final int calories;
  final int proteinG;
  final int fatG;
  final int carbsG;
  const MacroTargets({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });
}
