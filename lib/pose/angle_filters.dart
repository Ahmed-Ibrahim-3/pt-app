import 'dart:math' as math;

import 'pose_comparison.dart';

class _LowPass {
  double? _y;
  double? _a;

  double filter(double x, double a) {
    _a = a;
    if (_y == null) {
      _y = x;
      return x;
    }
    _y = a * x + (1 - a) * _y!;
    return _y!;
  }

  bool get hasValue => _y != null;
  double? get last => _y;
}

class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  final _LowPass _x = _LowPass();
  final _LowPass _dx = _LowPass();

  double? _lastTimeSec;

  OneEuroFilter({
    this.minCutoff = 1.2,
    this.beta = 0.02,
    this.dCutoff = 1.0,
  });

  double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double tSec, double x) {
    if (_lastTimeSec == null) {
      _lastTimeSec = tSec;
      return _x.filter(x, 1.0);
    }
    final dt = (tSec - _lastTimeSec!).clamp(1e-3, 0.25);
    _lastTimeSec = tSec;

    final prev = _x.last ?? x;
    final dx = (x - prev) / dt;
    final aD = _alpha(dCutoff, dt);
    final edx = _dx.filter(dx, aD);

    final cutoff = minCutoff + beta * edx.abs();
    final a = _alpha(cutoff, dt);
    return _x.filter(x, a);
  }
}

class AngleFilterBank {
  final Map<JointAngleKind, OneEuroFilter> _filters = {};

  AngleFilterBank({
    double minCutoff = 1.2,
    double beta = 0.02,
    double dCutoff = 1.0,
  }) {
    for (final k in JointAngleKind.values) {
      _filters[k] = OneEuroFilter(
        minCutoff: minCutoff,
        beta: beta,
        dCutoff: dCutoff,
      );
    }
  }

  Map<JointAngleKind, double> filterAngles(int tMs, Map<JointAngleKind, double> raw) {
    final tSec = tMs / 1000.0;
    final out = <JointAngleKind, double>{};
    for (final e in raw.entries) {
      final f = _filters[e.key];
      if (f == null) continue;
      out[e.key] = f.filter(tSec, e.value);
    }
    return out;
  }
}
