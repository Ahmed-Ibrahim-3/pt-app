import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '/pose/pose_comparison.dart';
import '/pose/rep_analyser.dart';
import '/pose/rep_scoring.dart';
import '/pose/rep_templates.dart';
import '/pose/rep_feedback.dart';

class ExerciseScoringCameraPage extends StatefulWidget {
  const ExerciseScoringCameraPage({super.key});

  @override
  State<ExerciseScoringCameraPage> createState() =>
      _ExerciseScoringCameraPageState();
}

class _ExerciseScoringCameraPageState extends State<ExerciseScoringCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  List<RepFeedback> _feedbackHistory = [];
  RepFeedback? _lastFeedback;

  late final PoseDetector _poseDetector;

  bool _isBusy = false;
  Pose? _pose;

  Size? _imageSize;
  InputImageRotation? _lastRotation;

  bool _recording = false;

  late ExerciseDefinition _exercise;
  late RepAnalyser _repAnalyser;

  int _repCount = 0;
  RepScore? _lastScore;
  Map<JointAngleKind, double>? _latestAngles;

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

    _exercise = BuiltInExerciseCatalog.all().first;
    _repAnalyser = RepAnalyser(_exercise);

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );

    _init();
  }

  Future<void> _init() async {
    _cameras = await availableCameras();
    final backIndex =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _cameraIndex = backIndex >= 0 ? backIndex : 0;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    _controller = controller;
    await controller.initialize();
    await controller.startImageStream(_processCameraImage);

    if (mounted) setState(() {});
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

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;

    await _controller?.stopImageStream();
    await _controller?.dispose();

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    setState(() {
      _pose = null;
      _imageSize = null;
      _latestAngles = null;
      _lastScore = null;
      _repCount = 0;
      _recording = false;
    });

    await _startCamera();
  }

  void _selectExercise(String id) {
    final def = BuiltInExerciseCatalog.byId(id);
    setState(() {
      _exercise = def;
      _repAnalyser = RepAnalyser(_exercise);
      _repCount = 0;
      _lastScore = null;
      _recording = false;
    });
  }

  void _toggleRecording() {
  final wasRecording = _recording;

  setState(() {
    _recording = !_recording;

    if (!wasRecording) {
      _repAnalyser.reset();
      _repCount = 0;
      _lastScore = null;
      _lastFeedback = null;
      _feedbackHistory = [];
    }
  });

  if (wasRecording) {
    _showSetSummary();
  }
}

