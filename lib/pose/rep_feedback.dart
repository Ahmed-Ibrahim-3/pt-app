import 'dart:math' as math;

import 'pose_comparison.dart';
import 'rep_analyser.dart';
import 'rep_templates.dart';

enum RepPhaseBucket { start, mid, opposite }

class FeedbackCue {
  final String id;
  final String message;

  final double deltaDeg;

  final double overTolDeg;

  final JointAngleKind? joint;
  final RepPhaseBucket? phase;

  const FeedbackCue({
    required this.id,
    required this.message,
    required this.deltaDeg,
    required this.overTolDeg,
    this.joint,
    this.phase,
  });
}

class RepFeedback {
  final String exerciseId;
  final List<FeedbackCue> cues;

  const RepFeedback({required this.exerciseId, required this.cues});
}

class RepFeedbackGenerator {
  static RepFeedback generate(
    CapturedRep rep,
    ExerciseDefinition def, {
    int maxCues = 3,
    double minOverTolDeg = 4.0,
  }) {
    final tpl = def.template;
    final samples = rep.samples;
    if (samples.length < 6) {
      return RepFeedback(exerciseId: rep.exerciseId, cues: const []);
    }

    final series = _forwardFillSeries(samples);
    final primary = _primarySeriesWithFallback(def.primaryJoint, series);

    final primaryClean = primary.whereType<double>().toList();
    if (primaryClean.length < math.max(6, (samples.length * 0.35).round())) {
      return RepFeedback(exerciseId: rep.exerciseId, cues: const []);
    }

    final startWin = _windowMean(primary, 0, (samples.length * 0.12).ceil());
    final endWin = _windowMean(primary, (samples.length * 0.88).floor(), samples.length);

    final startObs = def.startAtHigh
        ? math.max(startWin ?? primaryClean.first, endWin ?? primaryClean.last)
        : math.min(startWin ?? primaryClean.first, endWin ?? primaryClean.last);

    final oppObs = def.startAtHigh ? _minIgnoringNull(primary) : _maxIgnoringNull(primary);

    final denom = (startObs - oppObs).abs();
    if (denom < 8.0) {
      return RepFeedback(exerciseId: rep.exerciseId, cues: const []);
    }

    double sFromPrimary(double a) {
      final s = def.startAtHigh
          ? ((startObs - a) / (startObs - oppObs))
          : ((a - startObs) / (oppObs - startObs));
      return s.clamp(0.0, 1.0);
    }

    final offsets = <JointAngleKind, double>{};
    for (final e in tpl.joints.entries) {
      final joint = e.key;
      final targetStart = e.value.start;
      final obsStart = _jointStartMean(series[joint]);
      if (obsStart != null) offsets[joint] = obsStart - targetStart;
    }

    final cues = <FeedbackCue>[];

    for (final entry in tpl.joints.entries) {
      final joint = entry.key;
      final spec = entry.value;

      final jointSeries = series[joint];
      if (jointSeries == null) continue;

      final tol = spec.toleranceDeg.clamp(4.0, 60.0);
      final offset = offsets[joint] ?? 0.0;

      double? bestDelta;
      double bestOver = 0.0;
      RepPhaseBucket? bestPhase;

      for (var i = 0; i < samples.length; i++) {
        final aP = primary[i];
        final aJ = jointSeries[i];
        if (aP == null || aJ == null) continue;

        final s = sFromPrimary(aP);
        final expected = _lerp(spec.start + offset, spec.opposite + offset, s);

        final delta = aJ - expected; 
        final over = math.max(0.0, delta.abs() - tol);

        if (over > bestOver) {
          bestOver = over;
          bestDelta = delta;
          bestPhase = _bucketPhase(s);
        }
      }

      if (bestDelta == null || bestPhase == null) continue;
      if (bestOver < math.max(0.0, minOverTolDeg)) continue;

      final msg = _jointCueMessage(
        def: def,
        joint: joint,
        phase: bestPhase,
        deltaDeg: bestDelta,
      );

      final dir = bestDelta > 0 ? 'decrease' : 'increase';
      cues.add(
        FeedbackCue(
          id: 'joint:${def.id}:${joint.name}:${bestPhase.name}:$dir',
          message: msg,
          deltaDeg: bestDelta,
          overTolDeg: bestOver,
          joint: joint,
          phase: bestPhase,
        ),
      );
    }

    final romCue = _romCue(def, offsets, startObs, oppObs);
    if (romCue != null) cues.add(romCue);

    final lockoutCue = _lockoutCue(def, offsets, startObs);
    if (lockoutCue != null) cues.add(lockoutCue);

    final symCue = _symmetryCue(def, series);
    if (symCue != null) cues.add(symCue);

    cues.sort((a, b) => b.overTolDeg.compareTo(a.overTolDeg));

    final picked = <FeedbackCue>[];
    final seenIds = <String>{};
    for (final c in cues) {
      if (picked.length >= maxCues) break;
      if (seenIds.add(c.id)) picked.add(c);
    }

    return RepFeedback(exerciseId: rep.exerciseId, cues: picked);
  }

