import 'dart:collection';

import 'pose_comparison.dart';
import 'rep_templates.dart';

class PoseAngleSample {
  final int tMs;
  final Map<JointAngleKind, double> angles;
  PoseAngleSample({required this.tMs, required this.angles});
}

class CapturedRep {
  final String exerciseId;
  final int startMs;
  final int endMs;
  final List<PoseAngleSample> samples;

  CapturedRep({
    required this.exerciseId,
    required this.startMs,
    required this.endMs,
    required this.samples,
  });

  int get durationMs => endMs - startMs;
}

enum _RepPhase { idle, movingToOppositeExtreme, returning }

class RepAnalyser {
  final ExerciseDefinition def;

  final Queue<PoseAngleSample> _buffer = Queue();
  final int _bufferWindowMs;

  _RepPhase _phase = _RepPhase.idle;
  bool _armed = false;
  int? _repStartMs;
  bool _hitOppositeExtreme = false;

  RepAnalyser(this.def, {int bufferWindowMs = 15000}) : _bufferWindowMs = bufferWindowMs;

  void reset() {
    _buffer.clear();
    _phase = _RepPhase.idle;
    _armed = false;
    _repStartMs = null;
    _hitOppositeExtreme = false;
  }

  CapturedRep? addSample(PoseAngleSample s) {
    _buffer.addLast(s);
    while (_buffer.isNotEmpty && (s.tMs - _buffer.first.tMs) > _bufferWindowMs) {
      _buffer.removeFirst();
    }

    final a = _primaryAngleWithFallback(s.angles);
    if (a == null) return null;

    return def.startAtHigh ? _updateStartAtHigh(a, s.tMs) : _updateStartAtLow(a, s.tMs);
  }

  double? _primaryAngleWithFallback(Map<JointAngleKind, double> angles) {
    final primary = angles[def.primaryJoint];
    if (primary != null) return primary;

    switch (def.primaryJoint) {
      case JointAngleKind.leftKnee:
        return angles[JointAngleKind.rightKnee];
      case JointAngleKind.rightKnee:
        return angles[JointAngleKind.leftKnee];
      case JointAngleKind.leftElbow:
        return angles[JointAngleKind.rightElbow];
      case JointAngleKind.rightElbow:
        return angles[JointAngleKind.leftElbow];
      case JointAngleKind.leftHip:
        return angles[JointAngleKind.rightHip];
      case JointAngleKind.rightHip:
        return angles[JointAngleKind.leftHip];
      case JointAngleKind.leftShoulder:
        return angles[JointAngleKind.rightShoulder];
      case JointAngleKind.rightShoulder:
        return angles[JointAngleKind.leftShoulder];
      case JointAngleKind.trunkLean:
        return angles[JointAngleKind.trunkLean];
    }
  }

  CapturedRep? _updateStartAtHigh(double a, int nowMs) {
    switch (_phase) {
      case _RepPhase.idle:
        if (!_armed && a >= def.highEnter) {
          _armed = true;
          return null;
        }
        if (_armed && a <= def.highExit) {
          _phase = _RepPhase.movingToOppositeExtreme;
          _repStartMs = nowMs;
          _hitOppositeExtreme = false;
          _armed = false;
        }
        break;

      case _RepPhase.movingToOppositeExtreme:
        if (a <= def.lowEnter) _hitOppositeExtreme = true;
        if (_hitOppositeExtreme && a >= def.lowExit) {
          _phase = _RepPhase.returning;
        }
        break;

      case _RepPhase.returning:
        final start = _repStartMs;
        if (start == null) {
          _phase = _RepPhase.idle;
          return null;
        }
        if (a >= def.highEnter) {
          final end = nowMs;
          _phase = _RepPhase.idle;
          _repStartMs = null;

          if ((end - start) < def.minRepMs) return null;

          final repSamples = _buffer.where((x) => x.tMs >= start && x.tMs <= end).toList();
          return CapturedRep(
            exerciseId: def.id,
            startMs: start,
            endMs: end,
            samples: repSamples,
          );
        }
        break;
    }
    return null;
  }

  CapturedRep? _updateStartAtLow(double a, int nowMs) {
    switch (_phase) {
      case _RepPhase.idle:
        if (!_armed && a <= def.lowEnter) {
          _armed = true;
          return null;
        }
        if (_armed && a >= def.lowExit) {
          _phase = _RepPhase.movingToOppositeExtreme;
          _repStartMs = nowMs;
          _hitOppositeExtreme = false;
          _armed = false;
        }
        break;

      case _RepPhase.movingToOppositeExtreme:
        if (a >= def.highEnter) _hitOppositeExtreme = true;
        if (_hitOppositeExtreme && a <= def.highExit) {
          _phase = _RepPhase.returning;
        }
        break;

      case _RepPhase.returning:
        final start = _repStartMs;
        if (start == null) {
          _phase = _RepPhase.idle;
          return null;
        }
        if (a <= def.lowEnter) {
          final end = nowMs;
          _phase = _RepPhase.idle;
          _repStartMs = null;

          if ((end - start) < def.minRepMs) return null;

          final repSamples = _buffer.where((x) => x.tMs >= start && x.tMs <= end).toList();
          return CapturedRep(
            exerciseId: def.id,
            startMs: start,
            endMs: end,
            samples: repSamples,
          );
        }
        break;
    }
    return null;
  }
}
