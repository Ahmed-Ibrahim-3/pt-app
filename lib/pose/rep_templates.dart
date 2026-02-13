import 'dart:math' as math;

import 'pose_comparison.dart';

class JointTarget {
  final double start;
  final double opposite;
  final double toleranceDeg;
  final double weight;

  const JointTarget({
    required this.start,
    required this.opposite,
    required this.toleranceDeg,
    required this.weight,
  });
}

class PoseRepTemplate {
  final String exerciseId;
  final Map<JointAngleKind, JointTarget> joints;
  final double symmetryToleranceDeg;
  final double symmetryWeight;

  const PoseRepTemplate({
    required this.exerciseId,
    required this.joints,
    this.symmetryToleranceDeg = 12,
    this.symmetryWeight = 0.20,
  });
}

class ExerciseDefinition {
  final String id;
  final JointAngleKind primaryJoint;
  final bool startAtHigh;

  final double highEnter;
  final double highExit;
  final double lowEnter;
  final double lowExit;

  final int minRepMs;

  final PoseRepTemplate template;

  const ExerciseDefinition({
    required this.id,
    required this.primaryJoint,
    required this.startAtHigh,
    required this.highEnter,
    required this.highExit,
    required this.lowEnter,
    required this.lowExit,
    required this.minRepMs,
    required this.template,
  });
}

class BuiltInExerciseCatalog {
  static List<ExerciseDefinition> all() => [
        _squat(),
        _benchPress(),
        _curl(),
        _shoulderPress(),
        _deadlift(),
      ];

  static ExerciseDefinition byId(String id) {
    final normalized = switch (id) {
      'pushup' => 'bench_press',
      'hip_hinge' => 'deadlift',
      _ => id,
    };
    return all().firstWhere((e) => e.id == normalized);
  }

  static String displayName(String id) => switch (id) {
        'squat' => 'Squat',
        'bench_press' => 'Bench Press',
        'curl' => 'Bicep Curl',
        'shoulder_press' => 'Shoulder Press',
        'deadlift' => 'Deadlift',
        _ => id,
      };

  static ExerciseDefinition _squat() {
    return ExerciseDefinition(
      id: 'squat',
      primaryJoint: JointAngleKind.leftKnee,
      startAtHigh: true,
      highEnter: 160,
      highExit: 150,
      lowEnter: 105,
      lowExit: 115,
      minRepMs: 600,
      template: PoseRepTemplate(
        exerciseId: 'squat',
        symmetryToleranceDeg: 14,
        symmetryWeight: 0.20,
        joints: {
          JointAngleKind.leftKnee: const JointTarget(
            start: 175,
            opposite: 90,
            toleranceDeg: 14,
            weight: 1.0,
          ),
          JointAngleKind.rightKnee: const JointTarget(
            start: 175,
            opposite: 90,
            toleranceDeg: 14,
            weight: 1.0,
          ),
          JointAngleKind.leftHip: const JointTarget(
            start: 175,
            opposite: 80,
            toleranceDeg: 16,
            weight: 0.9,
          ),
          JointAngleKind.rightHip: const JointTarget(
            start: 175,
            opposite: 80,
            toleranceDeg: 16,
            weight: 0.9,
          ),
          JointAngleKind.trunkLean: const JointTarget(
            start: 10,
            opposite: 40,
            toleranceDeg: 12,
            weight: 0.7,
          ),
        },
      ),
    );
  }

  static ExerciseDefinition _benchPress() {
    return ExerciseDefinition(
      id: 'bench_press',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 105,
      lowExit: 115,
      minRepMs: 500,
      template: PoseRepTemplate(
        exerciseId: 'bench_press',
        symmetryToleranceDeg: 14,
        symmetryWeight: 0.18,
        joints: {
          JointAngleKind.leftElbow: const JointTarget(
            start: 175,
            opposite: 90,
            toleranceDeg: 16,
            weight: 1.0,
          ),
          JointAngleKind.rightElbow: const JointTarget(
            start: 175,
            opposite: 90,
            toleranceDeg: 16,
            weight: 1.0,
          ),
        },
      ),
    );
  }

  static ExerciseDefinition _curl() {
    return ExerciseDefinition(
      id: 'curl',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 75,
      lowExit: 85,
      minRepMs: 450,
      template: PoseRepTemplate(
        exerciseId: 'curl',
        symmetryToleranceDeg: 16,
        symmetryWeight: 0.15,
        joints: {
          JointAngleKind.leftElbow: const JointTarget(
            start: 175,
            opposite: 55,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.rightElbow: const JointTarget(
            start: 175,
            opposite: 55,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.leftShoulder: const JointTarget(
            start: 25,
            opposite: 40,
            toleranceDeg: 20,
            weight: 0.45,
          ),
          JointAngleKind.rightShoulder: const JointTarget(
            start: 25,
            opposite: 40,
            toleranceDeg: 20,
            weight: 0.45,
          ),
        },
      ),
    );
  }

  static ExerciseDefinition _shoulderPress() {
    return ExerciseDefinition(
      id: 'shoulder_press',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: false,
      highEnter: 155,
      highExit: 145,
      lowEnter: 110,
      lowExit: 120,
      minRepMs: 600,
      template: PoseRepTemplate(
        exerciseId: 'shoulder_press',
        symmetryToleranceDeg: 16,
        symmetryWeight: 0.18,
        joints: {
          JointAngleKind.leftElbow: const JointTarget(
            start: 95,
            opposite: 170,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.rightElbow: const JointTarget(
            start: 95,
            opposite: 170,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.leftShoulder: const JointTarget(
            start: 70,
            opposite: 130,
            toleranceDeg: 20,
            weight: 0.8,
          ),
          JointAngleKind.rightShoulder: const JointTarget(
            start: 70,
            opposite: 130,
            toleranceDeg: 20,
            weight: 0.8,
          ),
          JointAngleKind.trunkLean: const JointTarget(
            start: 5,
            opposite: 15,
            toleranceDeg: 12,
            weight: 0.6,
          ),
        },
      ),
    );
  }

  static ExerciseDefinition _deadlift() {
    return ExerciseDefinition(
      id: 'deadlift',
      primaryJoint: JointAngleKind.leftHip,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 110,
      lowExit: 120,
      minRepMs: 650,
      template: PoseRepTemplate(
        exerciseId: 'deadlift',
        symmetryToleranceDeg: 16,
        symmetryWeight: 0.18,
        joints: {
          JointAngleKind.leftHip: const JointTarget(
            start: 175,
            opposite: 85,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.rightHip: const JointTarget(
            start: 175,
            opposite: 85,
            toleranceDeg: 18,
            weight: 1.0,
          ),
          JointAngleKind.leftKnee: const JointTarget(
            start: 170,
            opposite: 150,
            toleranceDeg: 16,
            weight: 0.6,
          ),
          JointAngleKind.rightKnee: const JointTarget(
            start: 170,
            opposite: 150,
            toleranceDeg: 16,
            weight: 0.6,
          ),
          JointAngleKind.trunkLean: const JointTarget(
            start: 10,
            opposite: 60,
            toleranceDeg: 16,
            weight: 0.8,
          ),
        },
      ),
    );
  }
}
