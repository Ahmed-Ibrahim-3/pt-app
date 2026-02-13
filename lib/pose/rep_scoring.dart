import 'dart:math' as math;

import 'pose_comparison.dart';
import 'rep_analyser.dart';
import 'rep_templates.dart';

class RepScore {
  final String exerciseId;

  final double overall;
  final Map<JointAngleKind, double> perJoint;
  final Map<String, double> metrics;

  const RepScore({
    required this.exerciseId,
    required this.overall,
    required this.perJoint,
    required this.metrics,
  });
}

class RepScorer {
  static RepScore scoreRep(CapturedRep rep, ExerciseDefinition def) {
    final tpl = def.template;
    final samples = rep.samples;
    if (samples.isEmpty) {
      return RepScore(
        exerciseId: rep.exerciseId,
        overall: 0,
        perJoint: const {},
        metrics: const {'rom': 0, 'lockout': 0, 'symmetry': 0},
      );
    }

    final series = _forwardFillSeries(samples);

    final primary = _primarySeriesWithFallback(def.primaryJoint, series);
    final primaryClean = primary.whereType<double>().toList();
    if (primaryClean.length < math.max(6, (samples.length * 0.35).round())) {
      return RepScore(
        exerciseId: rep.exerciseId,
        overall: 0,
        perJoint: const {},
        metrics: const {'rom': 0, 'lockout': 0, 'symmetry': 0},
      );
    }

    final startWin = _windowMean(primary, 0, (samples.length * 0.12).ceil());
    final endWin = _windowMean(primary, (samples.length * 0.88).floor(), samples.length);

    final startObs = def.startAtHigh
        ? math.max(startWin ?? primaryClean.first, endWin ?? primaryClean.last)
        : math.min(startWin ?? primaryClean.first, endWin ?? primaryClean.last);

    final oppObs = def.startAtHigh ? _minIgnoringNull(primary) : _maxIgnoringNull(primary);

    final denom = (startObs - oppObs).abs();
    if (denom < 8.0) {
      return RepScore(
        exerciseId: rep.exerciseId,
        overall: 0,
        perJoint: const {},
        metrics: const {'rom': 0, 'lockout': 0, 'symmetry': 0},
      );
    }

    double sFromPrimary(double a) {
      final s = def.startAtHigh ? ((startObs - a) / (startObs - oppObs)) : ((a - startObs) / (oppObs - startObs));
      return s.clamp(0.0, 1.0);
    }

    final jointOffsets = <JointAngleKind, double>{};
    for (final e in tpl.joints.entries) {
      final joint = e.key;
      final targetStart = e.value.start;
      final obsStart = _jointStartMean(series[joint]);
      if (obsStart != null) {
        jointOffsets[joint] = obsStart - targetStart;
      }
    }

    final perJointScores = <JointAngleKind, double>{};

    double weightedSum = 0.0;
    double weightTotal = 0.0;

    for (final entry in tpl.joints.entries) {
      final joint = entry.key;
      final spec = entry.value;

      final tol = spec.toleranceDeg.clamp(4.0, 60.0);
      final w = spec.weight.clamp(0.0, 5.0);
      if (w <= 0) continue;

      final jointSeries = series[joint];
      if (jointSeries == null) continue;

      final offset = jointOffsets[joint] ?? 0.0;

      var sum = 0.0;
      var count = 0;

      for (var i = 0; i < samples.length; i++) {
        final aP = primary[i];
        final aJ = jointSeries[i];
        if (aP == null || aJ == null) continue;

        final s = sFromPrimary(aP);

        final expected = _lerp(spec.start + offset, spec.opposite + offset, s);
        final err = (aJ - expected).abs();

        final over = math.max(0.0, err - tol);
        final k = tol;
        final s01 = math.exp(-math.pow(over / k, 2));

        sum += s01;
        count++;
      }

      if (count == 0) continue;

      final jointScore = (sum / count) * 100.0;
      perJointScores[joint] = jointScore;

      weightedSum += (jointScore / 100.0) * w;
      weightTotal += w;
    }

    final techniqueOverall = weightTotal > 0 ? (weightedSum / weightTotal) * 100.0 : 0.0;

    final rom = _romScore(def, tpl, startObs, oppObs, jointOffsets);
    final lockout = _lockoutScore(def, tpl, startObs, jointOffsets);
    final symmetry = _symmetryScore(series, tpl.symmetryToleranceDeg);

    final symW = tpl.symmetryWeight.clamp(0.0, 0.5);
    final baseW = (1.0 - symW).clamp(0.5, 1.0);

    final overall = (techniqueOverall * (baseW * 0.86) +
            symmetry * (symW * 100.0) +
            rom * (baseW * 0.08) +
            lockout * (baseW * 0.06))
        .clamp(0.0, 100.0);

    return RepScore(
      exerciseId: rep.exerciseId,
      overall: overall,
      perJoint: perJointScores,
      metrics: {
        'rom': rom.clamp(0, 100),
        'lockout': lockout.clamp(0, 100),
        'symmetry': symmetry.clamp(0, 1) * 100.0,
      },
    );
  }

  static Map<JointAngleKind, List<double?>> _forwardFillSeries(List<PoseAngleSample> samples) {
    final out = <JointAngleKind, List<double?>>{};
    final last = <JointAngleKind, double?>{};

    for (final k in JointAngleKind.values) {
      out[k] = List<double?>.filled(samples.length, null);
    }

    for (var i = 0; i < samples.length; i++) {
      final a = samples[i].angles;
      for (final k in JointAngleKind.values) {
        final v = a[k];
        if (v != null) last[k] = v;
        out[k]![i] = last[k];
      }
    }
    return out;
  }

