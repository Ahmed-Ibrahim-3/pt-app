import 'dart:convert';
import 'dart:math' as math;

import 'pose_comparison.dart';

class PoseRepTemplate {
  final String exerciseId;
  final int sampleCount;

  final Map<JointAngleKind, List<double>> jointCurves;

  final Map<JointAngleKind, double> toleranceDeg;

  final Map<JointAngleKind, double> weights;

  const PoseRepTemplate({
    required this.exerciseId,
    required this.sampleCount,
    required this.jointCurves,
    required this.toleranceDeg,
    required this.weights,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sampleCount': sampleCount,
        'jointCurves': jointCurves.map((k, v) => MapEntry(k.name, v)),
        'toleranceDeg': toleranceDeg.map((k, v) => MapEntry(k.name, v)),
        'weights': weights.map((k, v) => MapEntry(k.name, v)),
      };

  static PoseRepTemplate fromJson(Map<String, dynamic> j) {
    JointAngleKind kFrom(String s) =>
        JointAngleKind.values.firstWhere((e) => e.name == s);

    Map<JointAngleKind, List<double>> curvesFrom(dynamic raw) {
      final m = (raw as Map).cast<String, dynamic>();
      return m.map((k, v) => MapEntry(kFrom(k), (v as List).cast<num>().map((e) => e.toDouble()).toList()));
    }

    Map<JointAngleKind, double> mapDouble(dynamic raw) {
      final m = (raw as Map).cast<String, dynamic>();
      return m.map((k, v) => MapEntry(kFrom(k), (v as num).toDouble()));
    }

    return PoseRepTemplate(
      exerciseId: j['exerciseId'] as String,
      sampleCount: (j['sampleCount'] as num).toInt(),
      jointCurves: curvesFrom(j['jointCurves']),
      toleranceDeg: mapDouble(j['toleranceDeg']),
      weights: mapDouble(j['weights']),
    );
  }

  String toJsonString({bool pretty = false}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());
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
  final int sampleCount;

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
    required this.sampleCount,
    required this.template,
  });
}

class BuiltInExerciseCatalog {
  static const int _n = 61;

  static List<ExerciseDefinition> all() => [
        _squat(),
        _pushup(),
        _curl(),
        _shoulderPress(),
        _hipHinge(),
      ];

  static ExerciseDefinition byId(String id) =>
      all().firstWhere((e) => e.id == id);

  static ExerciseDefinition _squat() {
    final tpl = _cosTemplate(
      exerciseId: 'squat',
      startHigh: true,
      jointTargets: {
        JointAngleKind.leftKnee: (175, 90),
        JointAngleKind.rightKnee: (175, 90),
        JointAngleKind.leftHip: (175, 80),
        JointAngleKind.rightHip: (175, 80),
        JointAngleKind.trunkLean: (10, 40), 
      },
      tolerance: {
        JointAngleKind.leftKnee: 12,
        JointAngleKind.rightKnee: 12,
        JointAngleKind.leftHip: 14,
        JointAngleKind.rightHip: 14,
        JointAngleKind.trunkLean: 10,
      },
      weights: {
        JointAngleKind.leftKnee: 1.0,
        JointAngleKind.rightKnee: 1.0,
        JointAngleKind.leftHip: 0.9,
        JointAngleKind.rightHip: 0.9,
        JointAngleKind.trunkLean: 0.7,
      },
    );

    return ExerciseDefinition(
      id: 'squat',
      primaryJoint: JointAngleKind.leftKnee,
      startAtHigh: true,
      highEnter: 160,
      highExit: 150,
      lowEnter: 105,
      lowExit: 115,
      minRepMs: 600,
      sampleCount: _n,
      template: tpl,
    );
  }

  static ExerciseDefinition _pushup() {
    final tpl = _cosTemplate(
      exerciseId: 'pushup',
      startHigh: true,
      jointTargets: {
        JointAngleKind.leftElbow: (175, 90),
        JointAngleKind.rightElbow: (175, 90),
        JointAngleKind.leftHip: (175, 165),
        JointAngleKind.rightHip: (175, 165),
        JointAngleKind.trunkLean: (5, 10),
      },
      tolerance: {
        JointAngleKind.leftElbow: 14,
        JointAngleKind.rightElbow: 14,
        JointAngleKind.leftHip: 10,
        JointAngleKind.rightHip: 10,
        JointAngleKind.trunkLean: 8,
      },
      weights: {
        JointAngleKind.leftElbow: 1.0,
        JointAngleKind.rightElbow: 1.0,
        JointAngleKind.leftHip: 0.7,
        JointAngleKind.rightHip: 0.7,
        JointAngleKind.trunkLean: 0.6,
      },
    );

    return ExerciseDefinition(
      id: 'pushup',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 105,
      lowExit: 115,
      minRepMs: 500,
      sampleCount: _n,
      template: tpl,
    );
  }

