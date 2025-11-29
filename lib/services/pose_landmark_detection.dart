// lib/services/pose_landmark_detection.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_comparison.dart';

class PoseCameraPage extends StatefulWidget {
  const PoseCameraPage({super.key});

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage> with WidgetsBindingObserver {

  bool _screenSpaceLabels = true;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  late final PoseDetector _poseDetector;

  bool _isBusy = false;
  List<Pose> _poses = [];
  Size? _imageSize;
  InputImageRotation? _lastRotation;

  Map<String, int> _angleDisplay = const {};

  PoseLandmarkType _swapLR(PoseLandmarkType t) {
    switch (t) {
      case PoseLandmarkType.leftShoulder: return PoseLandmarkType.rightShoulder;
      case PoseLandmarkType.rightShoulder: return PoseLandmarkType.leftShoulder;
      case PoseLandmarkType.leftElbow: return PoseLandmarkType.rightElbow;
      case PoseLandmarkType.rightElbow: return PoseLandmarkType.leftElbow;
      case PoseLandmarkType.leftWrist: return PoseLandmarkType.rightWrist;
      case PoseLandmarkType.rightWrist: return PoseLandmarkType.leftWrist;
      case PoseLandmarkType.leftHip: return PoseLandmarkType.rightHip;
      case PoseLandmarkType.rightHip: return PoseLandmarkType.leftHip;
      case PoseLandmarkType.leftKnee: return PoseLandmarkType.rightKnee;
      case PoseLandmarkType.rightKnee: return PoseLandmarkType.leftKnee;
      case PoseLandmarkType.leftAnkle: return PoseLandmarkType.rightAnkle;
      case PoseLandmarkType.rightAnkle: return PoseLandmarkType.leftAnkle;
      default: return t; 
    }
  }

    PoseLandmark? _lm(Map<PoseLandmarkType, PoseLandmark> lms, PoseLandmarkType t) {
    final isFront = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    final useScreenSpace = _screenSpaceLabels && isFront;
    return lms[useScreenSpace ? _swapLR(t) : t];
  }

  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
    _init();
  }