  static List<String> summariseSet(
    List<RepFeedback> reps,
    ExerciseDefinition def, {
    int maxItems = 5,
  }) {
    final bucket = <String, List<FeedbackCue>>{};
    for (final r in reps) {
      for (final c in r.cues) {
        bucket.putIfAbsent(c.id, () => []).add(c);
      }
    }

    final scored = <({String id, double score, FeedbackCue sample})>[];
    bucket.forEach((id, list) {
      final meanOver = list.map((c) => c.overTolDeg).reduce((a, b) => a + b) / list.length;
      final score = meanOver * (1.0 + math.log(list.length + 1));
      scored.add((id: id, score: score, sample: list.first));
    });

    scored.sort((a, b) => b.score.compareTo(a.score));

    final out = <String>[];
    for (final s in scored.take(maxItems)) {
      out.add(s.sample.message);
    }
    return out;
  }

  static String _jointCueMessage({
    required ExerciseDefinition def,
    required JointAngleKind joint,
    required RepPhaseBucket phase,
    required double deltaDeg,
  }) {
    switch (def.id) {
      case 'bench_press':
        return _benchPressCue(def, joint, phase, deltaDeg);
      case 'deadlift':
        return _deadliftCue(def, joint, phase, deltaDeg);
      case 'squat':
        return _squatCue(def, joint, phase, deltaDeg);
      default:
        return _genericCue(def, joint, phase, deltaDeg);
    }
  }

  static String _benchPressCue(
    ExerciseDefinition def,
    JointAngleKind joint,
    RepPhaseBucket phase,
    double deltaDeg,
  ) {
    final where = _phaseLabel(def, phase);
    final amt = _degText(deltaDeg);

    if (joint == JointAngleKind.leftElbow || joint == JointAngleKind.rightElbow) {
      if (deltaDeg > 0) {
        if (phase == RepPhaseBucket.opposite) {
          return '$where, lower the bar a bit more — bend your elbows $amt.';
        }
        return '$where, add more elbow bend — bend your elbows $amt.';
      } else {
        if (phase == RepPhaseBucket.start) {
          return '$where, finish the rep — straighten your elbows $amt (full lockout).';
        }
        return '$where, press a bit more — straighten your elbows $amt.';
      }
    }

    return _genericCue(def, joint, phase, deltaDeg);
  }

  static String _deadliftCue(
    ExerciseDefinition def,
    JointAngleKind joint,
    RepPhaseBucket phase,
    double deltaDeg,
  ) {
    final where = _phaseLabel(def, phase);
    final amt = _degText(deltaDeg);

    switch (joint) {
      case JointAngleKind.leftHip:
      case JointAngleKind.rightHip:
        if (deltaDeg > 0) {
          return '$where, hinge deeper — push your hips back $amt.';
        }
        return '$where, stand taller — drive your hips through $amt.';

      case JointAngleKind.leftKnee:
      case JointAngleKind.rightKnee:
        if (deltaDeg > 0) {
          return '$where, add a bit more knee bend $amt (don’t turn it into a stiff-leg).';
        }
        return '$where, keep your knees back $amt — make it more “hips back” than “squat down”.';

      case JointAngleKind.trunkLean:
        if (deltaDeg > 0) {
          return '$where, keep your chest up and brace — reduce the forward lean $amt.';
        }
        return '$where, hinge a bit more — let your torso come forward $amt while keeping your back neutral.';

      default:
        return _genericCue(def, joint, phase, deltaDeg);
    }
  }