  static ExerciseDefinition _curl() {
    final tpl = _cosTemplate(
      exerciseId: 'curl',
      startHigh: true, 
      jointTargets: {
        JointAngleKind.leftElbow: (175, 55),
        JointAngleKind.rightElbow: (175, 55),
        JointAngleKind.leftShoulder: (25, 40), 
        JointAngleKind.rightShoulder: (25, 40),
      },
      tolerance: {
        JointAngleKind.leftElbow: 16,
        JointAngleKind.rightElbow: 16,
        JointAngleKind.leftShoulder: 18,
        JointAngleKind.rightShoulder: 18,
      },
      weights: {
        JointAngleKind.leftElbow: 1.0,
        JointAngleKind.rightElbow: 1.0,
        JointAngleKind.leftShoulder: 0.4,
        JointAngleKind.rightShoulder: 0.4,
      },
    );

    return ExerciseDefinition(
      id: 'curl',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 75,
      lowExit: 85,
      minRepMs: 450,
      sampleCount: _n,
      template: tpl,
    );
  }

  static ExerciseDefinition _shoulderPress() {
    final tpl = _cosTemplate(
      exerciseId: 'shoulder_press',
      startHigh: false,
      jointTargets: {
        JointAngleKind.leftElbow: (95, 170),
        JointAngleKind.rightElbow: (95, 170),
        JointAngleKind.leftShoulder: (70, 130),
        JointAngleKind.rightShoulder: (70, 130),
        JointAngleKind.trunkLean: (5, 15),
      },
      tolerance: {
        JointAngleKind.leftElbow: 16,
        JointAngleKind.rightElbow: 16,
        JointAngleKind.leftShoulder: 18,
        JointAngleKind.rightShoulder: 18,
        JointAngleKind.trunkLean: 10,
      },
      weights: {
        JointAngleKind.leftElbow: 1.0,
        JointAngleKind.rightElbow: 1.0,
        JointAngleKind.leftShoulder: 0.8,
        JointAngleKind.rightShoulder: 0.8,
        JointAngleKind.trunkLean: 0.6,
      },
    );

    return ExerciseDefinition(
      id: 'shoulder_press',
      primaryJoint: JointAngleKind.leftElbow,
      startAtHigh: false,
      highEnter: 155,
      highExit: 145,
      lowEnter: 110,
      lowExit: 120,
      minRepMs: 600,
      sampleCount: _n,
      template: tpl,
    );
  }

  static ExerciseDefinition _hipHinge() {
    final tpl = _cosTemplate(
      exerciseId: 'hip_hinge',
      startHigh: true,
      jointTargets: {
        JointAngleKind.leftHip: (175, 85),
        JointAngleKind.rightHip: (175, 85),
        JointAngleKind.leftKnee: (170, 150),
        JointAngleKind.rightKnee: (170, 150),
        JointAngleKind.trunkLean: (10, 60),
      },
      tolerance: {
        JointAngleKind.leftHip: 16,
        JointAngleKind.rightHip: 16,
        JointAngleKind.leftKnee: 14,
        JointAngleKind.rightKnee: 14,
        JointAngleKind.trunkLean: 14,
      },
      weights: {
        JointAngleKind.leftHip: 1.0,
        JointAngleKind.rightHip: 1.0,
        JointAngleKind.leftKnee: 0.6,
        JointAngleKind.rightKnee: 0.6,
        JointAngleKind.trunkLean: 0.8,
      },
    );

    return ExerciseDefinition(
      id: 'hip_hinge',
      primaryJoint: JointAngleKind.leftHip,
      startAtHigh: true,
      highEnter: 155,
      highExit: 145,
      lowEnter: 110,
      lowExit: 120,
      minRepMs: 650,
      sampleCount: _n,
      template: tpl,
    );
  }

  static PoseRepTemplate _cosTemplate({
    required String exerciseId,
    required bool startHigh,
    required Map<JointAngleKind, (double high, double low)> jointTargets,
    required Map<JointAngleKind, double> tolerance,
    required Map<JointAngleKind, double> weights,
  }) {
    final curves = <JointAngleKind, List<double>>{};

    for (final e in jointTargets.entries) {
      final high = e.value.$1;
      final low = e.value.$2;
      final mid = (high + low) / 2.0;
      final amp = (high - low).abs() / 2.0;

      curves[e.key] = List.generate(_n, (i) {
        final p = i / (_n - 1);
        final c = math.cos(2 * math.pi * p); 
        return startHigh ? (mid + amp * c) : (mid - amp * c);
      });
    }

    return PoseRepTemplate(
      exerciseId: exerciseId,
      sampleCount: _n,
      jointCurves: curves,
      toleranceDeg: tolerance,
      weights: weights,
    );
  }
}
