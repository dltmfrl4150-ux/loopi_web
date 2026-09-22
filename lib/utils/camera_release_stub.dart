import 'package:camera/camera.dart';

/// Stops recording (if any) and disposes the camera controller.
Future<void> releaseCameraController(CameraController? controller) async {
  if (controller == null) return;
  try {
    if (controller.value.isInitialized && controller.value.isRecordingVideo) {
      await controller.stopVideoRecording();
    }
  } catch (_) {}
  try {
    await controller.dispose();
  } catch (_) {}
}

/// No-op on non-web platforms.
void stopOrphanedCameraMediaTracks() {}

/// No-op on non-web platforms.
void forceStopActiveCaptureTracks() {}