import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum JointAngleKind {
  leftElbow,
  rightElbow,
  leftKnee,
  rightKnee,
  leftHip,
  rightHip,
  leftShoulder,   
  rightShoulder, 
  trunkLean,     
}

class AngleRange {
  final double min; 
  final double max; 
  const AngleRange(this.min, this.max);

  bool contains(double v) => v >= min && v <= max;

  double outsideDelta(double v) {
    if (contains(v)) return 0.0;
    if (v < min) return (min - v).abs();
    return (v - max).abs();
  }
}


class PoseFrameTemplate {
  final String id; 
  final Map<JointAngleKind, AngleRange> expectedRanges;
  final Map<JointAngleKind, double> weights; 

  const PoseFrameTemplate({
    required this.id,
    required this.expectedRanges,
    required this.weights,
  });

  double weightOf(JointAngleKind k) => weights[k] ?? 1.0;
}

class PoseAngles {
  final Map<JointAngleKind, double> values;
  const PoseAngles(this.values);

  double? operator [](JointAngleKind k) => values[k];

  static PoseAngles fromPose(Pose pose) {
    final lm = pose.landmarks;
    PoseLandmark? g(PoseLandmarkType t) => lm[t];

    double? angAt(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
      if (a == null || b == null || c == null) return null;
      final bax = a.x - b.x, bay = a.y - b.y;
      final bcx = c.x - b.x, bcy = c.y - b.y;
      final baLen = math.sqrt(bax * bax + bay * bay);
      final bcLen = math.sqrt(bcx * bcx + bcy * bcy);
      if (baLen < 1e-6 || bcLen < 1e-6) return null;
      final cosT = ((bax * bcx) + (bay * bcy)) / (baLen * bcLen);
      final clamped = cosT.clamp(-1.0, 1.0);
      final rad = math.acos(clamped);
      return rad * 180.0 / math.pi;
    }

    double? trunkLeanDeg(PoseLandmark? hip, PoseLandmark? shoulder) {
      if (hip == null || shoulder == null) return null;
      final vx = shoulder.x - hip.x;
      final vy = shoulder.y - hip.y;
      final len = math.sqrt(vx * vx + vy * vy);
      if (len < 1e-6) return null;
      final cosT = (-vy) / len;
      final clamped = cosT.clamp(-1.0, 1.0);
      final rad = math.acos(clamped);
      final deg = rad * 180.0 / math.pi;
      return deg.abs();
    }

    final values = <JointAngleKind, double>{};

    final lElbow = angAt(g(PoseLandmarkType.leftShoulder), g(PoseLandmarkType.leftElbow), g(PoseLandmarkType.leftWrist));
    final rElbow = angAt(g(PoseLandmarkType.rightShoulder), g(PoseLandmarkType.rightElbow), g(PoseLandmarkType.rightWrist));

    final lKnee = angAt(g(PoseLandmarkType.leftHip), g(PoseLandmarkType.leftKnee), g(PoseLandmarkType.leftAnkle));
    final rKnee = angAt(g(PoseLandmarkType.rightHip), g(PoseLandmarkType.rightKnee), g(PoseLandmarkType.rightAnkle));

    final lHip = angAt(g(PoseLandmarkType.leftShoulder), g(PoseLandmarkType.leftHip), g(PoseLandmarkType.leftKnee));
    final rHip = angAt(g(PoseLandmarkType.rightShoulder), g(PoseLandmarkType.rightHip), g(PoseLandmarkType.rightKnee));

    final lShoulder = angAt(g(PoseLandmarkType.leftHip), g(PoseLandmarkType.leftShoulder), g(PoseLandmarkType.leftElbow));
    final rShoulder = angAt(g(PoseLandmarkType.rightHip), g(PoseLandmarkType.rightShoulder), g(PoseLandmarkType.rightElbow));

    final tLeft = trunkLeanDeg(g(PoseLandmarkType.leftHip), g(PoseLandmarkType.leftShoulder));
    final tRight = trunkLeanDeg(g(PoseLandmarkType.rightHip), g(PoseLandmarkType.rightShoulder));
    final trunk = _avgNullable([tLeft, tRight]);

    if (lElbow != null) values[JointAngleKind.leftElbow] = lElbow;
    if (rElbow != null) values[JointAngleKind.rightElbow] = rElbow;
    if (lKnee != null) values[JointAngleKind.leftKnee] = lKnee;
    if (rKnee != null) values[JointAngleKind.rightKnee] = rKnee;
    if (lHip != null) values[JointAngleKind.leftHip] = lHip;
    if (rHip != null) values[JointAngleKind.rightHip] = rHip;
    if (lShoulder != null) values[JointAngleKind.leftShoulder] = lShoulder;
    if (rShoulder != null) values[JointAngleKind.rightShoulder] = rShoulder;
    if (trunk != null) values[JointAngleKind.trunkLean] = trunk;

    return PoseAngles(values);
  }
}