  static List<double?> _primarySeriesWithFallback(
    JointAngleKind primary,
    Map<JointAngleKind, List<double?>> series,
  ) {
    final main = series[primary];
    if (main != null) return main;

    JointAngleKind? fallback;
    switch (primary) {
      case JointAngleKind.leftKnee:
        fallback = JointAngleKind.rightKnee;
        break;
      case JointAngleKind.rightKnee:
        fallback = JointAngleKind.leftKnee;
        break;
      case JointAngleKind.leftElbow:
        fallback = JointAngleKind.rightElbow;
        break;
      case JointAngleKind.rightElbow:
        fallback = JointAngleKind.leftElbow;
        break;
      case JointAngleKind.leftHip:
        fallback = JointAngleKind.rightHip;
        break;
      case JointAngleKind.rightHip:
        fallback = JointAngleKind.leftHip;
        break;
      case JointAngleKind.leftShoulder:
        fallback = JointAngleKind.rightShoulder;
        break;
      case JointAngleKind.rightShoulder:
        fallback = JointAngleKind.leftShoulder;
        break;
      case JointAngleKind.trunkLean:
        fallback = JointAngleKind.trunkLean;
        break;
    }
    return series[fallback] ?? List<double?>.filled(series.values.first.length, null);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double? _windowMean(List<double?> xs, int start, int end) {
    if (xs.isEmpty) return null;
    final s = start.clamp(0, xs.length);
    final e = end.clamp(0, xs.length);
    var sum = 0.0;
    var count = 0;
    for (var i = s; i < e; i++) {
      final v = xs[i];
      if (v == null) continue;
      sum += v;
      count++;
    }
    if (count == 0) return null;
    return sum / count;
  }

  static double? _jointStartMean(List<double?>? xs) {
    if (xs == null || xs.isEmpty) return null;
    final n = xs.length;
    final w = math.max(3, (n * 0.12).ceil());
    final a = _windowMean(xs, 0, w);
    final b = _windowMean(xs, n - w, n);
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return (a + b) / 2.0;
  }

  static double _minIgnoringNull(List<double?> xs) {
    var m = double.infinity;
    for (final v in xs) {
      if (v == null) continue;
      if (v < m) m = v;
    }
    return m.isFinite ? m : 0.0;
  }

  static double _maxIgnoringNull(List<double?> xs) {
    var m = -double.infinity;
    for (final v in xs) {
      if (v == null) continue;
      if (v > m) m = v;
    }
    return m.isFinite ? m : 0.0;
  }

  static double _romScore(
    ExerciseDefinition def,
    PoseRepTemplate tpl,
    double startObs,
    double oppObs,
    Map<JointAngleKind, double> offsets,
  ) {
    final spec = tpl.joints[def.primaryJoint];
    if (spec == null) return 50.0;

    final offset = offsets[def.primaryJoint] ?? 0.0;
    final targetOpp = spec.opposite + offset;

    final delta = def.startAtHigh
        ? math.max(0.0, oppObs - targetOpp) 
        : math.max(0.0, targetOpp - oppObs); 

    final tol = (spec.toleranceDeg * 0.9).clamp(8.0, 25.0);
    final s01 = math.exp(-math.pow(delta / tol, 2));
    return (s01 * 100.0).clamp(0.0, 100.0);
  }

  static double _lockoutScore(
    ExerciseDefinition def,
    PoseRepTemplate tpl,
    double startObs,
    Map<JointAngleKind, double> offsets,
  ) {
    final spec = tpl.joints[def.primaryJoint];
    if (spec == null) return 50.0;

    final offset = offsets[def.primaryJoint] ?? 0.0;
    final targetStart = spec.start + offset;

    final delta = def.startAtHigh
        ? math.max(0.0, targetStart - startObs) 
        : math.max(0.0, startObs - targetStart); 

    final tol = (spec.toleranceDeg * 0.8).clamp(8.0, 25.0);
    final s01 = math.exp(-math.pow(delta / tol, 2));
    return (s01 * 100.0).clamp(0.0, 100.0);
  }

  static double _symmetryScore(
    Map<JointAngleKind, List<double?>> series,
    double toleranceDeg,
  ) {
    final pairs = const [
      (JointAngleKind.leftElbow, JointAngleKind.rightElbow),
      (JointAngleKind.leftKnee, JointAngleKind.rightKnee),
      (JointAngleKind.leftHip, JointAngleKind.rightHip),
      (JointAngleKind.leftShoulder, JointAngleKind.rightShoulder),
    ];

    var sum01 = 0.0;
    var used = 0;

    for (final (l, r) in pairs) {
      final ls = series[l];
      final rs = series[r];
      if (ls == null || rs == null) continue;

      var sumDiff = 0.0;
      var count = 0;

      for (var i = 0; i < math.min(ls.length, rs.length); i++) {
        final a = ls[i];
        final b = rs[i];
        if (a == null || b == null) continue;
        sumDiff += (a - b).abs();
        count++;
      }
      if (count < 6) continue;

      final meanDiff = sumDiff / count;

      final over = math.max(0.0, meanDiff - toleranceDeg.clamp(6.0, 30.0));
      final k = toleranceDeg.clamp(6.0, 30.0);
      final s01 = math.exp(-math.pow(over / k, 2));

      sum01 += s01;
      used++;
    }

    if (used == 0) return 1.0; 
    return (sum01 / used).clamp(0.0, 1.0);
  }
}
