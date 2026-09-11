import 'package:camera/camera.dart';

/// Practice recordings stay small enough for web review and cheap Storage.
/// Prefer [medium]; init falls back to [low] when mobile rejects constraints.
const ResolutionPreset kPracticeCameraPreset = ResolutionPreset.medium;

/// Fallback when [kPracticeCameraPreset] is overconstrained on a device.
const ResolutionPreset kPracticeCameraFallbackPreset = ResolutionPreset.low;

/// Hard stop for camera / virtual practice recordings.
const int kMaxPracticeRecordingSeconds = 60;

const int kMaxStorageUploadBytes = 50 * 1024 * 1024;

/// Community / library list page size (Firestore `.limit`).
const int kFeedPageSize = 12;