  static String _squatCue(
    ExerciseDefinition def,
    JointAngleKind joint,
    RepPhaseBucket phase,
    double deltaDeg,
  ) {
    final where = _phaseLabel(def, phase);
    final amt = _degText(deltaDeg);

    switch (joint) {
      case JointAngleKind.leftKnee:
      case JointAngleKind.rightKnee:
        if (deltaDeg > 0) {
          return '$where, go a bit deeper — bend your knees $amt.';
        }
        return '$where, stand fully tall — straighten your knees $amt.';

      case JointAngleKind.leftHip:
      case JointAngleKind.rightHip:
        if (deltaDeg > 0) {
          return '$where, sit back and down more — increase hip bend $amt.';
        }
        return '$where, finish the rep — extend your hips $amt.';

      case JointAngleKind.trunkLean:
        if (deltaDeg > 0) {
          return '$where, keep your chest up — reduce forward lean $amt.';
        }
        return '$where, allow a touch more hinge — let your torso come forward $amt (stay braced).';

      default:
        return _genericCue(def, joint, phase, deltaDeg);
    }
  }

  static String _genericCue(
    ExerciseDefinition def,
    JointAngleKind joint,
    RepPhaseBucket phase,
    double deltaDeg,
  ) {
    final where = _phaseLabel(def, phase);
    final part = _jointLabel(joint);
    final act = _jointAction(joint, deltaDeg);
    final amt = _degText(deltaDeg);

    if (joint == JointAngleKind.trunkLean) {
      return '$where, $act $amt.';
    }
    if (joint == JointAngleKind.leftHip || joint == JointAngleKind.rightHip) {
      return '$where, $act $amt.';
    }
    if (joint == JointAngleKind.leftShoulder || joint == JointAngleKind.rightShoulder) {
      return '$where, $act $part $amt.';
    }
    return '$where, $act $part $amt.';
  }


  static RepPhaseBucket _bucketPhase(double s) {
    if (s <= 0.20) return RepPhaseBucket.start;
    if (s >= 0.80) return RepPhaseBucket.opposite;
    return RepPhaseBucket.mid;
  }

  static String _phaseLabel(ExerciseDefinition def, RepPhaseBucket phase) {
    switch (phase) {
      case RepPhaseBucket.start:
        return def.startAtHigh ? 'At the top' : 'At the bottom';
      case RepPhaseBucket.opposite:
        return def.startAtHigh ? 'At the bottom' : 'At the top';
      case RepPhaseBucket.mid:
        return 'Mid-rep';
    }
  }

  static String _degText(double deg) {
    final v = deg.abs();
    final rounded = math.max(2, (v / 2.0).round() * 2);
    return 'by about ${rounded}°';
  }

  static String _jointLabel(JointAngleKind j) {
    switch (j) {
      case JointAngleKind.leftElbow:
        return 'your left elbow';
      case JointAngleKind.rightElbow:
        return 'your right elbow';
      case JointAngleKind.leftKnee:
        return 'your left knee';
      case JointAngleKind.rightKnee:
        return 'your right knee';
      case JointAngleKind.leftHip:
      case JointAngleKind.rightHip:
        return 'your hips';
      case JointAngleKind.leftShoulder:
        return 'your left upper arm';
      case JointAngleKind.rightShoulder:
        return 'your right upper arm';
      case JointAngleKind.trunkLean:
        return 'your torso';
    }
  }

  static String _jointAction(JointAngleKind j, double deltaDeg) {
    final needDecrease = deltaDeg > 0;
    switch (j) {
      case JointAngleKind.leftElbow:
      case JointAngleKind.rightElbow:
        return needDecrease ? 'bend' : 'straighten';
      case JointAngleKind.leftKnee:
      case JointAngleKind.rightKnee:
        return needDecrease ? 'bend' : 'straighten';
      case JointAngleKind.leftHip:
      case JointAngleKind.rightHip:
        return needDecrease ? 'hinge/sit back a bit more' : 'stand a bit taller';
      case JointAngleKind.leftShoulder:
      case JointAngleKind.rightShoulder:
        return needDecrease ? 'lower' : 'raise';
      case JointAngleKind.trunkLean:
        return needDecrease ? 'stay more upright' : 'lean forward a bit more';
    }
  }

