import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

Offset translatePosePoint(
  Offset p,
  Size canvasSize,
  Size absoluteImageSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection,
) {
  final x = p.dx;
  final y = p.dy;

  late double cx;
  switch (rotation) {
    case InputImageRotation.rotation90deg:
      cx = x *
          canvasSize.width /
          (Platform.isIOS ? absoluteImageSize.width : absoluteImageSize.height);
      break;
    case InputImageRotation.rotation270deg:
      cx = canvasSize.width -
          x *
              canvasSize.width /
              (Platform.isIOS
                  ? absoluteImageSize.width
                  : absoluteImageSize.height);
      break;
    case InputImageRotation.rotation180deg:
      cx = canvasSize.width - (x * canvasSize.width / absoluteImageSize.width);
      break;
    case InputImageRotation.rotation0deg:
      cx = x * canvasSize.width / absoluteImageSize.width;
      break;
  }

  late double cy;
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      cy = y *
          canvasSize.height /
          (Platform.isIOS ? absoluteImageSize.height : absoluteImageSize.width);
      break;
    case InputImageRotation.rotation180deg:
      cy = canvasSize.height - (y * canvasSize.height / absoluteImageSize.height);
      break;
    case InputImageRotation.rotation0deg:
      cy = y * canvasSize.height / absoluteImageSize.height;
      break;
  }

  if (lensDirection == CameraLensDirection.front) {
    cx = canvasSize.width - cx;
  }

  return Offset(cx, cy);
}