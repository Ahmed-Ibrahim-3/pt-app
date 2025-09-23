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

enum ExperienceLevel { beginner, novice, intermediate, advanced, expert }


class UserSettings {
  final String name;
  final Gender gender;
  final int ageYears;
  final double heightCm;
  final double weightKg;
  final Goal goal;
  final Units units;
  final ActivityLevel activity;
  final ExperienceLevel experience;
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
    required this.experience,
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
        experience: ExperienceLevel.beginner,
        defaultGym: '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'gender': gender.name,
        'ageYears': ageYears,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'goal': goal.name,
        'units': units.name,
        'activity': activity.name,
        'experience': experience.name,
        'defaultGym': defaultGym,
        'updatedAt': DateTime.now(),
      };

  factory UserSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return UserSettings.initial();
    T _enum<T>(String v, List<T> values) =>
        values.firstWhere((e) => (e as dynamic).name == v, orElse: () => values.first);
    return UserSettings(
      name: (m['name'] ?? '') as String,
      gender: _enum(m['gender'] ?? 'male', Gender.values),
      ageYears: (m['ageYears'] ?? 30) as int,
      heightCm: (m['heightCm'] ?? 175).toDouble(),
      weightKg: (m['weightKg'] ?? 75).toDouble(),
      goal: _enum(m['goal'] ?? 'maintain', Goal.values),
      units: _enum(m['units'] ?? 'metric', Units.values),
      activity: _enum(m['activity'] ?? 'moderate', ActivityLevel.values),
      experience: _enum(m['experience'] ?? 'beginner', ExperienceLevel.values),
      defaultGym: (m['defaultGym'] ?? '') as String,
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
        'experience': experience.name,  
        'defaultGym': defaultGym, 
      };

  factory UserSettings.fromJson(Map<String, dynamic> map) {
    Gender g(String s) => Gender.values.firstWhere((e) => e.name == s, orElse: () => Gender.male);
    Goal goal(String s) => Goal.values.firstWhere((e) => e.name == s, orElse: () => Goal.maintain);
    Units u(String s) => Units.values.firstWhere((e) => e.name == s, orElse: () => Units.metric);
    ActivityLevel a(String s) =>
        ActivityLevel.values.firstWhere((e) => e.name == s, orElse: () => ActivityLevel.moderate);
    ExperienceLevel e(String s, List<ExperienceLevel> values) =>
        values.firstWhere((el) => el.name == s, orElse: () => ExperienceLevel.beginner);
    return UserSettings(
      name: (map['name'] ?? '') as String,
      gender: g(map['gender'] as String? ?? 'male'),
      ageYears: (map['ageYears'] ?? 30) as int,
      heightCm: (map['heightCm'] ?? 175).toDouble(),
      weightKg: (map['weightKg'] ?? 75).toDouble(),
      goal: goal(map['goal'] as String? ?? 'maintain'),
      units: u(map['units'] as String? ?? 'metric'),
      activity: a(map['activity'] as String? ?? 'moderate'),
      experience: e(map['experience'] ?? 'beginner', ExperienceLevel.values),
      defaultGym: (map['defaultGym'] ?? '') as String, 
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory UserSettings.fromJsonString(String s) => UserSettings.fromJson(jsonDecode(s));

  UserSettings copyWith({
    String? name,
    Gender? gender,
    int? ageYears,
    double? heightCm,
    double? weightKg,
    Goal? goal,
    Units? units,
    ActivityLevel? activity,
    ExperienceLevel? experience,
    String? defaultGym,
  }) =>
      UserSettings(
        name: name ?? this.name,
        gender: gender ?? this.gender,
        ageYears: ageYears ?? this.ageYears,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        goal: goal ?? this.goal,
        units: units ?? this.units,
        activity: activity ?? this.activity,
        experience: experience ?? this.experience,
        defaultGym: defaultGym ?? this.defaultGym,
      );
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