double? _avgNullable(List<double?> vals) {
  final filtered = vals.whereType<double>().toList();
  if (filtered.isEmpty) return null;
  return filtered.reduce((a, b) => a + b) / filtered.length;
}

class PoseComparisonConfig {
  final double outsideFalloffDeg;

  const PoseComparisonConfig({this.outsideFalloffDeg = 15.0});
}

class PoseComparisonResult {
  final String templateId;
  final double overallScore;
  final Map<JointAngleKind, double> perJointScores;
  final Map<JointAngleKind, double> measuredAngles; 

  const PoseComparisonResult({
    required this.templateId,
    required this.overallScore,
    required this.perJointScores,
    required this.measuredAngles,
  });
}

class PoseComparator {
  static PoseComparisonResult compare(
    PoseAngles angles,
    PoseFrameTemplate template, {
    PoseComparisonConfig config = const PoseComparisonConfig(),
  }) {
    final perJoint = <JointAngleKind, double>{};
    final measured = <JointAngleKind, double>{};

    double weightedSum = 0.0;
    double weightTotal = 0.0;

    template.expectedRanges.forEach((joint, range) {
      final v = angles[joint];
      final w = template.weightOf(joint).clamp(0.0, 1.0);
      if (v == null || w <= 0.0) return; 

      measured[joint] = v;

      double s;
      if (range.contains(v)) {
        s = 1.0;
      } else {
        final d = range.outsideDelta(v);
        final k = config.outsideFalloffDeg.clamp(1e-3, 180.0);
        s = math.exp(-math.pow(d / k, 2)); 
      }

      perJoint[joint] = s;
      weightedSum += s * w;
      weightTotal += w;
    });

    final overall = weightTotal > 0 ? (weightedSum / weightTotal) : 0.0;
    return PoseComparisonResult(
      templateId: template.id,
      overallScore: (overall * 100.0).clamp(0.0, 100.0),
      perJointScores: perJoint,
      measuredAngles: measured,
    );
  }
}

class ExercisePoseTemplates {
  static PoseFrameTemplate squatTop() => PoseFrameTemplate(
        id: 'squat_top',
        expectedRanges: {
          JointAngleKind.leftKnee: AngleRange(165, 185),
          JointAngleKind.rightKnee: AngleRange(165, 185),
          JointAngleKind.leftHip: AngleRange(160, 190),
          JointAngleKind.rightHip: AngleRange(160, 190),
          JointAngleKind.trunkLean: AngleRange(0, 15),
        },
        weights: {
          JointAngleKind.leftKnee: 1.0,
          JointAngleKind.rightKnee: 1.0,
          JointAngleKind.leftHip: 1.0,
          JointAngleKind.rightHip: 1.0,
          JointAngleKind.trunkLean: 0.6,
        },
      );

  static PoseFrameTemplate squatBottom() => PoseFrameTemplate(
        id: 'squat_bottom',
        expectedRanges: {
          JointAngleKind.leftKnee: AngleRange(75, 105),
          JointAngleKind.rightKnee: AngleRange(75, 105),
          JointAngleKind.leftHip: AngleRange(60, 95),
          JointAngleKind.rightHip: AngleRange(60, 95),
          JointAngleKind.trunkLean: AngleRange(10, 45),
        },
        weights: {
          JointAngleKind.leftKnee: 1.0,
          JointAngleKind.rightKnee: 1.0,
          JointAngleKind.leftHip: 1.0,
          JointAngleKind.rightHip: 1.0,
          JointAngleKind.trunkLean: 0.7,
        },
      );

  static PoseFrameTemplate pushupTop() => PoseFrameTemplate(
        id: 'pushup_top',
        expectedRanges: {
          JointAngleKind.leftElbow: AngleRange(165, 190),
          JointAngleKind.rightElbow: AngleRange(165, 190),
          JointAngleKind.leftHip: AngleRange(165, 190),  
          JointAngleKind.rightHip: AngleRange(165, 190), 
          JointAngleKind.trunkLean: AngleRange(0, 15),  
        },
        weights: {
          JointAngleKind.leftElbow: 1.0,
          JointAngleKind.rightElbow: 1.0,
          JointAngleKind.leftHip: 0.8,
          JointAngleKind.rightHip: 0.8,
          JointAngleKind.trunkLean: 0.6,
        },
      );

  static PoseFrameTemplate pushupBottom() => PoseFrameTemplate(
        id: 'pushup_bottom',
        expectedRanges: {
          JointAngleKind.leftElbow: AngleRange(70, 105),
          JointAngleKind.rightElbow: AngleRange(70, 105),
          JointAngleKind.leftHip: AngleRange(160, 190),
          JointAngleKind.rightHip: AngleRange(160, 190),
          JointAngleKind.trunkLean: AngleRange(0, 20),
        },
        weights: {
          JointAngleKind.leftElbow: 1.0,
          JointAngleKind.rightElbow: 1.0,
          JointAngleKind.leftHip: 0.8,
          JointAngleKind.rightHip: 0.8,
          JointAngleKind.trunkLean: 0.6,
        },
      );
}
