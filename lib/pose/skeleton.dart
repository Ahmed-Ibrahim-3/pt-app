import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_comparison.dart';

class PoseSkeletonPainter extends CustomPainter {
  final Pose pose;
  final Size imageSize; 
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  final Map<JointAngleKind, double>? lastJointScores;

  PoseSkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
    this.lastJointScores,
  });

  static const List<(PoseLandmarkType, PoseLandmarkType)> _connections = [
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),

    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),

    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),

    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel),
    (PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex),
    (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex),

    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
    (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel),
    (PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex),
    (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 1.0
      ..color = Colors.white;

    for (final (a, b) in _connections) {
      final la = pose.landmarks[a];
      final lb = pose.landmarks[b];
      if (la == null || lb == null) continue;

      final p1 = _toCanvas(Offset(la.x, la.y), size);
      final p2 = _toCanvas(Offset(lb.x, lb.y), size);

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = _segmentColor(a, b);

      canvas.drawLine(p1, p2, linePaint);
    }

    for (final lm in pose.landmarks.values) {
      final p = _toCanvas(Offset(lm.x, lm.y), size);
      canvas.drawCircle(p, 3.5, pointPaint);
    }
  }

  Color _segmentColor(PoseLandmarkType a, PoseLandmarkType b) {
    final scores = lastJointScores;
    if (scores == null) return Colors.white.withValues(alpha: .9);

    final joint = _jointForSegment(a, b);
    if (joint == null) return Colors.white.withValues(alpha: 0.7);

    final s = (scores[joint] ?? double.nan);
    if (s.isNaN) return Colors.white.withValues(alpha:0.7);

    if (s >= 80) return Colors.greenAccent.withValues(alpha: 0.9);
    if (s >= 55) return Colors.amberAccent.withValues(alpha: 0.9);
    return Colors.redAccent.withValues(alpha: 0.9);
  }

  JointAngleKind? _jointForSegment(PoseLandmarkType a, PoseLandmarkType b) {
    if (_isEither(a, b, PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.leftWrist)) {
      return JointAngleKind.leftElbow;
    }
    if (_isEither(a, b, PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightShoulder, PoseLandmarkType.rightWrist)) {
      return JointAngleKind.rightElbow;
    }

    if (_isEither(a, b, PoseLandmarkType.leftKnee,
        PoseLandmarkType.leftHip, PoseLandmarkType.leftAnkle)) {
      return JointAngleKind.leftKnee;
    }
    if (_isEither(a, b, PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightHip, PoseLandmarkType.rightAnkle)) {
      return JointAngleKind.rightKnee;
    }

    if ((a == PoseLandmarkType.leftShoulder && b == PoseLandmarkType.leftHip) ||
        (b == PoseLandmarkType.leftShoulder && a == PoseLandmarkType.leftHip) ||
        (a == PoseLandmarkType.leftHip && b == PoseLandmarkType.leftKnee) ||
        (b == PoseLandmarkType.leftHip && a == PoseLandmarkType.leftKnee)) {
      return JointAngleKind.leftHip;
    }
    if ((a == PoseLandmarkType.rightShoulder && b == PoseLandmarkType.rightHip) ||
        (b == PoseLandmarkType.rightShoulder && a == PoseLandmarkType.rightHip) ||
        (a == PoseLandmarkType.rightHip && b == PoseLandmarkType.rightKnee) ||
        (b == PoseLandmarkType.rightHip && a == PoseLandmarkType.rightKnee)) {
      return JointAngleKind.rightHip;
    }

    return null;
  }

  bool _isEither(
    PoseLandmarkType a,
    PoseLandmarkType b,
    PoseLandmarkType joint,
    PoseLandmarkType end1,
    PoseLandmarkType end2,
  ) {
    final set = {a, b};
    return set.contains(joint) && (set.contains(end1) || set.contains(end2));
  }

  Offset _toCanvas(Offset p, Size canvasSize) {
    double x = p.dx;
    double y = p.dy;

    double cx;
    double cy;

    switch (rotation) {
      case InputImageRotation.rotation90deg:
        cx = x * canvasSize.width / imageSize.height;
        cy = y * canvasSize.height / imageSize.width;
        break;
      case InputImageRotation.rotation270deg:
        cx = canvasSize.width - (x * canvasSize.width / imageSize.height);
        cy = y * canvasSize.height / imageSize.width;
        break;
      case InputImageRotation.rotation180deg:
        cx = canvasSize.width - (x * canvasSize.width / imageSize.width);
        cy = canvasSize.height - (y * canvasSize.height / imageSize.height);
        break;
      case InputImageRotation.rotation0deg:
        cx = x * canvasSize.width / imageSize.width;
        cy = y * canvasSize.height / imageSize.height;
        break;
    }

    if (lensDirection == CameraLensDirection.front) {
      cx = canvasSize.width - cx;
    }

    return Offset(cx, cy);
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.lensDirection != lensDirection ||
        oldDelegate.lastJointScores != lastJointScores;
  }
}
