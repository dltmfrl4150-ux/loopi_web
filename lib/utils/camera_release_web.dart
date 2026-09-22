import 'dart:async';
import 'dart:html' as html;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Stops recording (if any), disposes the controller, then force-stops any
/// leftover getUserMedia tracks so the browser camera indicator turns off.
Future<void> releaseCameraController(CameraController? controller) async {
  if (controller == null) return;
  try {
    if (controller.value.isInitialized && controller.value.isRecordingVideo) {
      await controller.stopVideoRecording().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {
          debugPrint('[LOOPI] releaseCameraController stopVideoRecording timed out');
          throw TimeoutException('stopVideoRecording');
        },
      );
    }
  } catch (_) {}
  try {
    await controller.dispose();
  } catch (_) {}
  stopOrphanedCameraMediaTracks();
}

/// Explicitly stops [MediaStreamTrack]s still attached to preview <video>
/// elements after Flutter camera dispose (web indicator can otherwise linger).
///
/// Also call this *before* [CameraController.stopVideoRecording] on web when
/// recording may lack a video track — stopping tracks forces MediaRecorder to
/// finalize instead of hanging for tens of seconds waiting for frames.
void stopOrphanedCameraMediaTracks() {
  try {
    final nodes = html.document.querySelectorAll('video');
    for (final node in nodes) {
      if (node is! html.VideoElement) continue;
      final stream = node.srcObject;
      if (stream == null) continue;
      // Only stop live capture streams (camera/mic), not blob:/http playback.
      var stoppedAny = false;
      for (final track in stream.getTracks()) {
        final kind = track.kind;
        final live = track.readyState == 'live';
        if (live && (kind == 'video' || kind == 'audio')) {
          track.stop();
          stoppedAny = true;
        }
      }
      if (stoppedAny) {
        node.srcObject = null;
        debugPrint('[LOOPI] stopped orphaned MediaStreamTrack(s) on <video>');
      }
    }
  } catch (error) {
    debugPrint('[LOOPI] stopOrphanedCameraMediaTracks ignored: $error');
  }
}

/// Stops live getUserMedia tracks immediately so a hung MediaRecorder can finish.
void forceStopActiveCaptureTracks() => stopOrphanedCameraMediaTracks();