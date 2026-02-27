import 'dart:collection';

import 'angle_filters.dart';
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

  final AngleFilterBank _filterBank;

  /// Extra smoothing on the primary rep-counting signal (after per-joint
  /// filtering).
  ///
  /// When a joint gets occluded, the analyser may fall back to the opposite
  /// side (e.g. left elbow -> right elbow). Those side-to-side swaps can create
  /// sudden jumps that look like threshold crossings, which can lead to “half
  /// rep” counts. This filter stabilises the combined signal.
  late OneEuroFilter _primaryFilter;

  _RepPhase _phase = _RepPhase.idle;
  bool _armed = false;
  int? _repStartMs;
  bool _hitOppositeExtreme = false;

  // Debounce for noisy threshold crossings at the extremes.
  static const int _extremeHoldMs = 140;
  static const double _resetHysteresisDeg = 3.0;
  int? _lowHoldSinceMs;
  int? _highHoldSinceMs;

  RepAnalyser(
    this.def, {
    int bufferWindowMs = 15000,
    AngleFilterBank? filterBank,
  })  : _bufferWindowMs = bufferWindowMs,
        _filterBank = filterBank ?? AngleFilterBank() {
    _primaryFilter = OneEuroFilter();
  }

  void reset() {
    _buffer.clear();
    _phase = _RepPhase.idle;
    _armed = false;
    _repStartMs = null;
    _hitOppositeExtreme = false;
    _lowHoldSinceMs = null;
    _highHoldSinceMs = null;
    _primaryFilter = OneEuroFilter();
  }

  CapturedRep? addAngles(int tMs, Map<JointAngleKind, double> rawAngles) {
    final filtered = _filterBank.filterAngles(tMs, rawAngles);

    final s = PoseAngleSample(tMs: tMs, angles: filtered);
    _buffer.addLast(s);

    while (_buffer.isNotEmpty && (tMs - _buffer.first.tMs) > _bufferWindowMs) {
      _buffer.removeFirst();
    }

    final aRaw = _primaryAngleWithFallback(filtered);
    if (aRaw == null) return null;

    // Smooth the combined primary signal (helps with left/right swapping).
    final a = _primaryFilter.filter(tMs / 1000.0, aRaw);

    return def.startAtHigh ? _updateStartAtHigh(a, tMs) : _updateStartAtLow(a, tMs);
  }

  double? _primaryAngleWithFallback(Map<JointAngleKind, double> angles) {
    // Prefer a stable signal:
    // - If we have both left/right for the same joint, use the mean.
    // - Otherwise use whichever side we have.
    JointAngleKind? other;
    switch (def.primaryJoint) {
      case JointAngleKind.leftKnee:
        other = JointAngleKind.rightKnee;
        break;
      case JointAngleKind.rightKnee:
        other = JointAngleKind.leftKnee;
        break;
      case JointAngleKind.leftElbow:
        other = JointAngleKind.rightElbow;
        break;
      case JointAngleKind.rightElbow:
        other = JointAngleKind.leftElbow;
        break;
      case JointAngleKind.leftHip:
        other = JointAngleKind.rightHip;
        break;
      case JointAngleKind.rightHip:
        other = JointAngleKind.leftHip;
        break;
      case JointAngleKind.leftShoulder:
        other = JointAngleKind.rightShoulder;
        break;
      case JointAngleKind.rightShoulder:
        other = JointAngleKind.leftShoulder;
        break;
      case JointAngleKind.trunkLean:
        other = null;
        break;
    }

    final a = angles[def.primaryJoint];
    if (other == null) return a;
    final b = angles[other];
    if (a != null && b != null) return (a + b) / 2.0;
    return a ?? b;
  }

  bool _holdBelowLow(double a, int nowMs) {
    if (a <= def.lowEnter) {
      _lowHoldSinceMs ??= nowMs;
      return (nowMs - _lowHoldSinceMs!) >= _extremeHoldMs;
    }
    if (_lowHoldSinceMs != null && a > (def.lowEnter + _resetHysteresisDeg)) {
      _lowHoldSinceMs = null;
    }
    return false;
  }

  bool _holdAboveHigh(double a, int nowMs) {
    if (a >= def.highEnter) {
      _highHoldSinceMs ??= nowMs;
      return (nowMs - _highHoldSinceMs!) >= _extremeHoldMs;
    }
    if (_highHoldSinceMs != null && a < (def.highEnter - _resetHysteresisDeg)) {
      _highHoldSinceMs = null;
    }
    return false;
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
        if (!_hitOppositeExtreme && _holdBelowLow(a, nowMs)) {
          _hitOppositeExtreme = true;
        }
        if (_hitOppositeExtreme && a >= def.lowExit) {
          _phase = _RepPhase.returning;
          _highHoldSinceMs = null;
        }
        break;

      case _RepPhase.returning:
        final start = _repStartMs;
        if (start == null) {
          _phase = _RepPhase.idle;
          return null;
        }
        if (_holdAboveHigh(a, nowMs)) {
          final end = nowMs;
          _phase = _RepPhase.idle;
          _repStartMs = null;
          _lowHoldSinceMs = null;
          _highHoldSinceMs = null;

          if ((end - start) < def.minRepMs) return null;

          final repSamples =
              _buffer.where((x) => x.tMs >= start && x.tMs <= end).toList();
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
        if (!_hitOppositeExtreme && _holdAboveHigh(a, nowMs)) {
          _hitOppositeExtreme = true;
        }
        if (_hitOppositeExtreme && a <= def.highExit) {
          _phase = _RepPhase.returning;
          _lowHoldSinceMs = null;
        }
        break;

      case _RepPhase.returning:
        final start = _repStartMs;
        if (start == null) {
          _phase = _RepPhase.idle;
          return null;
        }
        if (_holdBelowLow(a, nowMs)) {
          final end = nowMs;
          _phase = _RepPhase.idle;
          _repStartMs = null;
          _lowHoldSinceMs = null;
          _highHoldSinceMs = null;

          if ((end - start) < def.minRepMs) return null;

          final repSamples =
              _buffer.where((x) => x.tMs >= start && x.tMs <= end).toList();
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