Future<void> _showSetSummary() async {
  if (!mounted) return;
  if (_feedbackHistory.isEmpty) return;

  final items = RepFeedbackGenerator.summariseSet(
    _feedbackHistory,
    _exercise,
    maxItems: 5,
  );

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set feedback',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...items.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $m'),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _controller == null) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;

      if (poses.isEmpty) {
        setState(() {
          _pose = null;
          _latestAngles = null;
        });
        return;
      }

      final pose = poses.first;
      final angles = PoseAngles.fromPose(pose).values;
      final now = DateTime.now().millisecondsSinceEpoch;

      CapturedRep? rep;
      if (_recording) {
        rep = _repAnalyser.addAngles(now, angles);
      }

      if (rep != null) {
        final score = RepScorer.scoreRep(rep, _exercise);
        final feedback = RepFeedbackGenerator.generate(rep, _exercise);
        setState(() {
          _pose = pose;
          _latestAngles = angles;
          _repCount += 1;
          _lastScore = score;
          _lastFeedback = feedback;
          _feedbackHistory.add(feedback);
        });
      }
      else {
        setState(() {
          _pose = pose;
          _latestAngles = angles;
        });
      }
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

      final rotationCompensation =
          (camera.lensDirection == CameraLensDirection.front)
              ? (sensorOrientation + deviceRotation) % 360
              : (sensorOrientation - deviceRotation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;
    _lastRotation = rotation;

    final isQuarterTurn = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    _imageSize = isQuarterTurn
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isIOS) {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format != InputImageFormat.bgra8888) return null;
      if (image.planes.isEmpty) return null;
      final plane = image.planes.first;

      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android
    if (image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (image.planes.length == 3) {
      final nv21 = _yuv420ToNv21(image);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;
    final uRowStride = uPlane.bytesPerRow;
    final vRowStride = vPlane.bytesPerRow;

    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    final outSize = width * height + (width * height ~/ 2);
    final out = Uint8List(outSize);

    var outIndex = 0;
    for (var row = 0; row < height; row++) {
      final start = row * yRowStride;
      out.setRange(outIndex, outIndex + width, yBytes, start);
      outIndex += width;
    }

    var uvOutIndex = width * height;
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;

    for (var row = 0; row < uvHeight; row++) {
      for (var col = 0; col < uvWidth; col++) {
        final uIndex = row * uRowStride + col * uPixelStride;
        final vIndex = row * vRowStride + col * vPixelStride;
        out[uvOutIndex++] = vBytes[vIndex];
        out[uvOutIndex++] = uBytes[uIndex];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final lensDirection = _cameras.isNotEmpty
        ? _cameras[_cameraIndex].lensDirection
        : CameraLensDirection.back;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Scoring'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _exercise.id,
              onChanged: (v) => v == null ? null : _selectExercise(v),
              items: BuiltInExerciseCatalog.all()
                  .map((e) => DropdownMenuItem(value: e.id, child: Text(BuiltInExerciseCatalog.displayName(e.id))))
                  .toList(),
            ),
          ),
          IconButton(
            onPressed: _flipCamera,
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: controller == null || !controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                _FullScreenCameraWithOverlay(
                  controller: controller,
                  pose: _pose,
                  imageSize: _imageSize,
                  lensDirection: lensDirection,
                  perJointScore: _lastScore?.perJoint,
                ),

                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: _Hud(
                    recording: _recording,
                    exerciseId: _exercise.id,
                    repCount: _repCount,
                    score: _lastScore,
                    onToggleRecording: _toggleRecording,
                    feedback: _lastFeedback,
                  ),
                ),

                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _AngleDebugBar(
                    exercise: _exercise,
                    latestAngles: _latestAngles,
                  ),
                ),
              ],
            ),
    );
  }
}

class _FullScreenCameraWithOverlay extends StatelessWidget {
  final CameraController controller;
  final Pose? pose;
  final Size? imageSize;
  final CameraLensDirection lensDirection;
  final Map<JointAngleKind, double>? perJointScore;

  const _FullScreenCameraWithOverlay({
    required this.controller,
    required this.pose,
    required this.imageSize,
    required this.lensDirection,
    required this.perJointScore,
  });

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final childW = isPortrait ? previewSize.height : previewSize.width;
    final childH = isPortrait ? previewSize.width : previewSize.height;


     return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: childW,
            height: childH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                if (pose != null && imageSize != null)
                  CustomPaint(
                    painter: _PosePainter(
                      pose: pose!,
                      imageSize: imageSize!,
                      lensDirection: lensDirection,
                      perJointScore: perJointScore,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final bool recording;
  final String exerciseId;
  final int repCount;
  final RepScore? score;
  final VoidCallback onToggleRecording;
  final RepFeedback? feedback;

  const _Hud({
    required this.recording,
    required this.exerciseId,
    required this.repCount,
    required this.score,
    required this.onToggleRecording,
    required this.feedback,
    });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$exerciseId  •  reps: $repCount',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: onToggleRecording,
                    child: Text(recording ? 'Stop' : 'Start'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (score == null)
                const Text('No rep scored yet.')
              else ...[
                Text(
                  'Overall: ${score!.overall.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: score!.perJoint.entries.map((e) {
                    return Text('${e.key.name}: ${e.value.toStringAsFixed(0)}%');
                  }).toList(),
                ),
                if (feedback != null && feedback!.cues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Next rep focus:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...feedback!.cues.map((c) => Text('• ${c.message}')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AngleDebugBar extends StatelessWidget {
  final ExerciseDefinition exercise;
  final Map<JointAngleKind, double>? latestAngles;

  const _AngleDebugBar({
    required this.exercise,
    required this.latestAngles,
  });

  @override
  Widget build(BuildContext context) {
    final a = latestAngles;
    if (a == null) return const SizedBox.shrink();

    final joints = exercise.template.joints.keys.toList();
    final show = joints.take(6).toList();

    String line(JointAngleKind j) {
      final spec = exercise.template.joints[j]!;
      final minV = math.min(spec.start, spec.opposite);
      final maxV = math.max(spec.start, spec.opposite);
      final cur = a[j];

      return '${j.name}: ${cur?.toStringAsFixed(0) ?? "—"}°   '
          '(tpl ${minV.toStringAsFixed(0)}–${maxV.toStringAsFixed(0)}°, '
          'tol ±${spec.toleranceDeg.toStringAsFixed(0)}°)';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Live angles vs template range:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...show.map((j) => Text(line(j))),
            ],
          ),
        ),
      ),
    );
  }
}



class _PosePainter extends CustomPainter {
  _PosePainter({
    required this.pose,
    required this.imageSize,
    required this.lensDirection,
    required this.perJointScore,
  });

