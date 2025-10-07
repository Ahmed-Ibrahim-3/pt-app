// lib/features/pose/pose_camera_page.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseCameraPage extends StatefulWidget {
  const PoseCameraPage({super.key});

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  late final PoseDetector _poseDetector;

  bool _isBusy = false;
  List<Pose> _poses = [];
  Size? _imageSize; 
  InputImageRotation? _lastRotation;

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
      if (!mounted) return;
      setState(() {
        _poses = poses;
      });
    } catch (_) {
    } finally {
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
    });
    await _startCamera();
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
                    CameraPreview(controller),
                    if (_imageSize != null && _poses.isNotEmpty)
                      CustomPaint(
                        painter: _PosePainter(
                          poses: _poses,
                          imageSize: _imageSize!,
                          rotation: _lastRotation,
                          lensDirection: _cameras[_cameraIndex].lensDirection,
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

    final jointPaint = Paint()..style = PaintingStyle.fill..strokeWidth = 2.0;
    final bonePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.0;

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
