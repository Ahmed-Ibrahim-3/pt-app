import 'dart:math' as math;

import 'pose_comparison.dart';
import 'rep_analyser.dart';
import 'rep_templates.dart';

class RepScore {
  final String exerciseId;
  final double overall; 
  final Map<JointAngleKind, double> perJoint;
  final Map<JointAngleKind, List<double>> perJointPointScores; 

  const RepScore({
    required this.exerciseId,
    required this.overall,
    required this.perJoint,
    required this.perJointPointScores,
  });
}

class RepScorer {
  static RepScore scoreRep(CapturedRep rep, PoseRepTemplate template) {
    final n = template.sampleCount;

    final perJoint = <JointAngleKind, double>{};
    final perJointPointScores = <JointAngleKind, List<double>>{};

    double weightedSum = 0;
    double weightTotal = 0;

    for (final joint in template.jointCurves.keys) {
      final target = template.jointCurves[joint]!;
      final tol = (template.toleranceDeg[joint] ?? 15).clamp(1.0, 60.0);
      final w = (template.weights[joint] ?? 1.0).clamp(0.0, 5.0);

      final user = _resampleJoint(rep.samples, joint, n);
      final pointScores = <double>[];

      for (var i = 0; i < n; i++) {
        final u = user[i];
        final t = target[i];
        if (u.isNaN || t.isNaN) {
          pointScores.add(double.nan);
          continue;
        }
        final err = (u - t).abs();
        final s01 = math.exp(-math.pow(err / tol, 2)); 
        pointScores.add((s01 * 100).clamp(0, 100));
      }

      final jointScore = _meanIgnoringNaN(pointScores);
      if (!jointScore.isNaN) {
        perJoint[joint] = jointScore;
        perJointPointScores[joint] = pointScores;

        weightedSum += (jointScore / 100.0) * w;
        weightTotal += w;
      }
    }

    final overall01 = weightTotal > 0 ? (weightedSum / weightTotal) : 0.0;
    return RepScore(
      exerciseId: rep.exerciseId,
      overall: (overall01 * 100).clamp(0, 100),
      perJoint: perJoint,
      perJointPointScores: perJointPointScores,
    );
  }

  static List<double> _resampleJoint(List<PoseAngleSample> samples, JointAngleKind joint, int n) {
    if (samples.isEmpty) return List.filled(n, double.nan);

    final start = samples.first.tMs;
    final end = samples.last.tMs;
    final span = (end - start).clamp(1, 1 << 30);

    final ts = <int>[];
    final vs = <double>[];
    double? last;

    for (final s in samples) {
      final v = s.angles[joint];
      if (v != null) last = v;
      ts.add(s.tMs);
      vs.add(last ?? double.nan);
    }

    final out = List<double>.filled(n, double.nan);
    int j = 0;

    for (var i = 0; i < n; i++) {
      final targetT = start + ((span * i) / (n - 1)).round();

      while (j + 1 < ts.length && ts[j + 1] < targetT) {
        j++;
      }

      if (j + 1 >= ts.length) {
        out[i] = vs.last;
        continue;
      }

      final t0 = ts[j];
      final t1 = ts[j + 1];
      final v0 = vs[j];
      final v1 = vs[j + 1];

      if (v0.isNaN && v1.isNaN) {
        out[i] = double.nan;
        continue;
      }
      if (t1 == t0) {
        out[i] = v1.isNaN ? v0 : v1;
        continue;
      }
      if (v0.isNaN) {
        out[i] = v1;
        continue;
      }
      if (v1.isNaN) {
        out[i] = v0;
        continue;
      }

      final a = (targetT - t0) / (t1 - t0);
      out[i] = v0 + (v1 - v0) * a;
    }

    return out;
  }

  static double _meanIgnoringNaN(List<double> xs) {
    var sum = 0.0;
    var count = 0;
    for (final x in xs) {
      if (x.isNaN) continue;
      sum += x;
      count++;
    }
    return count == 0 ? double.nan : (sum / count);
  }
}