  final Pose pose;
  final Size imageSize;
  final CameraLensDirection lensDirection;
  final Map<JointAngleKind, double>? perJointScore;

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

    // feet
    [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
    [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
    [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
    [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final lm = pose.landmarks;
    if (lm.isEmpty) return;

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..color = Colors.white;

    // Map pose (image coords) -> canvas coords
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final edge in _edges) {
      final a = lm[edge.first];
      final b = lm[edge.last];
      if (a == null || b == null) continue;

      final p1 = _toCanvas(a.x, a.y, scaleX, scaleY, size);
      final p2 = _toCanvas(b.x, b.y, scaleX, scaleY, size);

      final joint = _jointForEdge(edge.first, edge.last);
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = _colorForJoint(joint);

      canvas.drawLine(p1, p2, linePaint);
    }

    for (final l in lm.values) {
      final p = _toCanvas(l.x, l.y, scaleX, scaleY, size);
      canvas.drawCircle(p, 3.5, pointPaint);
    }
  }

  Offset _toCanvas(
    double x,
    double y,
    double scaleX,
    double scaleY,
    Size canvasSize,
  ) {
    var cx = x * scaleX;
    final cy = y * scaleY;

    if (lensDirection == CameraLensDirection.front) {
      cx = canvasSize.width - cx;
    }
    return Offset(cx, cy);
  }

  Color _colorForJoint(JointAngleKind? joint) {
    final scores = perJointScore;
    if (scores == null || joint == null) return Colors.white.withValues(alpha: 0.85);

    final s = scores[joint];
    if (s == null) return Colors.white.withValues(alpha: 0.75);

    if (s >= 80) return Colors.greenAccent.withValues(alpha: 0.95);
    if (s >= 55) return Colors.amberAccent.withValues(alpha: 0.95);
    return Colors.redAccent.withValues(alpha: 0.95);
  }

  JointAngleKind? _jointForEdge(PoseLandmarkType a, PoseLandmarkType b) {
    bool isEdge(PoseLandmarkType x, PoseLandmarkType y) =>
        (a == x && b == y) || (a == y && b == x);

    // elbows
    if (isEdge(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow) ||
        isEdge(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist)) {
      return JointAngleKind.leftElbow;
    }
    if (isEdge(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow) ||
        isEdge(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist)) {
      return JointAngleKind.rightElbow;
    }

    // knees
    if (isEdge(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee) ||
        isEdge(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle)) {
      return JointAngleKind.leftKnee;
    }
    if (isEdge(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee) ||
        isEdge(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle)) {
      return JointAngleKind.rightKnee;
    }

    // hips
    if (isEdge(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip) ||
        isEdge(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee)) {
      return JointAngleKind.leftHip;
    }
    if (isEdge(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip) ||
        isEdge(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee)) {
      return JointAngleKind.rightHip;
    }

    return null;
  }

  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.lensDirection != lensDirection ||
        oldDelegate.perJointScore != perJointScore;
  }
}