  Future<void> _init() async {
    _cameras = await availableCameras();
    final backIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _cameraIndex = backIndex >= 0 ? backIndex : 0;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    await controller.initialize();
    _imageSize = Size(controller.value.previewSize!.height, controller.value.previewSize!.width);
    await controller.startImageStream(_processCameraImage);
    if (mounted) setState(() {});
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _controller == null) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }
      final poses = await _poseDetector.processImage(inputImage);

      Map<String, int> angles = {};
      if (poses.isNotEmpty) {
        angles = _computeAngles(poses.first);
      }

      if (!mounted) return;
      setState(() {
        _poses = poses;
        _angleDisplay = angles;
      });
    } catch (_) {} finally {
      _isBusy = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      final deviceRotation = _orientations[_controller!.value.deviceOrientation];
      if (deviceRotation == null) return null;

      var rotationCompensation = (camera.lensDirection == CameraLensDirection.front)
          ? (sensorOrientation + deviceRotation) % 360
          : (sensorOrientation - deviceRotation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;
    _lastRotation = rotation;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    _imageSize ??= Size(image.width.toDouble(), image.height.toDouble());

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.stopImageStream();
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  void _flipCamera() async {
    if (_cameras.length < 2) return;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() {
      _poses = [];
      _angleDisplay = const {};
    });
    await _startCamera();
  }

  Map<String, int> _computeAngles(Pose pose) {
    final lms = pose.landmarks;

    int? d(double? v) => (v == null || v.isNaN) ? null : v.round();

    double? ang(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
      if (a == null || b == null || c == null) return null;
      final abx = a.x - b.x, aby = a.y - b.y;
      final cbx = c.x - b.x, cby = c.y - b.y;
      final dot = (abx * cbx) + (aby * cby);
      final mab = math.sqrt(abx * abx + aby * aby);
      final mcb = math.sqrt(cbx * cbx + cby * cby);
      final denom = mab * mcb;
      if (denom < 1e-6) return null;
      final cosv = (dot / denom).clamp(-1.0, 1.0);
      return (math.acos(cosv) * 180.0 / math.pi);
    }

    final out = <String, int?>{
      'L Shoulder': d(ang(_lm(lms, PoseLandmarkType.leftElbow),
                          _lm(lms, PoseLandmarkType.leftShoulder),
                          _lm(lms, PoseLandmarkType.leftHip))),
      'R Shoulder': d(ang(_lm(lms, PoseLandmarkType.rightElbow),
                          _lm(lms, PoseLandmarkType.rightShoulder),
                          _lm(lms, PoseLandmarkType.rightHip))),
      'L Elbow'   : d(ang(_lm(lms, PoseLandmarkType.leftShoulder),
                          _lm(lms, PoseLandmarkType.leftElbow),
                          _lm(lms, PoseLandmarkType.leftWrist))),
      'R Elbow'   : d(ang(_lm(lms, PoseLandmarkType.rightShoulder),
                          _lm(lms, PoseLandmarkType.rightElbow),
                          _lm(lms, PoseLandmarkType.rightWrist))),
      'L Hip'     : d(ang(_lm(lms, PoseLandmarkType.leftShoulder),
                          _lm(lms, PoseLandmarkType.leftHip),
                          _lm(lms, PoseLandmarkType.leftKnee))),
      'R Hip'     : d(ang(_lm(lms, PoseLandmarkType.rightShoulder),
                          _lm(lms, PoseLandmarkType.rightHip),
                          _lm(lms, PoseLandmarkType.rightKnee))),
      'L Knee'    : d(ang(_lm(lms, PoseLandmarkType.leftHip),
                          _lm(lms, PoseLandmarkType.leftKnee),
                          _lm(lms, PoseLandmarkType.leftAnkle))),
      'R Knee'    : d(ang(_lm(lms, PoseLandmarkType.rightHip),
                          _lm(lms, PoseLandmarkType.rightKnee),
                          _lm(lms, PoseLandmarkType.rightAnkle))),
    };

    return out.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value!))
        .fold<Map<String, int>>({}, (m, e) { m[e.key] = e.value; return m; });
  }


  Widget _maybeFlip(Widget child) {
    final isFrontIOS = Platform.isIOS &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    if (!isFrontIOS) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
      child: child,
    );
  }
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pose Overlay'),
        actions: [
          IconButton(
            onPressed: _flipCamera,
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _maybeFlip(CameraPreview(controller)),
                    if (_imageSize != null && _poses.isNotEmpty)
                      CustomPaint(
                        painter: _PosePainter(
                          poses: _poses,
                          imageSize: _imageSize!,
                          rotation: _lastRotation,
                          lensDirection: _cameras[_cameraIndex].lensDirection,
                        ),
                      ),

                    if (_angleDisplay.isNotEmpty)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DefaultTextStyle(
                            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _angleDisplay.entries
                                  .map((e) => Text('${e.key}: ${e.value}°'))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _PosePainter extends CustomPainter {
  _PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation? rotation;
  final CameraLensDirection lensDirection;

  static const _faceTypes = <PoseLandmarkType>{
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEyeInner,
    PoseLandmarkType.leftEye,
    PoseLandmarkType.leftEyeOuter,
    PoseLandmarkType.rightEyeInner,
    PoseLandmarkType.rightEye,
    PoseLandmarkType.rightEyeOuter,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftMouth,
    PoseLandmarkType.rightMouth,
  };

  static const _edges = <List<PoseLandmarkType>>[
    // torso
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    // arms
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    // legs
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final jointPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0;
    final bonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final pose in poses) {
      for (final edge in _edges) {
        final a = pose.landmarks[edge.first];
        final b = pose.landmarks[edge.last];
        if (a == null || b == null) continue;

        final p1 = _toCanvas(a, scaleX, scaleY, size);
        final p2 = _toCanvas(b, scaleX, scaleY, size);
        canvas.drawLine(p1, p2, bonePaint);
      }

      for (final l in pose.landmarks.values) {
        if (_faceTypes.contains(l.type)) continue;
        final p = _toCanvas(l, scaleX, scaleY, size);
        canvas.drawCircle(p, 4.0, jointPaint);
      }
    }
  }

  Offset _toCanvas(
    PoseLandmark l,
    double scaleX,
    double scaleY,
    Size canvasSize,
  ) {
    var x = l.x * scaleX;
    final y = l.y * scaleY;
    final isFront = lensDirection == CameraLensDirection.front;
    if (isFront) {
      x = canvasSize.width - x; 
    }
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) =>
      oldDelegate.poses != poses ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.lensDirection != lensDirection;
}