  static FeedbackCue? _romCue(
    ExerciseDefinition def,
    Map<JointAngleKind, double> offsets,
    double startObs,
    double oppObs,
  ) {
    final spec = def.template.joints[def.primaryJoint];
    if (spec == null) return null;

    final offset = offsets[def.primaryJoint] ?? 0.0;
    final targetOpp = spec.opposite + offset;

    final delta = def.startAtHigh ? (oppObs - targetOpp) : (targetOpp - oppObs);
    if (delta <= 6.0) return null;

    final phase = RepPhaseBucket.opposite;
    final where = _phaseLabel(def, phase);
    final amt = _degText(delta);

    final msg = '$where, aim for a bit more range of motion $amt.';
    return FeedbackCue(
      id: 'metric:rom:${def.id}:${def.primaryJoint.name}',
      message: msg,
      deltaDeg: delta,
      overTolDeg: delta,
      joint: def.primaryJoint,
      phase: phase,
    );
  }

  static FeedbackCue? _lockoutCue(
    ExerciseDefinition def,
    Map<JointAngleKind, double> offsets,
    double startObs,
  ) {
    final spec = def.template.joints[def.primaryJoint];
    if (spec == null) return null;

    final offset = offsets[def.primaryJoint] ?? 0.0;
    final targetStart = spec.start + offset;

    final delta = def.startAtHigh ? (targetStart - startObs) : (startObs - targetStart);
    if (delta <= 6.0) return null;

    final phase = RepPhaseBucket.start;
    final where = _phaseLabel(def, phase);
    final amt = _degText(delta);

    final msg = '$where, complete the lockout $amt.';
    return FeedbackCue(
      id: 'metric:lockout:${def.id}:${def.primaryJoint.name}',
      message: msg,
      deltaDeg: delta,
      overTolDeg: delta,
      joint: def.primaryJoint,
      phase: phase,
    );
  }

  static FeedbackCue? _symmetryCue(
    ExerciseDefinition def,
    Map<JointAngleKind, List<double?>> series,
  ) {
    final tol = def.template.symmetryToleranceDeg.clamp(6.0, 30.0);

    const pairs = [
      (JointAngleKind.leftElbow, JointAngleKind.rightElbow, 'elbows'),
      (JointAngleKind.leftKnee, JointAngleKind.rightKnee, 'knees'),
      (JointAngleKind.leftHip, JointAngleKind.rightHip, 'hips'),
      (JointAngleKind.leftShoulder, JointAngleKind.rightShoulder, 'upper arms'),
    ];

    double bestOver = 0.0;
    String? bestLabel;
    double bestSigned = 0.0;

    for (final (l, r, label) in pairs) {
      final ls = series[l];
      final rs = series[r];
      if (ls == null || rs == null) continue;

      var sumAbs = 0.0;
      var sumSigned = 0.0;
      var count = 0;

      for (var i = 0; i < math.min(ls.length, rs.length); i++) {
        final a = ls[i];
        final b = rs[i];
        if (a == null || b == null) continue;
        final d = b - a; 
        sumAbs += d.abs();
        sumSigned += d;
        count++;
      }
      if (count < 8) continue;

      final meanAbs = sumAbs / count;
      final meanSigned = sumSigned / count;
      final over = math.max(0.0, meanAbs - tol);

      if (over > bestOver) {
        bestOver = over;
        bestLabel = label;
        bestSigned = meanSigned;
      }
    }

    if (bestLabel == null || bestOver < 5.0) return null;

    final sideHint = bestSigned > 0
        ? 'Your right side stayed a bit straighter than your left'
        : 'Your left side stayed a bit straighter than your right';

    final msg = 'Keep your $bestLabel more even. $sideHint.';
    return FeedbackCue(
      id: 'metric:symmetry:${def.id}:$bestLabel',
      message: msg,
      deltaDeg: bestSigned,
      overTolDeg: bestOver,
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

    JointAngleKind fallback;
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
}
