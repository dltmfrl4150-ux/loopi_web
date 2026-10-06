import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' hide PlayerState;
import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../state/shadowing_sequence_controller.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';
import '../utils/camera_release.dart';
import '../utils/cached_video.dart';
import '../services/storage_service.dart';
import '../utils/media_limits.dart';
import '../utils/youtube_player_factory.dart';
import '../widgets/highlight_interval.dart';
import '../widgets/shell_close_scope.dart';
import '../widgets/comparison_export.dart';
import '../widgets/storage_quota_nudge.dart';
import '../utils/storage_quota.dart';

/// True when [path] looks like an audio-only capture (wav/m4a/…).
bool _pathLooksLikeAudioRecording(String? path) {
  if (path == null || path.isEmpty) return false;
  final lower = path.toLowerCase();
  return lower.endsWith('.m4a') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.flac') ||
      lower.contains('loopi_practice_');
}

/// Empty / dummy web recordings often initialize with ~0 duration or no frames,
/// which makes [VideoPlayer] hit EOF immediately and "reset" to 0.1s.
/// Fatal recorded-player failure only. On Flutter Web, blob metadata / DOM mount
/// can lag after [initialize] — never treat missing size/duration/isInitialized
/// as failure (reading `.value` too early can even throw [StateError]).
bool _recordedVideoLooksUnusable(VideoPlayerController? controller) {
  if (controller == null) return true;
  return _recordedControllerHasFatalError(controller);
}

/// True only when [VideoPlayerValue.hasError] is explicitly set.
/// [StateError] / "Bad state" while probing → not fatal (render VideoPlayer).
bool _recordedControllerHasFatalError(VideoPlayerController controller) {
  try {
    return controller.value.hasError;
  } catch (error) {
    debugPrint('[LOOPI] recorded value probe ignored (not fatal): $error');
    return false;
  }
}

void _debugPrintSavedDuration(VideoPlayerController controller) {
  try {
    // ignore: avoid_print
    print('Saved video duration: ${controller.value.duration}');
  } catch (error) {
    debugPrint('[LOOPI] duration probe ignored: $error');
  }
}

/// Await [VideoPlayerController.initialize]. On web, do not re-probe
/// isInitialized / size / duration after success — the HTML5 video element
/// resolves metadata once mounted in the widget tree.
Future<void> awaitVideoPlayerReady(
  VideoPlayerController controller, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  var alreadyInit = false;
  try {
    alreadyInit = controller.value.isInitialized;
  } catch (_) {
    alreadyInit = false;
  }
  if (!alreadyInit) {
    await controller.initialize().timeout(timeout);
  }
}

SavedRoutine sanitizeRoutineForPractice(SavedRoutine routine) {
  final isYoutube = routine.sourceType == SourceType.youtube;
  final videoId = isYoutube
      ? (resolveYoutubeVideoId(videoId: routine.videoId, videoUrl: routine.videoUrl) ?? '')
      : '';
  // TRUST author timestamps completely — including identical overlapping windows
  // used for speed-ramp practice (A–E all 0–15s at different speeds).
  // Never invent, heal, or evenly split section ranges.
  final segments = routine.segments.map((segment) {
    final start = segment.startSec.isFinite && segment.startSec >= 0 ? segment.startSec : 0.0;
    final end = segment.endSec.isFinite && segment.endSec > start ? segment.endSec : start;
    return segment.copyWith(
      startSec: start.toDouble(),
      endSec: end.toDouble(),
      speed: (segment.speed <= 0 ? 1.0 : segment.speed).toDouble(),
      loopCount: segment.loopCount == 0 ? 1 : segment.loopCount,
      delaySec: segment.delaySec < 0 ? 0 : segment.delaySec,
    );
  }).toList();
  return SavedRoutine(
    id: routine.id,
    name: routine.name.trim().isEmpty ? 'Routine' : routine.name,
    videoUrl: isYoutube ? routine.videoUrl : '',
    videoId: videoId,
    segments: segments.isNotEmpty
        ? segments
        : [
            RoutineSegment(
              id: 'seg_fallback',
              startSec: 0,
              endSec: 1,
            ),
          ],
    createdAt: routine.createdAt,
    sourceType: routine.sourceType,
    localFilePath: routine.localFilePath,
    fileName: routine.fileName,
    localDataBytes: routine.localDataBytes,
    isFavorite: routine.isFavorite,
    authorId: routine.authorId,
    authorName: routine.authorName,
    category: routine.category,
    isMirrored: routine.isMirroredOn,
  );
}

double originalAspectRatioForRoutine(SavedRoutine routine) {
  final url = routine.videoUrl.toLowerCase();
  if (url.contains('/shorts/') || url.contains('shorts')) return 9 / 16;
  return 16 / 9;
}

/// Letterboxed frame at [aspectRatio] with [BoxFit.contain] (no FoV crop).
/// Black bars are preferred over cutting the subject. Used by practice
/// CameraPreview and comparison VideoPlayer so FoV matches.
/// App-wide practice/comparison UI frame — matches YouTube in landscape.
const double kPracticeUiAspectRatio = 16 / 9;
const double kPracticeUiPortraitAspectRatio = 9 / 16;

/// Outer UI box: landscape → 16:9, portrait → 9:16.
double uiFrameAspectRatioFor(Orientation orientation) {
  return orientation == Orientation.portrait
      ? kPracticeUiPortraitAspectRatio
      : kPracticeUiAspectRatio;
}

/// Aligns [controllerAspectRatio] with [orientation] so a landscape sensor
/// isn't squeezed into a portrait UI box (and vice versa). Never re-inits camera.
double nativePreviewAspectRatioFor({
  required double controllerAspectRatio,
  required Orientation orientation,
}) {
  var ratio = controllerAspectRatio > 0 && controllerAspectRatio.isFinite
      ? controllerAspectRatio
      : kPracticeUiAspectRatio;
  final devicePortrait = orientation == Orientation.portrait;
  final sensorPortrait = ratio < 1.0;
  if (devicePortrait != sensorPortrait) {
    ratio = 1.0 / ratio;
  }
  return ratio;
}

/// Outer UI aspect (16:9 / 9:16) + inner native FoV letterbox (no cover crop).
Widget buildOrientationAwareMediaFrame({
  required Orientation orientation,
  required double nativeAspectRatio,
  required Widget child,
}) {
  final uiRatio = uiFrameAspectRatioFor(orientation);
  final native = nativeAspectRatio > 0 && nativeAspectRatio.isFinite
      ? nativeAspectRatio
      : uiRatio;
  return AspectRatio(
    aspectRatio: uiRatio,
    child: ColoredBox(
      color: Colors.black,
      child: Center(
        // Nested AspectRatio + Center == BoxFit.contain letterboxing.
        child: AspectRatio(
          aspectRatio: native,
          child: child,
        ),
      ),
    ),
  );
}

/// App UI standard: outer 16:9 (matches YouTube). Inner box uses the media's
/// native hardware/file aspect ratio so the lens FoV is never cover-cropped.
Widget buildYoutubeStandardMediaFrame({
  required double nativeAspectRatio,
  required Widget child,
  Orientation orientation = Orientation.landscape,
}) {
  return buildOrientationAwareMediaFrame(
    orientation: orientation,
    nativeAspectRatio: nativeAspectRatio,
    child: child,
  );
}

/// @Deprecated — use [buildYoutubeStandardMediaFrame] (no forced cover crop).
Widget buildRatioCroppedMedia({
  required double aspectRatio,
  required double sourceWidth,
  required double sourceHeight,
  required Widget child,
}) {
  final native = (sourceWidth > 0 && sourceHeight > 0)
      ? sourceWidth / sourceHeight
      : aspectRatio;
  return buildYoutubeStandardMediaFrame(
    nativeAspectRatio: native,
    child: child,
  );
}

/// @Deprecated — use [buildYoutubeStandardMediaFrame].
Widget buildLetterboxedRatioMedia({
  required double aspectRatio,
  required double sourceWidth,
  required double sourceHeight,
  required Widget child,
}) {
  return buildRatioCroppedMedia(
    aspectRatio: aspectRatio,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    child: child,
  );
}

/// @Deprecated — use [buildYoutubeStandardMediaFrame].
Widget buildContainedMediaFrame({
  required BoxConstraints constraints,
  required double aspectRatio,
  required double sourceWidth,
  required double sourceHeight,
  required Widget child,
}) {
  return Center(
    child: buildYoutubeStandardMediaFrame(
      nativeAspectRatio: aspectRatio,
      child: child,
    ),
  );
}

/// @Deprecated — use [buildYoutubeStandardMediaFrame].
Widget buildCoverCroppedMediaFrame({
  required BoxConstraints constraints,
  required double aspectRatio,
  required double sourceWidth,
  required double sourceHeight,
  required Widget child,
}) {
  return Center(
    child: buildYoutubeStandardMediaFrame(
      nativeAspectRatio: aspectRatio,
      child: child,
    ),
  );
}

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({
    super.key,
    required this.library,
    this.selectedRoutine,
    this.selectedView,
    this.onOpenInShell,
    this.profilePhotoUrl,
  });

  final RoutineLibrary library;
  final SavedRoutine? selectedRoutine;
  final Widget? selectedView;
  final ValueChanged<Widget>? onOpenInShell;
  final String? profilePhotoUrl;

  void _open(BuildContext context, SavedRoutine routine) {
    final safe = sanitizeRoutineForPractice(routine);
    final Widget screen;
    switch (safe.sourceType) {
      case SourceType.localVideo:
        screen = VideoPracticeScreen(
          routine: safe,
          library: library,
          onOpenInShell: onOpenInShell,
          profilePhotoUrl: profilePhotoUrl,
        );
        break;
      case SourceType.audio:
        screen = AudioPracticeScreen(routine: safe, library: library);
        break;
      case SourceType.youtube:
        screen = VideoPracticeScreen(
          routine: safe,
          library: library,
          onOpenInShell: onOpenInShell,
          profilePhotoUrl: profilePhotoUrl,
        );
        break;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    if (selectedView != null) {
      return selectedView!;
    }
    if (selectedRoutine != null) {
      final safe = sanitizeRoutineForPractice(selectedRoutine!);
      return safe.sourceType == SourceType.audio
          ? AudioPracticeScreen(routine: safe, library: library)
          : VideoPracticeScreen(
              routine: safe,
              library: library,
              onOpenInShell: onOpenInShell,
              profilePhotoUrl: profilePhotoUrl,
            );
    }
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final routines = library.routines;
        if (routines.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('저장한 루틴을 선택해 연습을 시작하세요.'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text('연습 모드', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('연습할 저장 루틴을 선택하세요.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            for (final routine in routines)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(_iconFor(routine.sourceType), color: LoopiColors.purple),
                  title: Text(routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${routine.segments.length}개 구간 · ${_typeLabel(routine.sourceType)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, routine),
                ),
              ),
          ],
        );
      },
    );
  }

  static IconData _iconFor(SourceType type) {
    switch (type) {
      case SourceType.youtube:
        return Icons.play_circle_outline;
      case SourceType.localVideo:
        return Icons.videocam_outlined;
      case SourceType.audio:
        return Icons.graphic_eq;
    }
  }

  static String _typeLabel(SourceType type) {
    switch (type) {
      case SourceType.youtube:
        return 'YouTube';
      case SourceType.localVideo:
        return '비디오';
      case SourceType.audio:
        return '오디오';
    }
  }
}

class VideoPracticeScreen extends StatefulWidget {
  const VideoPracticeScreen({
    super.key,
    required this.routine,
    required this.library,
    this.onOpenInShell,
    this.profilePhotoUrl,
  });

  final SavedRoutine routine;
  final RoutineLibrary library;
  final ValueChanged<Widget>? onOpenInShell;
  final String? profilePhotoUrl;

  @override
  State<VideoPracticeScreen> createState() => _VideoPracticeScreenState();
}

class _VideoPracticeScreenState extends State<VideoPracticeScreen> {
  CameraController? _camera;
  VideoPlayerController? _original;
  YoutubePlayerController? _youtubeOriginal;
  VideoPlayerController? _recorded;
  bool _recording = false;
  bool _loading = true;
  String? _error;
  String? _cameraError;
  String? _originalError;
  Timer? _syncTimer;
  String? _originalObjectUrl;
  /// Fixed UI standard — matches YouTube 16:9. Native camera FoV letterboxes inside.
  double _previewAspectRatio = kPracticeUiAspectRatio;
  /// Keeps the web HtmlElementView / MediaStream attached across ratio setState.
  /// Must never be recreated (do not assign a new GlobalKey).
  final GlobalKey _cameraPreviewHostKey = GlobalKey(debugLabel: 'practiceCameraPreview');
  /// Unmount CameraPreview before routing away — prevents disposed EngineFlutterView.
  bool _isNavigating = false;
  /// When true, a glass pane sits over the YouTube iframe so dialogs receive taps.
  bool _isOverlayActive = false;
  bool _audioOnlyMode = false;
  bool _audioRecording = false;
  bool _virtualRecording = false;
  /// Recording clock (mm:ss). Timer ticks ONLY mutate this — never parent setState.
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  /// Alias used by audio-only preview meters (same notifier).
  ValueNotifier<int> get _virtualSeconds => _recordingDuration;
  /// Isolated amplitude meter — must not call parent setState during capture.
  final ValueNotifier<double> _audioLevel = ValueNotifier<double>(0);
  /// Bumps once after stop-grace elapses so FAB updates without camera rebuild.
  final ValueNotifier<int> _stopGraceTick = ValueNotifier<int>(0);
  Timer? _virtualTimer;
  Timer? _recordingTimer;
  Timer? _maxRecordingTimer;
  final AudioRecorder _recorder = AudioRecorder();
  bool _countingDown = false;
  String _countdownLabel = '';
  /// Countdown banner — must not rebuild CameraPreview via parent setState.
  final ValueNotifier<bool> _countingDownN = ValueNotifier<bool>(false);
  final ValueNotifier<String> _countdownLabelN = ValueNotifier<String>('');
  /// Recording FAB / overlays without rebuilding the camera HtmlElementView.
  final ValueNotifier<bool> _recordingUiN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _processingSaveN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _cameraStartingN = ValueNotifier<bool>(false);
  /// Save-dialog filename field — owned by this State for the full widget lifetime.
  /// Never dispose after showDialog; that races the TextField during route pop.
  late final TextEditingController _saveNameController;
  /// True while play→pause unlock / pre-countdown arming is in flight.
  bool _recordArming = false;
  /// True while awaiting MediaRecorder start (UI blocked / loading).
  bool _cameraStarting = false;
  /// Completes when [startVideoRecording] has been confirmed live (or failed).
  Completer<bool>? _recorderStartCompleter;
  /// When camera MediaRecorder actually became live (stop armed after 2s).
  DateTime? _recordingLiveSince;
  Timer? _stopEnableTimer;
  /// Blocks boundary listener while A→B seek/delay/play is in flight.
  /// Prevents duplicate countdowns that fight over UI state.
  bool _isTransitioning = false;
  /// Only one section-delay countdown may run at a time.
  bool _sectionDelayInFlight = false;

  // A -> B segment engine state used while recording/virtual-recording so the
  // original video plays through every routine segment sequentially, honoring
  // each segment's speed and repeat count instead of just the first segment.
  int _engineSegmentIndex = 0;
  /// Section tab the user last chose (e.g. Section E). Independent of engine
  /// auto-advance so save metadata does not fall back to Section A / 00:00.
  int _userSelectedSegmentIndex = 0;
  bool _engineSeeking = false;
  final Stopwatch _recordClock = Stopwatch();
  final List<PracticeIntervalMarker> _intervalMarkers = [];
  int? _openMarkerIndex;
  Timer? _enginePollTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<YoutubePlayerValue>? _engineYoutubeSub;
  VoidCallback? _engineOnFinished;
  bool _disposing = false;
  int _engineEpoch = 0;
  bool _engineActive = false;
  bool _engineAdvancing = false;
  /// Wall-clock fallback when YouTube JS-interop throws (keeps D→E alive).
  DateTime? _engineSegmentWallStart;
  double _engineSegmentAnchorSec = 0;
  double _engineSegmentSpeed = 1.0;
  /// Actual media length (Shorts often < authored section.endSec).
  double? _cachedVideoDurationSec;
  bool _stopInProgress = false;
  /// Non-blocking save/stop overlay so blob/controller work does not look frozen.
  bool _processingSave = false;
  /// Completed plays of the current segment (1 after first full pass).
  int _engineLoopsCompleted = 0;
  double? _captureOriginalEnd;
  /// Segment index where the practice recording actually began (e.g. Section E).
  int? _recordStartSegmentIndex;
  /// Frozen at stop-time so async save/nav cannot lose the section window.
  ({double start, double end})? _lockedSaveRange;

  bool get _youtubeAlive => !_disposing && mounted && _youtubeOriginal != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtubeOriginal, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    _saveNameController = TextEditingController();
    _initialize();
  }

  Future<void> _initialize() async {
    installYoutubeInteropErrorGuard();
    unawaited(_initCameraSafely());
    try {
      await _initOriginalMedia().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _originalError = '영상을 준비하는 데 시간이 초과되었습니다.';
      _showInitError(_originalError!);
    } catch (error) {
      _originalError = '원본 영상을 준비하지 못했습니다: $error';
      _showInitError(_originalError!);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _showInitError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initCameraSafely() async {
    CameraController? pending;
    try {
      debugPrint('[LOOPI] camera init: listing devices…');
      // Do NOT race a short Future.any timeout here — mobile permission prompts
      // and first-time initialize commonly take >5s and were incorrectly
      // forcing Audio-only mode.
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('cameraNotFound', 'No cameras available');
      }

      // Prefer front camera for practice selfie; fall back to any device.
      var description = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          description = camera;
          break;
        }
      }

      debugPrint(
        '[LOOPI] camera selected name=${description.name} '
        'lens=${description.lensDirection} count=${cameras.length}',
      );

      Object? lastError;
      for (final preset in <ResolutionPreset>[
        kPracticeCameraPreset,
        kPracticeCameraFallbackPreset,
      ]) {
        try {
          debugPrint('[LOOPI] camera initialize trying preset=$preset …');
          pending = CameraController(
            description,
            preset,
            enableAudio: true,
          );
          await pending.initialize();
          if (!mounted) {
            await pending.dispose();
            pending = null;
            return;
          }
          _camera = pending;
          pending = null;
          _cameraError = null;
          _audioOnlyMode = false;
          debugPrint('[LOOPI] camera initialized OK preset=$preset');
          if (!mounted) return;
          setState(() {});
          return;
        } catch (error, stack) {
          lastError = error;
          debugPrint(
            '[LOOPI] camera initialize FAILED preset=$preset: $error\n$stack',
          );
          try {
            await pending?.dispose();
          } catch (_) {}
          pending = null;
          _camera = null;
        }
      }

      throw lastError ?? CameraException('initFailed', 'Camera initialize failed');
    } catch (error, stack) {
      debugPrint('[LOOPI] camera init FINAL FAILURE: $error\n$stack');
      try {
        await pending?.dispose();
      } catch (_) {}
      try {
        await _camera?.dispose();
      } catch (_) {}
      pending = null;
      _camera = null;
      _cameraError = error is CameraException
          ? (error.description ?? error.code)
          : error.toString();
      await _handleCameraInitFailure(error);
    }
    if (!mounted) return;
    setState(() {});
  }

  /// Audio-only ONLY when there is no usable camera (missing / permission denied),
  /// never for transient timeouts or overconstrained retries that we already exhausted.
  Future<void> _handleCameraInitFailure(Object error) async {
    final message = error.toString().toLowerCase();
    final code = error is CameraException ? error.code.toLowerCase() : '';
    final noCamera = code.contains('cameranotfound') ||
        message.contains('no cameras') ||
        message.contains('notfound');
    final permissionDenied = code.contains('permission') ||
        code.contains('withoutpermissions') ||
        code.contains('accessdenied') ||
        message.contains('permission') ||
        message.contains('notallowed') ||
        message.contains('denied');

    debugPrint(
      '[LOOPI] camera failure classified noCamera=$noCamera '
      'permissionDenied=$permissionDenied raw=$error',
    );

    bool micReady = false;
    try {
      micReady = await _recorder.hasPermission();
    } catch (e) {
      debugPrint('[LOOPI] mic permission check failed: $e');
      micReady = false;
    }

    // Only fall back to audio-only for real camera unavailability.
    if ((noCamera || permissionDenied) && micReady) {
      _audioOnlyMode = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              permissionDenied
                  ? '카메라 권한이 없어 음성 전용 모드로 전환합니다. (원인: $_cameraError)'
                  : '카메라를 찾을 수 없어 음성 전용 모드로 전환합니다. (원인: $_cameraError)',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    _audioOnlyMode = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            micReady
                ? '카메라 초기화에 실패했습니다: $_cameraError'
                : '카메라/마이크를 사용할 수 없습니다: $_cameraError',
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '재시도',
            onPressed: () => unawaited(_initCameraSafely()),
          ),
        ),
      );
    }
  }

  Future<String> _practiceAudioPath() async {
    if (kIsWeb) {
      return 'loopi_practice_${DateTime.now().microsecondsSinceEpoch}.wav';
    }
    final directory = await getTemporaryDirectory();
    return '${directory.path}/loopi_practice_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  Future<void> _startPracticeAudioRecording() async {
    final path = await _practiceAudioPath();
    final config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
      numChannels: 1,
      sampleRate: 44100,
    );
    await _recorder.start(config, path: path);
  }

  Future<void> _initOriginalMedia() async {
    final routine = widget.routine;
    if (routine.sourceType == SourceType.youtube) {
      final videoId = resolveYoutubeVideoId(videoId: routine.videoId, videoUrl: routine.videoUrl);
      if (videoId == null || videoId.isEmpty) {
        throw StateError('YouTube 영상 ID가 없습니다.');
      }
      _youtubeOriginal = createLoopiYoutubeController(
        videoId: videoId,
        autoPlay: false,
      );
    }

    final path = routine.localFilePath;
    if (routine.sourceType == SourceType.localVideo) {
      if (path != null && path.isNotEmpty && !kIsWeb) {
        _original = VideoPlayerController.file(File(path));
        await _original!.initialize();
      } else if (routine.localDataBytes != null && routine.localDataBytes!.isNotEmpty) {
        _originalObjectUrl = createMediaBlobUrl(routine.localDataBytes!, 'video/mp4');
        final uri = _originalObjectUrl == null
            ? Uri.dataFromBytes(routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(_originalObjectUrl!);
        _original = VideoPlayerController.networkUrl(uri);
        await _original!.initialize();
      } else if (path != null && path.isNotEmpty) {
        _original = createCachedNetworkVideo(Uri.parse(path));
        await _original!.initialize();
      } else {
        throw StateError('로컬 영상 파일을 찾을 수 없습니다.');
      }
    }

    if (routine.segments.isEmpty) return;
    final firstSegmentStartTime = routine.segments.first.startSec;
    if (_original != null && _original!.value.isInitialized) {
      await _original!.seekTo(Duration(milliseconds: (firstSegmentStartTime * 1000).round()));
    }
    if (_youtubeOriginal != null) {
      await _yt(
        (player) => player.seekTo(seconds: firstSegmentStartTime).timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        ),
      );
    }
  }

  /// Selected section start (never jump to 0:00 on unlock/reset).
  double get _practiceStartSec {
    final segments = widget.routine.segments;
    if (segments.isEmpty) return 0;
    final idx = _userSelectedSegmentIndex.clamp(0, segments.length - 1);
    return _clampSeekToMedia(segments[idx].startSec);
  }

  /// Record FAB entry: unlock iframe with a short play→gap→pause/seek, then
  /// countdown, then real play + camera. Avoids sync play/pause race that
  /// resets YouTube to the thumbnail / cued state.
  Future<void> _onRecordPressed() async {
    if (_recordArming || _recording || _virtualRecording || _audioRecording) return;
    _recordArming = true;
    if (mounted) setState(() {});

    try {
      // Fresh take: drop prior section takes for this routine so Comparison only
      // shows the section about to be recorded (no A/B/C leak from old sessions).
      try {
        await widget.library.clearPracticeResultsForRoutine(widget.routine.id);
      } catch (e) {
        debugPrint('[LOOPI] clear prior takes ignored: $e');
      }

      final startSec = _practiceStartSec;
      final yt = _youtubeOriginal;
      final local = _original;

      // a) Start play on the user-gesture call stack (before any await).
      if (yt != null) {
        try {
          // ignore: unawaited_futures
          yt.playVideo();
        } catch (e) {
          debugPrint('[LOOPI] unlock play ignored: $e');
        }
      }
      if (local != null && local.value.isInitialized) {
        try {
          // ignore: unawaited_futures
          local.play();
        } catch (e) {
          debugPrint('[LOOPI] unlock local play ignored: $e');
        }
      }

      // b) Let the iframe register PLAYING before we pause (sync play/pause races).
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted || _disposing) return;

      // c) Pause and park on the selected section start (not 0:00).
      if (yt != null) {
        try {
          // ignore: unawaited_futures
          yt.pauseVideo();
          // ignore: unawaited_futures
          yt.seekTo(seconds: startSec, allowSeekAhead: true);
        } catch (e) {
          debugPrint('[LOOPI] unlock pause/seek ignored: $e');
        }
      }
      if (local != null && local.value.isInitialized) {
        try {
          await local.pause();
          await local.seekTo(Duration(milliseconds: (startSec * 1000).round()));
        } catch (e) {
          debugPrint('[LOOPI] unlock local pause/seek ignored: $e');
        }
      }

      // d–e) Countdown, then play + startVideoRecording.
      await _toggleRecording();
    } finally {
      _recordArming = false;
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      if (_audioRecording) {
        await _toggleAudioOnlyRecording();
        return;
      }
      await _stopVideoRecordingSafely(_camera);
      return;
    }

    // --- Start recording ---
    // Gesture unlock already parked the player at startSec (see _onRecordPressed).
    // 1) Resolve capture mode
    // 2) Run 3-2-1 countdown
    // 3) On countdown end: playVideo + startVideoRecording together
    var camera = _camera;
    var cameraAvailable = camera?.value.isInitialized == true;
    final knownMissingCamera = _audioOnlyMode ||
        (_cameraError != null &&
            (_cameraError!.toLowerCase().contains('notfound') ||
                _cameraError!.toLowerCase().contains('no camera') ||
                _cameraError!.toLowerCase().contains('cameranotfound')));

    if (!cameraAvailable && !knownMissingCamera) {
      debugPrint('[LOOPI] camera not ready at record press — bounded retry');
      try {
        await _initCameraSafely().timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[LOOPI] camera retry ignored: $e');
      }
      camera = _camera;
      cameraAvailable = camera?.value.isInitialized == true;
    }

    final microphoneAvailable = await _recorder.hasPermission();

    // No camera + no mic → optional virtual session (still plays YouTube).
    if (!cameraAvailable && !microphoneAvailable) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => PointerInterceptor(
          child: AlertDialog(
            title: const Text('카메라, 마이크가 감지되지 않습니다'),
            content: const Text('영상 재생만 하며 가상 녹화를 진행할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('아니오')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('네')),
            ],
          ),
        ),
      );
      if (proceed == true) {
        final countdownOk = await _runCountdown();
        if (mounted && countdownOk) _startVirtualRecording();
      }
      return;
    }

    // Prefer real camera when ready; otherwise audio-only without blocking playback.
    final useCamera = cameraAvailable && camera != null;
    if (!useCamera && microphoneAvailable && !knownMissingCamera && !_audioOnlyMode) {
      // Soft prompt once — cancel returns; confirm continues into shared start path.
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => PointerInterceptor(
          child: AlertDialog(
            title: const Text('카메라를 사용할 수 없습니다'),
            content: Text(
              _cameraError == null
                  ? '카메라 없이 음성만 녹화할까요?'
                  : '카메라 오류: $_cameraError\n\n음성만 녹화할까요?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
              TextButton(
                onPressed: () {
                  unawaited(_initCameraSafely());
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('카메라 재시도'),
              ),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('음성만 녹화')),
            ],
          ),
        ),
      );
      if (proceed != true) return;
    }

    // d) Countdown — player stays paused at startSec.
    final countdownOk = await _runCountdown();
    if (!mounted || !countdownOk) return;
    // e) playVideo + startVideoRecording
    await _startPracticeSession(
      preferCamera: useCamera,
      camera: camera,
    );
  }

  /// Resume original playback (after countdown). Call play only — do not pause.
  void _kickOriginalPlaybackNow() {
    final youtube = _youtubeOriginal;
    if (youtube != null) {
      try {
        // ignore: unawaited_futures
        youtube.playVideo();
      } catch (e) {
        debugPrint('[LOOPI] kick YouTube play ignored: $e');
      }
    }
    try {
      final original = _original;
      if (original != null && original.value.isInitialized) {
        // ignore: unawaited_futures
        original.play();
      }
    } catch (e) {
      debugPrint('[LOOPI] kick local play ignored: $e');
    }
  }

  bool get _stopGraceElapsed {
    final since = _recordingLiveSince;
    if (since == null) return false;
    return DateTime.now().difference(since) >= const Duration(seconds: 2);
  }

  /// Stop is allowed only after MediaRecorder is live + 2s grace (camera takes).
  bool get _canStopRecording {
    if (_virtualRecording || _audioRecording) return true;
    if (!_recording || _cameraStarting) return false;
    if (!(_camera?.value.isInitialized == true && _camera!.value.isRecordingVideo)) {
      return false;
    }
    return _stopGraceElapsed;
  }

  void _armStopGracePeriod() {
    _recordingLiveSince = DateTime.now();
    _stopEnableTimer?.cancel();
    _stopEnableTimer = Timer(const Duration(seconds: 2), () {
      // Do NOT setState the practice screen — that rebuilds CameraPreview.
      if (mounted) _stopGraceTick.value++;
    });
  }

  /// Starts Practice capture AFTER MediaRecorder is fully live, then plays.
  Future<void> _startPracticeSession({
    required bool preferCamera,
    CameraController? camera,
  }) async {
    // Camera path: await startVideoRecording + isRecordingVideo BEFORE
    // timer / YouTube play / single-section watcher.
    if (preferCamera && camera != null) {
      // Never setState here — remounts HtmlElementView and triggers Skia shader floods.
      _cameraStarting = true;
      _cameraStartingN.value = true;
      final startGate = Completer<bool>();
      _recorderStartCompleter = startGate;
      final cameraOk = await _tryStartCameraRecording(camera);
      if (!startGate.isCompleted) startGate.complete(cameraOk);
      if (!identical(_recorderStartCompleter, startGate)) {
        // Superseded by a newer start attempt.
      } else {
        _recorderStartCompleter = null;
      }
      if (!mounted) return;
      if (!cameraOk) {
        _cameraStarting = false;
        _cameraStartingN.value = false;
        debugPrint('[LOOPI] camera start failed — falling back to audio-only');
        await _startAudioOnlyPracticeSession();
        return;
      }

      // Confirmed MediaRecorder live — hide "준비 중" banner immediately.
      _recording = true;
      _audioOnlyMode = false;
      _audioRecording = false;
      _cameraStarting = false;
      _cameraStartingN.value = false;
      _beginRecordClock();
      _armStopGracePeriod();
      _recordingTimer?.cancel();
      _armMaxRecordingTimer();
      _recordingUiN.value = true;
      // Timer ticks via ValueNotifier only — never setState the camera parent.
      _recordingDuration.value = 0;
      _virtualTimer?.cancel();
      _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recording) return;
        _recordingDuration.value += 1;
      });

      // MediaRecorder is live — NOW start original playback + segment engine.
      final yt = _youtubeOriginal;
      if (yt != null) {
        try {
          // ignore: unawaited_futures
          yt.seekTo(seconds: _practiceStartSec, allowSeekAhead: true);
          // ignore: unawaited_futures
          yt.playVideo();
        } catch (e) {
          debugPrint('[LOOPI] post-countdown play ignored: $e');
        }
      }
      _kickOriginalPlaybackNow();
      unawaited(_beginSegmentEngine(
        onFinished: () {
          if (!_stopInProgress && !_processingSave) {
            unawaited(_handleStopPressed());
          }
        },
        skipCue: true,
      ));
      return;
    }

    await _startAudioOnlyPracticeSession();
  }

  Future<void> _startAudioOnlyPracticeSession() async {
    // Audio / virtual-style capture (no MediaRecorder grace needed).
    _recording = true;
    _audioOnlyMode = true;
    _audioRecording = false;
    _cameraStarting = false;
    _cameraStartingN.value = false;
    _beginRecordClock();
    _recordingLiveSince = DateTime.now();
    _recordingTimer?.cancel();
    _armMaxRecordingTimer();
    _recordingDuration.value = 0;
    _virtualTimer?.cancel();
    _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_audioRecording || _recording)) {
        _recordingDuration.value += 1;
      }
    });
    // Audio-only: no CameraPreview HtmlElementView — notifier UI is enough.
    _recordingUiN.value = true;

    final yt = _youtubeOriginal;
    if (yt != null) {
      try {
        // ignore: unawaited_futures
        yt.seekTo(seconds: _practiceStartSec, allowSeekAhead: true);
        // ignore: unawaited_futures
        yt.playVideo();
      } catch (e) {
        debugPrint('[LOOPI] post-countdown play ignored: $e');
      }
    }
    _kickOriginalPlaybackNow();
    unawaited(_beginSegmentEngine(
      onFinished: () {
        if (!_stopInProgress && !_processingSave) {
          unawaited(_handleStopPressed());
        }
      },
      skipCue: true,
    ));
    await _tryStartAudioCaptureQuietly();
  }

  /// Localized camera start. Never throws to the caller.
  /// Returns true only when [isRecordingVideo] is confirmed true.
  Future<bool> _tryStartCameraRecording(CameraController camera) async {
    try {
      if (!camera.value.isInitialized) {
        debugPrint('[LOOPI] camera not initialized — skip startVideoRecording');
        return false;
      }
      if (camera.value.isRecordingVideo) {
        debugPrint('[LOOPI] camera already recording');
        return true;
      }
      await camera.startVideoRecording().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('startVideoRecording'),
      );
      // Web: Future may resolve before MediaRecorder flips isRecordingVideo.
      final live = await _waitUntilCameraRecording(camera);
      if (!live) {
        debugPrint('[LOOPI] startVideoRecording returned but isRecordingVideo stayed false');
        return false;
      }
      _audioOnlyMode = false;
      _audioRecording = false;
      debugPrint('[LOOPI] camera recording started (isRecordingVideo=true)');
      // Do NOT setState — remounts HtmlElementView the moment capture goes live.
      return true;
    } on CameraException catch (e) {
      debugPrint(
        '[LOOPI] CameraException during startVideoRecording '
        'code=${e.code} desc=${e.description} — audio fallback',
      );
      return false;
    } catch (e) {
      debugPrint('[LOOPI] startVideoRecording failed (non-fatal): $e');
      return false;
    }
  }

  /// Polls until MediaRecorder is live (bounded). Used by start + stop handshake.
  Future<bool> _waitUntilCameraRecording(
    CameraController camera, {
    Duration timeout = const Duration(milliseconds: 1500),
    Duration step = const Duration(milliseconds: 300),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      try {
        if (camera.value.isInitialized && camera.value.isRecordingVideo) {
          return true;
        }
      } catch (_) {
        return false;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(remaining < step ? remaining : step);
    }
    try {
      return camera.value.isInitialized && camera.value.isRecordingVideo;
    } catch (_) {
      return false;
    }
  }

  /// If start is still in flight, wait for it. Then wait for isRecordingVideo.
  Future<bool> _ensureCameraRecordingBeforeStop(CameraController? camera) async {
    final pending = _recorderStartCompleter;
    if (pending != null && !pending.isCompleted) {
      debugPrint('[LOOPI] stop waiting for startVideoRecording handshake…');
      try {
        final ok = await pending.future.timeout(const Duration(seconds: 3));
        if (!ok) return false;
      } catch (e) {
        debugPrint('[LOOPI] start handshake wait failed: $e');
        return false;
      }
    }
    final live = camera ?? _camera;
    if (live == null || !live.value.isInitialized) return false;
    if (live.value.isRecordingVideo) return true;
    debugPrint('[LOOPI] stop: isRecordingVideo=false — bounded spin-up wait');
    return _waitUntilCameraRecording(live);
  }

  /// Mic capture after playback already started. Swallows errors.
  Future<void> _tryStartAudioCaptureQuietly() async {
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        debugPrint('[LOOPI] mic permission denied — playback continues without capture');
        return;
      }
      _audioOnlyMode = true;
      _audioRecording = true;
      await _startPracticeAudioRecording();
      _startAmplitudeMonitor();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('카메라 없이 음성만 기록합니다. 원본 영상은 계속 재생됩니다.'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('[LOOPI] audio capture start ignored: $e');
    }
  }

  /// Awaits [CameraController.stopVideoRecording] and returns the file path.
  /// Does NOT call setState and does NOT stop preview MediaStream tracks.
  Future<String?> _awaitStopVideoRecording(CameraController live) async {
    if (!live.value.isInitialized) {
      debugPrint('[LOOPI] stopRecording skipped — camera not initialized');
      return null;
    }
    if (!live.value.isRecordingVideo) {
      debugPrint('[LOOPI] stopRecording skipped — isRecordingVideo=false');
      return null;
    }
    try {
      // Web MediaRecorder: wait for the chunk buffer to catch up before stop().
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!live.value.isRecordingVideo) {
        debugPrint('[LOOPI] stopRecording aborted — recording ended during flush delay');
        return null;
      }
      // CRITICAL (Web): never force-stop getUserMedia tracks before this await —
      // that blacks out CameraPreview and yields an empty / missing blob.
      final file = await live.stopVideoRecording().timeout(
        Duration(seconds: kIsWeb ? 8 : 3),
        onTimeout: () => throw TimeoutException('stopVideoRecording'),
      );
      debugPrint('[LOOPI] stopVideoRecording ok path=${file.path}');
      return file.path;
    } on CameraException catch (e, stack) {
      debugPrint(
        '[LOOPI] stopVideoRecording CameraException '
        'code=${e.code} desc=${e.description}\n$stack',
      );
      return null;
    } on TimeoutException catch (e, stack) {
      debugPrint('[LOOPI] stopVideoRecording timed out: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('[LOOPI] stopVideoRecording failed safely: $e\n$stack');
      return null;
    }
  }

  /// Stop order (Web-safe):
  /// 1) Halt engine flags without rebuilding camera UI
  /// 2) Await stopVideoRecording → XFile
  /// 3) Only then setState(isRecording: false)
  /// 4) Save dialog / empty-file snackbar
  ///
  /// Never dispose the camera or remount CameraPreview during this path.
  Future<void> _stopVideoRecordingSafely(CameraController? camera) async {
    if (_stopInProgress) {
      debugPrint(
        '[LOOPI] stop already in progress — ignoring re-entry '
        '(processingSave=$_processingSave recording=$_recording)',
      );
      return;
    }
    _stopInProgress = true;

    // Soft halt only — NO setState yet (keeps HtmlElementView / stream attached).
    _engineAdvancing = false;
    _engineSeeking = false;
    _isTransitioning = false;
    _sectionDelayInFlight = false;
    _stopEnableTimer?.cancel();
    _stopEnableTimer = null;
    _recordingLiveSince = null;
    _cameraStarting = false;
    _cameraStartingN.value = false;
    _stopAmplitudeMonitor();
    _stopSegmentEngine();
    _snapshotCaptureEndOffline();
    _lockPracticeSaveRange();

    final live = camera ?? _camera;
    String? recordedPath;

    try {
      // 1) Must actually be recording — wait for late MediaRecorder spin-up.
      final ready = await _ensureCameraRecordingBeforeStop(live);
      if (!ready ||
          live == null ||
          !live.value.isInitialized ||
          !live.value.isRecordingVideo) {
        debugPrint(
          '[LOOPI] stop aborted — not recording '
          '(null=${live == null} init=${live?.value.isInitialized} '
          'rec=${live?.value.isRecordingVideo})',
        );
        if (mounted) {
          _recording = false;
          _processingSave = false;
          _recordingUiN.value = false;
          _processingSaveN.value = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹화된 영상이 없습니다')),
          );
        }
        return;
      }

      // 2–3) AWAIT blob BEFORE any recording UI rebuild.
      recordedPath = await _awaitStopVideoRecording(live);

      // Mic fallback only if camera stop produced nothing.
      if ((recordedPath == null || recordedPath.isEmpty) &&
          await _recorder.isRecording()) {
        try {
          final audioPath = await _recorder.stop().timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException('recorderStop'),
          );
          if (audioPath != null && audioPath.isNotEmpty) {
            recordedPath = audioPath;
          }
        } catch (audioError) {
          debugPrint('[LOOPI] audio fallback after video stop failed: $audioError');
        }
      }

      // 4) Flip recording UI via notifiers — do NOT setState (camera still mounted).
      if (mounted) {
        _recording = false;
        _processingSave = recordedPath != null && recordedPath.isNotEmpty;
        _recordingUiN.value = false;
        _processingSaveN.value = _processingSave;
      }

      // Best-effort pause AFTER recorder stopped — never blocks save.
      unawaited(_haltOriginalPlayback());

      // 5) Handle file
      if (recordedPath != null && recordedPath.isNotEmpty) {
        await _endStopProcessing();
        _stopInProgress = false;
        if (!mounted) return;
        await _showSaveDialog(
          recordedPath: recordedPath,
          isAudioRecording:
              _audioOnlyMode || _pathLooksLikeAudioRecording(recordedPath),
        );
      } else if (mounted) {
        await _endStopProcessing();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹화된 영상이 없습니다')),
        );
      }
    } catch (error, stack) {
      debugPrint('stop recording failed: $error\n$stack');
      if (mounted) {
        _recording = false;
        _processingSave = false;
        _recordingUiN.value = false;
        _processingSaveN.value = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹화된 영상이 없습니다')),
        );
      }
    } finally {
      _stopInProgress = false;
      _processingSave = false;
      _processingSaveN.value = false;
      _engineAdvancing = false;
      _engineSeeking = false;
      // Do not setState while CameraPreview may still be mounted on web.
      _recording = false;
      _recordingUiN.value = false;
    }
  }

  /// Stop while recording must always be tappable — never blocked by zombie flags.
  Future<void> _handleStopPressed() async {
    _engineAdvancing = false;
    _engineSeeking = false;
    _cancelEngineListeners();
    try {
      if (_virtualRecording) {
        _stopVirtualRecording();
        return;
      }
      if (_audioRecording) {
        await _toggleAudioOnlyRecording();
        return;
      }
      if (_recording || _cameraStarting || _recorderStartCompleter != null) {
        final cam = _camera;
        final ready = await _ensureCameraRecordingBeforeStop(cam);
        final live = ready &&
            cam != null &&
            cam.value.isInitialized &&
            cam.value.isRecordingVideo;
        if (!live) {
          debugPrint(
            '[LOOPI] stop ignored — camera not recording yet '
            '(initialized=${cam?.value.isInitialized} '
            'isRecordingVideo=${cam?.value.isRecordingVideo} '
            'starting=$_cameraStarting)',
          );
          if (mounted && !_cameraStarting && _recorderStartCompleter == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('녹화가 아직 시작되지 않았습니다. 잠시만 기다려 주세요.'),
              ),
            );
          }
          return;
        }
        await _stopVideoRecordingSafely(_camera);
      }
    } catch (e, stack) {
      debugPrint('[LOOPI] handleStopPressed failed: $e\n$stack');
      _stopInProgress = false;
      _processingSave = false;
      _recording = false;
      _virtualRecording = false;
      _audioRecording = false;
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _toggleAudioOnlyRecording() async {
    try {
      if (_audioRecording) {
        if (_stopInProgress) return;
        _stopInProgress = true;
        await _beginStopProcessing();
        try {
          _virtualTimer?.cancel();
          _virtualTimer = null;
          _stopAmplitudeMonitor();
          _stopSegmentEngine();
          // Offline only — never query YouTube before/during recorder stop.
          _snapshotCaptureEndOffline();
          _lockPracticeSaveRange();
          final path = await _recorder.stop().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('recorderStop'),
          );
          _audioRecording = false;
          _recording = false;
          if (!mounted) {
            await _endStopProcessing();
            return;
          }
          setState(() {});
          unawaited(_haltOriginalPlayback());
          await Future<void>.delayed(Duration.zero);
          await _endStopProcessing();
          if (!mounted) return;
          await _showSaveDialog(
            recordedPath: path,
            isAudioRecording: true,
          );
        } catch (error, stack) {
          debugPrint('stop audio recording failed: $error\n$stack');
          await _endStopProcessing();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('음성 저장 준비에 실패했습니다. 다시 시도해 주세요.')),
            );
          }
        }
        return;
      }
      await _runCountdown();
      if (!mounted) return;
      _audioOnlyMode = true;
      _audioRecording = true;
      _recording = true;
      _virtualSeconds.value = 0;
      _virtualTimer?.cancel();
      _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _audioRecording) {
          _virtualSeconds.value += 1;
        }
      });
      _beginRecordClock();
      _recordingTimer?.cancel();
      _armMaxRecordingTimer();
      // Audio path — no CameraPreview; recording UI via notifier.
      _recordingUiN.value = true;

      // After countdown: play + mic together (gesture was armed on FAB press).
      _kickOriginalPlaybackNow();
      unawaited(_beginSegmentEngine(onFinished: () {
        if (_audioRecording && !_stopInProgress) unawaited(_toggleAudioOnlyRecording());
      }));
      try {
        await _startPracticeAudioRecording();
        _startAmplitudeMonitor();
      } catch (error) {
        debugPrint('[LOOPI] audio start failed: $error');
        if (!mounted) return;
        setState(() => _error = '음성 녹화에 실패했습니다: $error');
      }
    } catch (error) {
      _stopAmplitudeMonitor();
      _audioRecording = false;
      _recording = false;
      if (!mounted) return;
      setState(() => _error = '음성 녹화에 실패했습니다: $error');
    } finally {
      _stopInProgress = false;
      _processingSave = false;
      if (mounted) _processingSaveN.value = false;
    }
  }

  Future<void> _beginStopProcessing() async {
    if (!mounted) return;
    _processingSave = true;
    _processingSaveN.value = true;
    // Yield so the preparing overlay paints before MediaRecorder work blocks web.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _endStopProcessing() async {
    _processingSave = false;
    if (!mounted) return;
    _processingSaveN.value = false;
  }

  // ignore: unused_element
  Future<void> _attachRecordedFromPath(String path) async {
    final previous = _recorded;
    try {
      final next = (kIsWeb || path.startsWith('blob:') || path.startsWith('http'))
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      _recorded = next;
      await awaitVideoPlayerReady(next);
      // ignore: avoid_print
      print('Saved video duration: ${next.value.duration}');
      await next.pause();
      await next.seekTo(Duration.zero);
    } catch (error) {
      debugPrint('attach recorded controller failed: $error');
      // Keep a controller bound to the path when possible; comparison can recover.
    } finally {
      if (previous != null && !identical(previous, _recorded)) {
        try {
          await previous.dispose();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  int get _recordingDelaySeconds {
    final segments = widget.routine.segments;
    final configured = segments.isNotEmpty ? segments.first.delaySec : 0;
    return configured > 0 ? configured : 3;
  }

  /// Shows a full-screen N-…-1-START countdown (pre-record or section delay).
  /// Returns false if another countdown already owns the UI (caller must not play).
  Future<bool> _runCountdown({int? seconds}) async {
    if (!mounted) return false;
    // Synchronous guard — must run before any await to stop concurrent callers.
    if (_countingDown) return false;
    final total = seconds ?? _recordingDelaySeconds;
    if (total <= 0) return true;
    _countingDown = true;
    _countdownLabel = '$total';
    _syncCountdownNotifiers();
    // Pre-record countdown may setState; mid-record section delay must NOT.
    if (!_cameraCaptureLive) {
      if (!mounted) return false;
      setState(() {});
    }
    for (var i = total; i >= 1; i--) {
      if (!mounted || _stopInProgress || _disposing) {
        _countingDown = false;
        _syncCountdownNotifiers();
        if (!_cameraCaptureLive && mounted) {
          setState(() {});
        }
        return false;
      }
      _countdownLabel = '$i';
      _syncCountdownNotifiers();
      if (!_cameraCaptureLive) {
        if (!mounted) return false;
        setState(() {});
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || _stopInProgress || _disposing) {
      _countingDown = false;
      _syncCountdownNotifiers();
      if (!_cameraCaptureLive && mounted) {
        setState(() {});
      }
      return false;
    }
    _countdownLabel = 'START!';
    _syncCountdownNotifiers();
    if (!_cameraCaptureLive) {
      if (!mounted) return false;
      setState(() {});
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return false;
    _countingDown = false;
    _syncCountdownNotifiers();
    if (!_cameraCaptureLive) {
      setState(() {});
    }
    return true;
  }

  bool get _isPracticeRecordingActive =>
      _recording || _virtualRecording || _audioRecording;

  /// True while camera MediaRecorder is live — parent setState remounts HtmlElementView.
  bool get _cameraCaptureLive =>
      _recording &&
      !_audioOnlyMode &&
      _camera != null &&
      !_isNavigating;

  /// Prefer no-op during camera capture; only mutate fields / ValueNotifiers.
  void _practiceSetState(VoidCallback fn) {
    fn();
    if (!mounted) return;
    if (_cameraCaptureLive) {
      _recordingUiN.value = _recording || _virtualRecording || _audioRecording;
      return;
    }
    setState(() {});
  }

  void _syncCountdownNotifiers() {
    _countingDownN.value = _countingDown;
    _countdownLabelN.value = _countdownLabel;
  }

  /// Section chips are selectable only before Record (select section → then Record).
  bool get _sectionChipsLocked =>
      _isPracticeRecordingActive || _countingDown || _stopInProgress || _processingSave;

  /// Drives the original video/audio through every routine segment in order
  /// (A -> B -> ...), applying each segment's speed and repeat count.
  void _beginRecordClock() {
    _recordClock
      ..reset()
      ..start();
    _intervalMarkers.clear();
    _openMarkerIndex = null;
    // Do not pin to Section A here — [_beginSegmentEngine] sets the real start
    // from the user-selected section tab.
    _captureOriginalEnd = null;
    _recordStartSegmentIndex = null;
    _lockedSaveRange = null;
  }

  /// Freeze save range from the recording start section through the furthest
  /// section reached (supports D→E advance). Uses TRUE section timestamps only.
  void _lockPracticeSaveRange() {
    final segments = widget.routine.segments;
    if (segments.isEmpty) {
      _lockedSaveRange = (start: 0, end: 0.5);
      return;
    }
    final startIdx = (_recordStartSegmentIndex ?? _userSelectedSegmentIndex)
        .clamp(0, segments.length - 1);
    final endIdx = _engineSegmentIndex.clamp(0, segments.length - 1);
    final start = segments[startIdx].startSec;
    var end = segments[endIdx].endSec;
    // Honor an already-expanded lock from D→E advance (still section-based).
    final prev = _lockedSaveRange;
    if (prev != null && prev.start <= start + 0.05 && prev.end > end) {
      end = prev.end;
    }
    if (end <= start) end = start + 0.5;
    _lockedSaveRange = (start: start, end: end);
    _captureOriginalEnd = end;
    _recordStartSegmentIndex = startIdx;
    debugPrint(
      '[LOOPI] lock practice range section=${sectionLabelForIndex(startIdx)}→${sectionLabelForIndex(endIdx)} '
      'start=$start end=$end userSelected=$_userSelectedSegmentIndex',
    );
  }

  ({double start, double end}) _savedCaptureRange() {
    if (_lockedSaveRange != null) {
      final locked = _lockedSaveRange!;
      if (locked.end > locked.start) return locked;
    }

    final segments = widget.routine.segments;
    if (segments.isEmpty) return (start: 0.0, end: 0.5);

    final idx = (_recordStartSegmentIndex ?? _userSelectedSegmentIndex)
        .clamp(0, segments.length - 1);
    final targetSection = segments[idx];
    final start = targetSection.startSec;
    final end = targetSection.endSec > start ? targetSection.endSec : start + 0.5;
    return (start: start, end: end);
  }

  void _startAmplitudeMonitor() {
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 200)).listen(
      (amp) {
        if (!mounted || !_audioRecording) return;
        // dBFS is typically ~[-160, 0]; map a usable speech range to 0..1.
        final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
        if ((normalized - _audioLevel.value).abs() < 0.04) return;
        _audioLevel.value = normalized;
      },
      onError: (_) {},
    );
  }

  void _stopAmplitudeMonitor() {
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    _audioLevel.value = 0;
  }

  /// Capture end time without touching YouTube (markers / wall clock / section).
  void _snapshotCaptureEndOffline() {
    try {
      final estimated = _estimateEngineTime();
      if (estimated != null) {
        _captureOriginalEnd = estimated;
        return;
      }
    } catch (_) {}
    if (_intervalMarkers.isNotEmpty) {
      final last = _intervalMarkers.last;
      final seg = widget.routine.segments[last.segmentIndex.clamp(0, widget.routine.segments.length - 1)];
      final elapsedSec = (last.endOffsetMillis - last.startOffsetMillis) / 1000.0;
      _captureOriginalEnd = (seg.startSec + elapsedSec).clamp(seg.startSec, seg.endSec);
      return;
    }
    final segments = widget.routine.segments;
    if (segments.isEmpty) return;
    final idx = _engineSegmentIndex.clamp(0, segments.length - 1);
    final seg = segments[idx];
    _captureOriginalEnd = seg.endSec > seg.startSec ? seg.endSec : seg.startSec + 0.5;
  }

  void _closeOpenIntervalMarker() {
    if (_openMarkerIndex == null) return;
    final endMs = _recordClock.elapsedMilliseconds;
    final previous = _intervalMarkers[_openMarkerIndex!];
    _intervalMarkers[_openMarkerIndex!] = PracticeIntervalMarker(
      intervalId: previous.intervalId,
      startOffsetMillis: previous.startOffsetMillis,
      endOffsetMillis: endMs < previous.startOffsetMillis ? previous.startOffsetMillis : endMs,
      segmentIndex: previous.segmentIndex,
    );
    _openMarkerIndex = null;
  }

  void _logIntervalTransition(int segmentIndex) {
    if (!_recording && !_virtualRecording && !_audioRecording) return;
    if (segmentIndex < 0 || segmentIndex >= widget.routine.segments.length) return;
    _closeOpenIntervalMarker();
    final startMs = _recordClock.elapsedMilliseconds;
    _intervalMarkers.add(
      PracticeIntervalMarker(
        intervalId: sectionLabelForIndex(segmentIndex),
        startOffsetMillis: startMs,
        endOffsetMillis: startMs,
        segmentIndex: segmentIndex,
      ),
    );
    _openMarkerIndex = _intervalMarkers.length - 1;
  }

  bool get _engineSessionLive =>
      _engineActive &&
      !_disposing &&
      !_stopInProgress &&
      (_recording || _virtualRecording || _audioRecording);

  Future<void> _haltOriginalPlayback() async {
    try {
      await _original?.pause();
    } catch (_) {}
    // Fire-and-forget: never let YT interop block stop/save.
    unawaited(() async {
      try {
        await _yt((player) => player.pauseVideo());
      } catch (e) {
        debugPrint('Ignored YouTube interop error to keep listener alive: $e');
      }
    }());
  }

  Future<void> _beginSegmentEngine({
    required VoidCallback onFinished,
    bool skipCue = false,
  }) async {
    _engineEpoch += 1;
    final epoch = _engineEpoch;
    _engineActive = true;
    _engineAdvancing = false;
    _engineSeeking = false;
    _isTransitioning = false;
    _sectionDelayInFlight = false;
    _engineOnFinished = onFinished;
    _cancelEngineListeners();

    final segments = widget.routine.segments;
    // Select section FIRST, then Record: always use the chip selection at press time.
    final startIndex = segments.isEmpty ? 0 : _userSelectedSegmentIndex.clamp(0, segments.length - 1);
    final targetSection = segments.isEmpty ? null : segments[startIndex];

    _engineSegmentIndex = startIndex;
    _recordStartSegmentIndex = startIndex;
    _userSelectedSegmentIndex = startIndex;

    if (targetSection != null) {
      _captureOriginalEnd = targetSection.endSec > targetSection.startSec
          ? targetSection.endSec
          : targetSection.startSec + 0.5;
      // Lock metadata immediately to this section's exact bounds.
      _lockedSaveRange = (
        start: targetSection.startSec,
        end: _captureOriginalEnd!,
      );
    }

    debugPrint(
      '[LOOPI] begin recording at section=${sectionLabelForIndex(startIndex)} '
      'idx=$startIndex startSec=${targetSection?.startSec} endSec=${targetSection?.endSec} '
      'userSelected=$_userSelectedSegmentIndex skipCue=$skipCue',
    );
    // Do NOT setState here — remounts CameraPreview HtmlElementView mid-record.
    _recordingUiN.value = true;
    // Warm media duration so Shorts with endSec>duration can still advance.
    unawaited(_engineVideoDuration());
    // Pre-record countdown already consumed the first section's delay.
    await _playEngineSegment(
      startIndex,
      epoch: epoch,
      respectDelay: false,
      useCue: !skipCue,
    );
  }

  Future<void> _playEngineSegment(
    int index, {
    int? epoch,
    bool resetPlays = true,
    bool previewOnly = false,
    bool fromUserSelection = false,
    bool respectDelay = true,
    bool useCue = true,
  }) async {
    final token = epoch ?? _engineEpoch;
    if (index < 0 || index >= widget.routine.segments.length) return;
    // Ignore section jumps while a recording session is locked to one section.
    if (fromUserSelection && _isPracticeRecordingActive && !previewOnly) {
      return;
    }
    if (!previewOnly && (!_engineSessionLive || token != _engineEpoch)) {
      _engineSeeking = false;
      _engineAdvancing = false;
      return;
    }

    if (!previewOnly) {
      _isTransitioning = true;
      _engineAdvancing = true;
      _engineSeeking = true;
      _cancelEngineListeners();
    }

    if (!previewOnly) _logIntervalTransition(index);
    _engineSegmentIndex = index;
    final segment = widget.routine.segments[index];
    if (fromUserSelection && !_isPracticeRecordingActive) {
      _userSelectedSegmentIndex = index;
    }
    if (!previewOnly && _recordStartSegmentIndex == null) {
      _recordStartSegmentIndex = index;
    }
    // Never rebuild CameraPreview while MediaRecorder is live.
    if (!_cameraCaptureLive && mounted) setState(() {});
    if (resetPlays) {
      _engineLoopsCompleted = 0;
    }
    // Always re-anchor from the section start so wall-clock estimates cannot
    // stay stuck past EOF (e.g. atTime=39 on a 27s Short).
    _markEngineSegmentAnchor(segment.startSec, segment.speed);

    // Preview (chip tap before Record): seek + pause only — never auto-play.
    if (previewOnly) {
      unawaited(_seekEngineMedia(segment, play: false));
      return;
    }

    // Section delay: hold on start frame, run prep countdown, then play.
    final delaySec = respectDelay ? segment.delaySec : 0;
    if (delaySec > 0) {
      // Only one delay countdown may run — duplicates skip entirely (no play).
      if (_sectionDelayInFlight) {
        debugPrint(
          '[LOOPI] skip duplicate section delay for '
          '${sectionLabelForIndex(index)}',
        );
        return;
      }
      _sectionDelayInFlight = true;
      unawaited(_playEngineSegmentAfterDelay(segment, delaySec: delaySec, token: token));
      return;
    }

    // Recording progression: never block the engine poll on hung YouTube seeks.
    unawaited(_seekEngineMedia(segment, play: true, token: token, useCue: useCue));
  }

  /// Seek+pause → section delay countdown → play. Camera recording keeps running.
  Future<void> _playEngineSegmentAfterDelay(
    RoutineSegment segment, {
    required int delaySec,
    required int token,
  }) async {
    try {
      // Hold the start frame; keep transitioning locked so the poll cannot
      // re-fire A→B and spawn another countdown.
      _isTransitioning = true;
      _engineAdvancing = true;
      _engineSeeking = true;
      _cancelEngineListeners();

      await _seekEngineMedia(segment, play: false);
      if (!_engineSessionLive || token != _engineEpoch || _stopInProgress) {
        return;
      }

      debugPrint(
        '[LOOPI] section delay ${delaySec}s before '
        '${sectionLabelForIndex(_engineSegmentIndex)} play',
      );
      final countdownOk = await _runCountdown(seconds: delaySec);
      if (!countdownOk ||
          !_engineSessionLive ||
          token != _engineEpoch ||
          _stopInProgress ||
          !mounted) {
        return;
      }

      // Delay wall-time must not count as section playback progress.
      _markEngineSegmentAnchor(segment.startSec, segment.speed);
      await _seekEngineMedia(segment, play: true, token: token);
    } catch (e) {
      debugPrint('[LOOPI] delayed section start failed: $e');
    } finally {
      _sectionDelayInFlight = false;
      _isTransitioning = false;
      // Aborted before play: unlock and re-arm. Successful play already cleared
      // seeking/advancing and armed the poll inside [_seekEngineMedia].
      if (_engineSeeking || _engineAdvancing) {
        _engineSeeking = false;
        _engineAdvancing = false;
        if (token == _engineEpoch && _engineSessionLive && !_stopInProgress) {
          _armEnginePoll(token);
        }
      }
    }
  }

  /// Seek/rate (and optionally play) without stalling the recording timer loop.
  ///
  /// When [useCue] is false (post-countdown record start), skip `cueVideoById`
  /// so the iframe does not flash back to the thumbnail — only seek + play.
  Future<void> _seekEngineMedia(
    RoutineSegment segment, {
    required bool play,
    int? token,
    bool useCue = true,
  }) async {
    if (play) {
      _kickOriginalPlaybackNow();
    }

    final seekSec = _clampSeekToMedia(segment.startSec);
    final videoDuration = _cachedVideoDurationSec ?? await _engineVideoDuration();
    final effectiveEnd = _effectiveSectionEnd(segment, videoDuration);
    final endSeconds = effectiveEnd > seekSec ? effectiveEnd : null;
    try {
      await Future<void>(() async {
        try {
          final original = _original;
          if (original != null) {
            await original.setPlaybackSpeed(segment.speed);
            await original.seekTo(Duration(milliseconds: (seekSec * 1000).round()));
            if (play) {
              await original.play();
            } else {
              await original.pause();
            }
          }
        } catch (e) {
          debugPrint('[LOOPI] engine local seek/play ignored: $e');
        }
        if (_youtubeOriginal != null) {
          try {
            final videoId = resolveYoutubeVideoId(
              videoId: widget.routine.videoId,
              videoUrl: widget.routine.videoUrl,
            );
            await _yt((player) => player.setPlaybackRate(segment.speed))
                .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            // cueVideoById resets to thumbnail — only use when not already parked.
            if (useCue && videoId != null && videoId.isNotEmpty) {
              await _yt(
                (player) => player.cueVideoById(
                  videoId: videoId,
                  startSeconds: seekSec,
                  endSeconds: endSeconds,
                ),
              ).timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            }
            await _yt(
              (player) => player.seekTo(seconds: seekSec, allowSeekAhead: true),
            ).timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            if (play) {
              unawaited(
                _yt((player) => player.playVideo()).timeout(
                  const Duration(milliseconds: 800),
                  onTimeout: () => null,
                ),
              );
            } else {
              await _yt((player) => player.pauseVideo())
                  .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            }
          } catch (e) {
            debugPrint('Ignored YouTube interop error to keep listener alive: $e');
            if (play) {
              unawaited(_yt((player) => player.playVideo()));
            }
          }
        }
      }).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('[LOOPI] engine seek/play timed out — continuing poll');
          if (play) _kickOriginalPlaybackNow();
        },
      );
    } catch (e) {
      debugPrint('[LOOPI] engine seek/play failed: $e');
      if (play) _kickOriginalPlaybackNow();
    } finally {
      if (play) {
        _engineSeeking = false;
        _engineAdvancing = false;
        _isTransitioning = false;
        if (token != null && token == _engineEpoch && _engineSessionLive) {
          _armEnginePoll(token);
        }
      }
    }
  }

  double _clampSeekToMedia(double seconds) {
    final duration = _cachedVideoDurationSec;
    if (duration == null || duration <= 1) return seconds < 0 ? 0 : seconds;
    final maxSeek = (duration - 0.25).clamp(0.0, duration);
    return seconds.clamp(0.0, maxSeek);
  }

  /// Prefer duration API (no crashing videoData / metadata path on Web).
  Future<double?> _engineVideoDuration() async {
    if (_cachedVideoDurationSec != null && _cachedVideoDurationSec! > 1) {
      return _cachedVideoDurationSec;
    }
    try {
      final original = _original;
      if (original != null && original.value.isInitialized) {
        final d = original.value.duration.inMilliseconds / 1000.0;
        if (d > 1) {
          _cachedVideoDurationSec = d;
          return d;
        }
      }
      final youtube = _youtubeOriginal;
      if (youtube != null) {
        try {
          final d = await _yt((player) => player.duration)
              .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
          if (d != null && d > 1) {
            _cachedVideoDurationSec = d;
            return d;
          }
        } catch (e) {
          debugPrint('Ignored YouTube interop error to keep listener alive: $e');
        }
      }
    } catch (e) {
      debugPrint('Ignored YouTube interop error to keep listener alive: $e');
    }
    return _cachedVideoDurationSec;
  }

  /// Cap authored section.end when it exceeds the real Shorts/video length.
  double _effectiveSectionEnd(RoutineSegment segment, double? videoDuration) {
    final rawEnd = segment.endSec;
    final start = segment.startSec;
    if (videoDuration == null || videoDuration <= 1) return rawEnd;
    // Section end past EOF (e.g. endSec=30 on a 27s Short) → never fires without cap.
    if (rawEnd >= videoDuration - 0.05) {
      final capped = (videoDuration - 0.35).clamp(start + 0.05, videoDuration);
      return capped;
    }
    if (rawEnd > videoDuration) {
      return (videoDuration - 0.35).clamp(start + 0.05, videoDuration);
    }
    return rawEnd;
  }

  void _markEngineSegmentAnchor(double startSec, double speed) {
    _engineSegmentWallStart = DateTime.now();
    _engineSegmentAnchorSec = startSec;
    _engineSegmentSpeed = speed <= 0 ? 1.0 : speed;
  }

  /// Estimated original-timeline seconds when YT `currentTime` is unavailable.
  double? _estimateEngineTime() {
    final started = _engineSegmentWallStart;
    if (started == null) return null;
    final elapsed = DateTime.now().difference(started).inMilliseconds / 1000.0;
    if (elapsed < 0) return _engineSegmentAnchorSec;
    return _engineSegmentAnchorSec + elapsed * _engineSegmentSpeed;
  }

  void _cancelEngineListeners() {
    _enginePollTimer?.cancel();
    _enginePollTimer = null;
    unawaited(_engineYoutubeSub?.cancel());
    _engineYoutubeSub = null;
  }

  /// Periodic Timer — primary End-time enforcer while recording (same role as
  /// Playback's boundary poll). Prefer wall-clock estimate when YT currentTime
  /// stalls so Practice cannot run past End.
  void _armEnginePoll(int token) {
    _cancelEngineListeners();
    if (!_engineSessionLive || token != _engineEpoch) return;
    _enginePollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      unawaited(_engineTick(token));
    });
    _armEngineYoutubeBoundary(token);
  }

  /// Backup: when cue endSeconds fires PlayerState.ended, run the same End logic.
  void _armEngineYoutubeBoundary(int token) {
    unawaited(_engineYoutubeSub?.cancel());
    _engineYoutubeSub = null;
    final youtube = _youtubeOriginal;
    if (youtube == null || !_engineSessionLive || token != _engineEpoch) return;
    _engineYoutubeSub = listenYoutubeStream(
      youtube.stream,
      (value) {
        if (!_engineSessionLive || token != _engineEpoch) return;
        if (_engineSeeking || _engineAdvancing || _isTransitioning || _sectionDelayInFlight) {
          return;
        }
        if (value.playerState == PlayerState.ended) {
          debugPrint('[LOOPI] practice YT ended → section boundary');
          final segments = widget.routine.segments;
          if (_engineSegmentIndex < 0 || _engineSegmentIndex >= segments.length) return;
          final segment = segments[_engineSegmentIndex];
          final end = _effectiveSectionEnd(segment, _cachedVideoDurationSec);
          _onEngineTime(end, token, videoDuration: _cachedVideoDurationSec);
        }
      },
      isAlive: () => _youtubeAlive && _engineSessionLive,
    );
  }

  Future<void> _engineTick(int token) async {
    if (!_engineSessionLive ||
        token != _engineEpoch ||
        _engineSeeking ||
        _engineAdvancing ||
        _isTransitioning ||
        _sectionDelayInFlight ||
        _countingDown) {
      return;
    }
    double? time;
    double? videoDuration;
    try {
      time = await _engineCurrentTime();
      videoDuration = await _engineVideoDuration();
    } catch (e) {
      // CRITICAL: Swallow youtube_player_iframe TypeError so the listener doesn't die.
      debugPrint('Ignored YouTube interop error to keep listener alive: $e');
      time = null;
    }
    final estimated = _estimateEngineTime();
    if (time == null) {
      time = estimated;
    } else if (estimated != null && estimated > time + 0.35) {
      // currentTime stalled/behind while the original kept playing past End.
      time = estimated;
    }
    if (!_engineSessionLive ||
        token != _engineEpoch ||
        _engineSeeking ||
        _engineAdvancing ||
        _isTransitioning ||
        _sectionDelayInFlight ||
        _countingDown) {
      return;
    }
    if (time == null) return;
    try {
      _onEngineTime(time, token, videoDuration: videoDuration ?? _cachedVideoDurationSec);
    } catch (e) {
      debugPrint('Ignored YouTube interop error to keep listener alive: $e');
    }
  }

  Future<double?> _engineCurrentTime() async {
    try {
      final original = _original;
      if (original != null && original.value.isInitialized) {
        return original.value.position.inMilliseconds / 1000.0;
      }
      if (_youtubeOriginal != null) {
        try {
          final time = await _yt((player) => player.currentTime)
              .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
          return time;
        } catch (e) {
          debugPrint('Ignored YouTube interop error to keep listener alive: $e');
          return null;
        }
      }
    } catch (e) {
      debugPrint('Ignored YouTube interop error to keep listener alive: $e');
    }
    return null;
  }

  void _onEngineTime(double time, int token, {double? videoDuration}) {
    if (!_engineSessionLive ||
        token != _engineEpoch ||
        _engineAdvancing ||
        _engineSeeking ||
        _isTransitioning ||
        _sectionDelayInFlight ||
        _countingDown) {
      return;
    }
    if (!_recording && !_virtualRecording && !_audioRecording) return;
    final segments = widget.routine.segments;
    if (_engineSegmentIndex < 0 || _engineSegmentIndex >= segments.length) {
      return;
    }
    final segment = segments[_engineSegmentIndex];
    final effectiveEnd = _effectiveSectionEnd(segment, videoDuration);
    // Near EOF of a Short: treat as section end even if authored endSec is larger.
    final atMediaEof = videoDuration != null &&
        videoDuration > 1 &&
        time >= videoDuration - 0.4;

    if (time < segment.startSec - 1.0 && _engineSegmentIndex > 0) return;
    if (!atMediaEof && time + 0.15 < effectiveEnd) return;

    // Lock IMMEDIATELY so concurrent ticks cannot spawn duplicate delays.
    _isTransitioning = true;
    _engineAdvancing = true;
    _engineSeeking = true;
    _cancelEngineListeners();

    if (atMediaEof || (effectiveEnd - segment.endSec).abs() > 0.2) {
      debugPrint(
        '[LOOPI] section end capped rawEnd=${segment.endSec} '
        'effectiveEnd=$effectiveEnd duration=$videoDuration time=$time',
      );
    }

    final targetLoops = segment.loopCount <= 0 && segment.loopCount != kInfiniteLoop
        ? 1
        : segment.loopCount;
    if (targetLoops == kInfiniteLoop) {
      unawaited(_playEngineSegment(_engineSegmentIndex, epoch: token, resetPlays: false));
      return;
    }

    _engineLoopsCompleted += 1;
    if (_engineLoopsCompleted < targetLoops) {
      // Still looping THIS section only — seek back to start. Keep recording.
      unawaited(_playEngineSegment(_engineSegmentIndex, epoch: token, resetPlays: false));
      return;
    }

    // Single-section practice: section finished → pause original and stop recorder.
    // Do NOT auto-advance to the next section or start its delay countdown.
    debugPrint(
      '[LOOPI] single-section complete '
      '${sectionLabelForIndex(_engineSegmentIndex)} — pause + stop recording',
    );
    _engineActive = false;
    _engineAdvancing = false;
    _engineSeeking = false;
    _isTransitioning = false;
    _sectionDelayInFlight = false;
    final finished = _engineOnFinished;
    _engineOnFinished = null;
    unawaited(_haltOriginalPlayback());
    if (!_stopInProgress && !_processingSave) {
      finished?.call();
    }
  }

  void _stopSegmentEngine() {
    _engineEpoch += 1;
    _engineActive = false;
    _engineAdvancing = false;
    _engineSeeking = false;
    _isTransitioning = false;
    _sectionDelayInFlight = false;
    _countingDown = false;
    _engineOnFinished = null;
    _cancelEngineListeners();
    _stopAmplitudeMonitor();
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _closeOpenIntervalMarker();
    _recordClock.stop();
  }

  void _armMaxRecordingTimer() {
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = Timer(const Duration(seconds: kMaxPracticeRecordingSeconds), () {
      if (!mounted) return;
      if (_recording) {
        unawaited(_toggleRecording());
      } else if (_virtualRecording) {
        _stopVirtualRecording();
      }
    });
  }

  void _startVirtualRecording() {
    _virtualTimer?.cancel();
    _beginRecordClock();
    _armMaxRecordingTimer();
    _recordingDuration.value = 0;
    _virtualRecording = true;
    _recordingUiN.value = true;
    _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_virtualRecording) return;
      _recordingDuration.value += 1;
      if (_recordingDuration.value >= kMaxPracticeRecordingSeconds) {
        _stopVirtualRecording();
      }
    });
    _kickOriginalPlaybackNow();
    unawaited(_beginSegmentEngine(onFinished: () {
      if (_virtualRecording) _stopVirtualRecording();
    }));
  }

  void _stopVirtualRecording() {
    if (_stopInProgress) return;
    unawaited(_stopVirtualRecordingAsync());
  }

  Future<void> _stopVirtualRecordingAsync() async {
    if (_stopInProgress) return;
    _stopInProgress = true;
    await _beginStopProcessing();
    try {
      _virtualTimer?.cancel();
      _virtualTimer = null;
      _stopAmplitudeMonitor();
      _stopSegmentEngine();
      _snapshotCaptureEndOffline();
      _lockPracticeSaveRange();
      _virtualRecording = false;
      _recordingUiN.value = false;
      unawaited(_haltOriginalPlayback());
      await _endStopProcessing();
      if (!mounted) return;
      await _showSaveDialog();
    } catch (error, stack) {
      debugPrint('virtual stop failed: $error\n$stack');
      await _endStopProcessing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 준비에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      _stopInProgress = false;
      _processingSave = false;
      if (mounted) _processingSaveN.value = false;
    }
  }

  Future<void> _showSaveDialog({
    String? recordedPath,
    bool isAudioRecording = false,
    List<int>? recordedBytes,
  }) async {
    if (!mounted) return;
    _saveNameController.text = '${_dateLabel()} ${widget.routine.name} 연습 1';
    String? name;
    if (!mounted) return;
    setState(() => _isOverlayActive = true);
    try {
      name = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) => PointerInterceptor(
          child: AlertDialog(
            title: const Text('연습 영상 저장'),
            content: TextField(
              controller: _saveNameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '파일 이름'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, _saveNameController.text.trim()),
                child: const Text('저장하기'),
              ),
            ],
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('save dialog failed: $error\n$stack');
      // Do NOT dispose _saveNameController here — State.dispose owns it.
      if (!mounted) return;
      setState(() => _isOverlayActive = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isOverlayActive = false);
    if (name == null || name.isEmpty) return;

    await _beginStopProcessing();
    try {
      // Re-lock in case stop path skipped it (e.g. cancel/retry); never fall back to A/0.
      if (_lockedSaveRange == null) {
        _snapshotCaptureEndOffline();
        _lockPracticeSaveRange();
      }
      final range = _savedCaptureRange();
      final sectionIndex = (_recordStartSegmentIndex ?? _userSelectedSegmentIndex)
          .clamp(0, widget.routine.segments.isEmpty ? 0 : widget.routine.segments.length - 1);
      debugPrint(
        '[LOOPI] saving practice startTime=${range.start} endTime=${range.end} '
        'section=${sectionLabelForIndex(sectionIndex)}',
      );
      final playbackRate = widget.routine.segments.isNotEmpty
          ? widget.routine.segments[sectionIndex].speed
          : 1.0;
      // Prefer path-based playback. Reading the full blob here freezes the UI for
      // large takes; bytes can be loaded lazily later for community upload.
      final practicedRoutine = sanitizeRoutineForPractice(widget.routine);
      // Community / showcase routines may not exist in the private library —
      // persist a lightweight copy so Comparison + library reopen can resolve it.
      try {
        await widget.library.update(
          practicedRoutine.copyWith(clearLocalDataBytes: true),
        );
      } catch (e) {
        debugPrint('[LOOPI] ensure practice routine in library ignored: $e');
      }
      final savedResult = PracticeResult(
        id: 'practice_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        routineId: practicedRoutine.id,
        createdAt: DateTime.now(),
        recordedPath: recordedPath,
        recordedDataBytes: recordedBytes,
        startTime: range.start,
        endTime: range.end,
        playbackRate: playbackRate,
        category: practicedRoutine.category,
        intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
        isAudioRecording: isAudioRecording,
        recordedSectionIndex: sectionIndex,
        recordedAspectRatio: _previewAspectRatio,
        sourceRoutine: practicedRoutine.copyWith(clearLocalDataBytes: true),
      );
      await widget.library.savePracticeResult(savedResult);
      if (!mounted) return;
      await _navigateToComparisonPage(
        title: name,
        recordedAudioPath: isAudioRecording ? recordedPath : null,
        recordedMediaPath: recordedPath,
        loopStart: range.start,
        loopEnd: range.end,
        recordedSectionIndex: sectionIndex,
        recordedAspectRatio: _previewAspectRatio,
        // Only the take just recorded — never merge stale A/B/C takes.
        sectionTakesByIndex: {sectionIndex: savedResult},
        sourceRoutine: practicedRoutine,
      );
    } on StorageQuotaExceededException {
      if (mounted) await showStorageQuotaNudge(context);
    } catch (error, stack) {
      debugPrint('save practice failed: $error\n$stack');
      if (mounted) {
        if (StorageQuotaExceededException.matches(error)) {
          await showStorageQuotaNudge(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('저장에 실패했습니다. 다시 시도해 주세요.')),
          );
        }
      }
    } finally {
      await _endStopProcessing();
    }
  }

  /// Hands the already-initialized player controllers off to a standalone
  /// full-screen result page instead of overlaying them on this screen, so
  /// this screen's dispose() must not tear them down afterwards.
  Future<void> _navigateToComparisonPage({
    String? title,
    String? recordedAudioPath,
    String? recordedMediaPath,
    double? loopStart,
    double? loopEnd,
    int? recordedSectionIndex,
    double? recordedAspectRatio,
    Map<int, PracticeResult>? sectionTakesByIndex,
    SavedRoutine? sourceRoutine,
  }) async {
    if (!mounted) return;

    // 1) Unmount CameraPreview BEFORE route change (web EngineFlutterView crash).
    _isNavigating = true;
    _recordingUiN.value = false;
    _virtualTimer?.cancel();
    _virtualTimer = null;
    if (mounted) setState(() {});
    // Two frames so HtmlElementView is fully removed from the tree first.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    // 2) Stop all practice timers / engine so nothing paints into a disposed view.
    _stopEnableTimer?.cancel();
    _stopEnableTimer = null;
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _stopAmplitudeMonitor();
    _stopSegmentEngine();

    // 3) Release camera MediaStream before leaving.
    final camera = _camera;
    _camera = null;
    try {
      await releaseCameraController(camera);
    } catch (e) {
      debugPrint('[LOOPI] camera release on navigate ignored: $e');
    }
    stopOrphanedCameraMediaTracks();
    await WidgetsBinding.instance.endOfFrame;

    final original = _original;
    var recordedOut = _recorded;
    final youtube = _youtubeOriginal;
    _original = null;
    _recorded = null;
    _youtubeOriginal = null;
    try {
      try {
        await original?.pause();
        await recordedOut?.pause();
        await safeYoutubePlayerCallOn(youtube, (player) => player.pauseVideo());
      } catch (_) {}
      final youtubeVideoId = widget.routine.sourceType == SourceType.youtube
          ? resolveYoutubeVideoId(
              videoId: widget.routine.videoId,
              videoUrl: widget.routine.videoUrl,
            )
          : null;
      // Local/mp4 originals must keep their VideoPlayerController — never replace
      // with a YouTube iframe (stale studio default IDs like M7lc1UVf-VE).
      await closeYoutubePlayerSafely(youtube);
      final segments = widget.routine.segments;
      final range = _savedCaptureRange();
      final sectionIndex = (recordedSectionIndex ??
              _recordStartSegmentIndex ??
              _userSelectedSegmentIndex)
          .clamp(0, segments.isEmpty ? 0 : segments.length - 1);
      final savedStart = loopStart ?? range.start;
      final savedEnd = loopEnd ?? range.end;
      final playbackRate = segments.isNotEmpty
          ? segments[sectionIndex].speed
          : 1.0;
      // Prefer an explicit single-take map from the caller; never merge stale takes.
      final sectionTakes = sectionTakesByIndex ??
          (widget.library.practiceResults
                  .where(
                    (r) =>
                        r.routineId == widget.routine.id &&
                        r.recordedSectionIndex == sectionIndex,
                  )
                  .isNotEmpty
              ? {
                  sectionIndex: widget.library.practiceResults.firstWhere(
                    (r) =>
                        r.routineId == widget.routine.id &&
                        r.recordedSectionIndex == sectionIndex,
                  ),
                }
              : <int, PracticeResult>{});
      // Ensure Comparison always receives a VideoPlayerController for the blob.
      final mediaPath = (recordedMediaPath ??
              recordedAudioPath ??
              sectionTakes[sectionIndex]?.recordedPath)
          ?.trim();
      final audioOnly = recordedAudioPath != null &&
          recordedAudioPath.trim().isNotEmpty &&
          (mediaPath == null ||
              mediaPath == recordedAudioPath.trim() ||
              _pathLooksLikeAudioRecording(mediaPath));
      if (recordedOut == null &&
          !audioOnly &&
          mediaPath != null &&
          mediaPath.isNotEmpty) {
        debugPrint('[LOOPI] creating VideoPlayerController from blob path=$mediaPath');
        recordedOut = (kIsWeb ||
                mediaPath.startsWith('blob:') ||
                mediaPath.startsWith('http://') ||
                mediaPath.startsWith('https://'))
            ? VideoPlayerController.networkUrl(Uri.parse(mediaPath))
            : VideoPlayerController.file(File(mediaPath));
      }
      debugPrint(
        '[LOOPI] open comparison source=${widget.routine.sourceType.name} '
        'ytId=$youtubeVideoId hasLocalOriginal=${original != null} '
        'hasRecordedController=${recordedOut != null} '
        'recordedMediaPath=$mediaPath '
        'loopStart=$savedStart loopEnd=$savedEnd '
        'recordedSection=${sectionLabelForIndex(sectionIndex)} '
        'sectionTakes=${sectionTakes.keys.map(sectionLabelForIndex).join(",")}',
      );
      if (!mounted) {
        // Ownership fell through — dispose locally to avoid leaks.
        try {
          await original?.dispose();
        } catch (_) {}
        try {
          await recordedOut?.dispose();
        } catch (_) {}
        return;
      }
      final review = MotionComparisonViewerPage(
        title: title ?? widget.routine.name,
        original: original,
        recorded: recordedOut,
        originalYoutube: null,
        youtubeVideoId: youtubeVideoId,
        sourceType: widget.routine.sourceType,
        segments: segments,
        loopStart: savedStart,
        loopEnd: savedEnd,
        playbackRate: playbackRate,
        intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
        recordedAudioPath: audioOnly ? recordedAudioPath : null,
        recordedSectionIndex: sectionIndex,
        sectionTakesByIndex: sectionTakes,
        originalAspectRatio: originalAspectRatioForRoutine(widget.routine),
        recordedAspectRatio: recordedAspectRatio ?? _previewAspectRatio,
        recordedMediaPath: mediaPath,
        sourceRoutine: sourceRoutine ?? sanitizeRoutineForPractice(widget.routine),
      );
      final openInShell = widget.onOpenInShell;
      if (openInShell != null) {
        // Defer shell swap so this State finishes the current callback cleanly
        // before Home replaces (and disposes) the practice screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          openInShell(review);
        });
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => review),
      );
    } catch (error, stack) {
      debugPrint('navigate to comparison failed: $error\n$stack');
      // Best-effort cleanup if navigation failed after hand-off.
      try {
        await original?.dispose();
      } catch (_) {}
      try {
        await recordedOut?.dispose();
      } catch (_) {}
      unawaited(closeYoutubePlayerSafely(youtube));
      if (!mounted) return;
      _isNavigating = false;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비교 화면으로 이동하지 못했습니다. 보관함에서 다시 열어 주세요.')),
      );
    }
  }

  String _dateLabel() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playComparison() async {
    final recorded = _recorded;
    if (recorded == null || _processingSave) return;
    try {
      final range = _savedCaptureRange();
      final start = Duration(milliseconds: (range.start * 1000).round());
      final original = _original;
      if (original != null) {
        await Future.wait([original.seekTo(start), recorded.seekTo(Duration.zero)]);
        await Future.wait([original.play(), recorded.play()]);
      } else if (_youtubeOriginal != null) {
        await _yt((player) => player.seekTo(seconds: range.start, allowSeekAhead: true));
        await recorded.seekTo(Duration.zero);
        await _yt((player) => player.playVideo());
        await recorded.play();
      } else {
        return;
      }
      _syncTimer?.cancel();
      _recordingTimer?.cancel();
      _virtualTimer?.cancel();
      _stopAmplitudeMonitor();
      _stopSegmentEngine();
      await _haltOriginalPlayback();
      if (!mounted) return;
      await _navigateToComparisonPage();
    } catch (error, stack) {
      debugPrint('play comparison failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비교 재생을 시작하지 못했습니다.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _stopAmplitudeMonitor();
    _stopSegmentEngine();
    _virtualTimer?.cancel();
    _stopEnableTimer?.cancel();
    _maxRecordingTimer?.cancel();
    _recordingTimer?.cancel();
    _syncTimer?.cancel();
    _recordingDuration.dispose();
    _audioLevel.dispose();
    _stopGraceTick.dispose();
    _countingDownN.dispose();
    _countdownLabelN.dispose();
    _recordingUiN.dispose();
    _processingSaveN.dispose();
    _cameraStartingN.dispose();
    _saveNameController.dispose();
    // Strict camera release: await dispose + stop leftover MediaStreamTracks
    // so the browser camera indicator turns off immediately.
    final camera = _camera;
    _camera = null;
    unawaited(releaseCameraController(camera));
    try {
      _original?.dispose();
    } catch (_) {}
    try {
      _recorded?.dispose();
    } catch (_) {}
    unawaited(closeYoutubePlayerSafely(_youtubeOriginal));
    revokeMediaBlobUrl(_originalObjectUrl);
    _originalObjectUrl = null;
    // Do not dispose the AudioRecorder while a stop() may still be settling on web;
    // schedule after microtask so MediaRecorder tracks can finish releasing.
    final recorder = _recorder;
    scheduleMicrotask(() {
      try {
        recorder.dispose();
      } catch (_) {}
      // Extra pass after recorder teardown for any lingering getUserMedia tracks.
      stopOrphanedCameraMediaTracks();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routine.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => closeShellOrPop(context),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: !_loading && _error == null
          ? ListenableBuilder(
              listenable: Listenable.merge([
                _stopGraceTick,
                _recordingUiN,
                _processingSaveN,
                _cameraStartingN,
              ]),
              builder: (context, _) {
                final recordingActive =
                    _recording || _virtualRecording || _audioRecording || _recordingUiN.value;
                final processing = _processingSave || _processingSaveN.value;
                final cameraStarting = _cameraStarting || _cameraStartingN.value;
                return FloatingActionButton(
            // Pre-record countdown disables FAB; mid-record section delay must
            // still allow Stop.
            onPressed: (_countingDown && !_isPracticeRecordingActive) ||
                    _recordArming ||
                    cameraStarting
                ? null
                : recordingActive
                    ? () {
                        if (!_canStopRecording) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('녹화가 준비되는 중입니다. 잠시만 기다려 주세요.'),
                            ),
                          );
                          return;
                        }
                        unawaited(_handleStopPressed());
                      }
                    : _recorded == null
                        ? () => unawaited(_onRecordPressed())
                        : _playComparison,
            backgroundColor: _recorded == null ? Colors.redAccent : LoopiColors.purple,
            tooltip: recordingActive ? '녹화 중지 및 저장' : '녹화 시작',
            child: processing || cameraStarting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Icon(recordingActive ? Icons.stop : Icons.fiber_manual_record),
                );
              },
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Stack(
                  children: [
                    Column(
                      children: [
                        if (widget.routine.segments.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _recordingSegmentTabs(),
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final landscape = constraints.maxWidth > constraints.maxHeight;
                              final original = _originalPane();
                              final camera = _cameraPane();
                              final content = landscape || _isVerticalOriginal
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: original),
                                        const SizedBox(width: 12),
                                        Expanded(child: camera),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(child: original),
                                        const SizedBox(height: 12),
                                        Expanded(child: camera),
                                      ],
                                    );
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                                child: content,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    // YouTube ToS: do not cover the iframe logo/controls with opaque overlays.
                    // Status banners sit above the player row instead of Positioned.fill.
                    ValueListenableBuilder<bool>(
                      valueListenable: _countingDownN,
                      builder: (context, counting, _) {
                        if (!counting) return const SizedBox.shrink();
                        return Positioned(
                          left: 16,
                          right: 16,
                          top: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                              child: ValueListenableBuilder<String>(
                                valueListenable: _countdownLabelN,
                                builder: (context, label, _) {
                                  return Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _cameraStartingN,
                      builder: (context, starting, _) {
                        if (!starting && !_cameraStarting) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: 16,
                          right: 16,
                          bottom: 96,
                          child: Material(
                            color: const Color(0xE6120F1C),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  ),
                                  SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      '녹화 준비 중…',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _processingSaveN,
                      builder: (context, processing, _) {
                        if (!processing && !_processingSave) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: 16,
                          right: 16,
                          bottom: 96,
                          child: Material(
                            color: const Color(0xE6120F1C),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  ),
                                  SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      '녹화 파일을 준비하는 중…',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
    );
  }

  /// User tapped a section chip (A/B/C/…). Only before Record — chips are locked
  /// while recording so metadata cannot drift to a later tap (e.g. Record→E).
  void _onSectionChipSelected(int index, bool selected) {
    if (!selected) return;
    if (_sectionChipsLocked) return;
    if (index < 0 || index >= widget.routine.segments.length) return;
    setState(() {
      _userSelectedSegmentIndex = index;
      _engineSegmentIndex = index;
    });
    debugPrint(
      '[LOOPI] section chip selected idx=$index '
      'label=${sectionLabelForIndex(index)} '
      'startSec=${widget.routine.segments[index].startSec} '
      'endSec=${widget.routine.segments[index].endSec}',
    );
    unawaited(
      _playEngineSegment(
        index,
        previewOnly: true,
        fromUserSelection: true,
      ),
    );
  }

  /// Lets the user pick the target section before Record. Disabled while recording.
  Widget _recordingSegmentTabs() {
    final segments = widget.routine.segments;
    final locked = _sectionChipsLocked;
    // Always highlight the locked/selected practice section (not auto-advance).
    final highlightIndex = _userSelectedSegmentIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!locked)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '섹션을 먼저 선택한 뒤 녹화를 시작하세요',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      sectionLabelForIndex(i),
                      style: TextStyle(
                        color: i == highlightIndex
                            ? Colors.white
                            : (locked ? Theme.of(context).disabledColor : null),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    avatar: segments[i].isHighlight
                        ? const HighlightCrown(size: 12)
                        : null,
                    selected: i == highlightIndex,
                    onSelected: locked ? null : (value) => _onSectionChipSelected(i, value),
                    selectedColor: LoopiColors.purple,
                    side: segments[i].isHighlight
                        ? const BorderSide(color: kHighlightGold, width: 1.6)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  double get _originalAspectRatio {
    if (_original?.value.isInitialized == true) {
      final ratio = _original!.value.aspectRatio;
      if (ratio > 0) return ratio;
    }
    if (widget.routine.videoUrl.toLowerCase().contains('/shorts/')) return 9 / 16;
    return 16 / 9;
  }

  bool get _isVerticalOriginal => _originalAspectRatio < 1;

  Widget _fittedAspect(double ratio, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeRatio = ratio > 0 ? ratio : 16 / 9;
        if (!constraints.maxWidth.isFinite || !constraints.maxHeight.isFinite) {
          return AspectRatio(aspectRatio: safeRatio, child: child);
        }
        var width = constraints.maxWidth;
        var height = width / safeRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * safeRatio;
        }
        return Center(
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }

  Widget _originalPane() {
    if (_originalError != null && _youtubeOriginal == null && _original == null) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(child: Text(_originalError!, style: const TextStyle(color: Colors.white70))),
      );
    }
    if (_youtubeOriginal != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('원본 영상', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _fittedAspect(
                _originalAspectRatio,
                Stack(
                  fit: StackFit.expand,
                  children: [
                    loopiYoutubePlayer(
                      controller: _youtubeOriginal!,
                      aspectRatio: _originalAspectRatio,
                      backgroundColor: Colors.transparent,
                    ),
                    // Web HtmlElementView sits above Flutter hit-testing; block
                    // iframe pointer events while a modal (save dialog) is open.
                    if (_isOverlayActive)
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0x01000000)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _mediaPane('원본 영상', _original);
  }

  Widget _cameraPane() {
    // Completely unmount HtmlElementView / CameraPreview while routing away.
    if (!mounted || _isNavigating) {
      return const SizedBox.shrink();
    }
    final camera = _camera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _audioOnlyMode ? 'player.audio_only_mode'.tr() : '카메라 프리뷰',
          style: const TextStyle(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (_cameraError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _audioOnlyMode
                      ? 'player.audio_only_hint'.tr()
                      : '카메라 초기화 실패: $_cameraError',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
                if (!_audioOnlyMode) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => unawaited(_initCameraSafely()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('카메라 다시 시도'),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: OrientationBuilder(
              builder: (context, orientation) {
                if (_isNavigating || !mounted) {
                  return const SizedBox.shrink();
                }
                final showCamera = camera != null &&
                    camera.value.isInitialized &&
                    !_audioOnlyMode;

                // Dynamic hardware FoV — flip vs device orientation when needed.
                // Never call camera.initialize() on rotate (keeps MediaStream).
                final controllerRatio = showCamera && camera.value.aspectRatio > 0
                    ? camera.value.aspectRatio
                    : kPracticeUiAspectRatio;
                final nativeRatio = nativePreviewAspectRatioFor(
                  controllerAspectRatio: controllerRatio,
                  orientation: orientation,
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (showCamera)
                      Center(
                        child: _StableCameraSlot(
                          key: _cameraPreviewHostKey,
                          freeze: _cameraCaptureLive,
                          orientation: orientation,
                          nativeAspectRatio: nativeRatio,
                          controller: camera,
                        ),
                      )
                    else
                      ValueListenableBuilder<int>(
                        valueListenable: _recordingDuration,
                        builder: (context, seconds, _) {
                          return ValueListenableBuilder<double>(
                            valueListenable: _audioLevel,
                            builder: (context, level, _) {
                              return _AudioOnlyPreview(
                                photoUrl: widget.profilePhotoUrl,
                                recording: _audioRecording || _virtualRecording,
                                seconds: seconds,
                                audioLevel: level,
                              );
                            },
                          );
                        },
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      child: IsolatedRecordingTimer(
                        secondsListenable: _recordingDuration,
                        visibleListenable: _recordingUiN,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _mediaPane(String label, VideoPlayerController? player) {
    final ratio = player?.value.isInitialized == true && player!.value.aspectRatio > 0
        ? player.value.aspectRatio
        : _originalAspectRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: _fittedAspect(
              ratio,
              player?.value.isInitialized == true
                  ? VideoPlayer(player!)
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class MotionComparisonViewer extends StatefulWidget {
  const MotionComparisonViewer({
    super.key,
    required this.original,
    required this.recorded,
    this.segments = const [],
    this.originalYoutube,
    this.originalWidget,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.intervalMarkers = const [],
    this.recordedAudioPath,
    this.recordedSectionIndex,
    this.sectionTakesByIndex = const {},
    this.originalAspectRatio,
    this.recordedAspectRatio,
    this.youtubeVideoId,
  });

  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final List<RoutineSegment> segments;
  final YoutubePlayerController? originalYoutube;
  final Widget? originalWidget;
  final double loopStart;
  final double loopEnd;
  final List<PracticeIntervalMarker> intervalMarkers;
  final String? recordedAudioPath;
  /// Section index that was actually recorded (e.g. D). Unrecorded chips are disabled.
  final int? recordedSectionIndex;
  /// Independent takes keyed by section index (A/B/C…).
  final Map<int, PracticeResult> sectionTakesByIndex;
  /// Prefer 9/16 for Shorts so comparison does not force 16:9 letterboxing.
  final double? originalAspectRatio;
  /// Crop ratio used during CameraPreview practice (must match recording UI).
  final double? recordedAspectRatio;
  final String? youtubeVideoId;

  @override
  State<MotionComparisonViewer> createState() => _MotionComparisonViewerState();
}

class _MotionComparisonViewerState extends State<MotionComparisonViewer> {
  double _position = 0;
  bool _playing = false;
  bool _preparing = true;
  bool _hasInitialSeek = false;
  int _segmentIndex = 0;
  Timer? _loopTimer;
  Timer? _recordedSyncTimer;
  StreamSubscription<YoutubePlayerValue>? _youtubeSub;
  final TransformationController _originalTransformController = TransformationController();
  final TransformationController _recordedTransformController = TransformationController();
  AudioPlayer? _recordedAudio;
  StreamSubscription<Duration>? _audioPosSub;
  Duration _audioDuration = Duration.zero;
  bool _audioReady = false;
  bool _disposing = false;
  bool _loopingBack = false;
  /// Suppress YouTube→recorded drive while we are intentionally seeking chips.
  bool _ignoreYoutubeDrive = false;
  /// Viewer-owned recorded controller when swapping independent section takes.
  VideoPlayerController? _ownedRecorded;
  String? _ownedRecordedPath;
  String? _activeRecordedAudioPath;
  bool _sectionBoundaryHit = false;
  bool _chipInitialized = false;
  bool _segmentSelectInFlight = false;
  int? _lastLoggedSelectIndex;
  /// Throttle UI updates from high-frequency media listeners.
  int _lastUiPositionMs = -1;
  bool? _lastUiPlaying;
  /// Last observed YouTube currentTime — used only to detect loop-back to startSec.
  double? _lastYoutubeTime;
  /// Guards one-shot local play() — ignore YouTube cued/buffering flicker.
  bool _localPlayArmed = false;
  DateTime? _localPlayArmedAt;
  bool _localSeekZeroPending = false;

  VideoPlayerController? get _activeRecorded => _ownedRecorded ?? widget.recorded;

  bool get _youtubeAlive => !_disposing && mounted && widget.originalYoutube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(widget.originalYoutube, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    _playing = false;
    _activeRecordedAudioPath = widget.recordedAudioPath;
    _applyInitialSectionChip(force: true);
    widget.original?.addListener(_onOriginalChanged);
    widget.recorded?.addListener(_onRecordedChanged);
    final youtube = widget.originalYoutube;
    if (youtube != null) {
      _youtubeSub = listenYoutubeStream(
        youtube.stream,
        _onYoutubeChanged,
        isAlive: () => _youtubeAlive,
      );
    }
    _position = _minPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_preparePlayback());
    });
  }

  /// Highlight the recorded section chip (e.g. D), not A/0.
  /// Locked to [recordedSectionIndex] when provided — never overwritten by time scan.
  void _applyInitialSectionChip({bool force = false}) {
    if (_chipInitialized && !force) return;
    final sections = widget.segments;
    var initialIndex = -1;

    final recorded = widget.recordedSectionIndex;
    if (recorded != null && sections.isNotEmpty) {
      initialIndex = recorded.clamp(0, sections.length - 1);
    }
    if (initialIndex < 0) {
      final recordedIndices = _recordedSectionIndices;
      if (recordedIndices.isNotEmpty) {
        initialIndex = recordedIndices.reduce((a, b) => a < b ? a : b);
      }
    }

    // Only fall back to time-based lookup when Practice did not pass a section.
    if (initialIndex < 0 && widget.recordedSectionIndex == null && sections.isNotEmpty) {
      final savedStartTime = widget.loopStart;
      initialIndex = sections.indexWhere(
        (s) => savedStartTime >= s.startSec && savedStartTime < s.endSec,
      );
      if (initialIndex < 0) {
        initialIndex = sections.indexWhere(
          (s) => savedStartTime >= s.startSec && savedStartTime <= s.endSec,
        );
      }
    }
    if (initialIndex < 0) initialIndex = 0;
    _chipInitialized = true;
    if (_segmentIndex == initialIndex) return;
    debugPrint(
      '[LOOPI] comparison chip init savedStart=${widget.loopStart} '
      'recordedSection=${widget.recordedSectionIndex} '
      '→ idx=$initialIndex label=${sections.isEmpty ? "?" : sectionLabelForIndex(initialIndex)}',
    );
    _segmentIndex = initialIndex;
  }

  /// Sections covered by independent takes and/or the explicit recorded index.
  Set<int> get _recordedSectionIndices {
    final out = <int>{};
    out.addAll(widget.sectionTakesByIndex.keys);
    for (final marker in widget.intervalMarkers) {
      out.add(marker.segmentIndex);
    }
    final recorded = widget.recordedSectionIndex;
    if (recorded != null) out.add(recorded);
    if (out.isEmpty && widget.segments.isNotEmpty) {
      final savedStartTime = widget.loopStart;
      final idx = widget.segments.indexWhere(
        (s) => savedStartTime >= s.startSec && savedStartTime < s.endSec,
      );
      if (idx >= 0) {
        out.add(idx);
      } else if (widget.loopStart > 0 || widget.loopEnd > widget.loopStart) {
        out.add(_segmentIndex.clamp(0, widget.segments.length - 1));
      }
    }
    return out;
  }

  void _onYoutubeChanged(YoutubePlayerValue value) {
    // youtube_player_iframe has no PlayerState.ready — use isReady + cued/paused.
    if (!_hasInitialSeek && !_disposing && !_preparing && !_ignoreYoutubeDrive) {
      final state = value.playerState;
      if (state == PlayerState.cued ||
          state == PlayerState.paused ||
          state == PlayerState.playing ||
          state == PlayerState.unStarted ||
          state == PlayerState.buffering) {
        unawaited(_performInitialOriginalSeek());
      }
    }
    // Ignore drive events until the initial cue/seek has settled — otherwise
    // cue→play→pause churn mirrors into setState rebuild loops.
    if (!mounted ||
        _preparing ||
        _disposing ||
        _ignoreYoutubeDrive ||
        !_hasInitialSeek) {
      return;
    }

    final state = value.playerState;

    // Play is owned exclusively by the unified Play button (user gesture).
    // Never auto-start local/YouTube from stream events (breaks web autoplay + dual sync).
    if (state == PlayerState.playing) {
      return;
    }

    // Mirror pause when the user pauses via the YouTube iframe chrome.
    if (state == PlayerState.paused || state == PlayerState.ended) {
      final armedAt = _localPlayArmedAt;
      if (armedAt != null &&
          DateTime.now().difference(armedAt) < const Duration(milliseconds: 800)) {
        return;
      }
      if (_localPlayArmed || _playing) {
        unawaited(_disarmLocalPlay());
      }
    }
  }

  Future<void> _armLocalPlayOnce() async {
    if (_localPlayArmed || _disposing || !mounted) return;
    _localPlayArmed = true;
    _localPlayArmedAt = DateTime.now();
    _sectionBoundaryHit = false;
    try {
      if (_hasRecorded) {
        // Free-run local clip — no seek except explicit loop-back to zero.
        await _activeRecorded?.play();
        await _playRecordedAudio();
      }
      await widget.original?.play();
    } catch (_) {}
    _armSingleSectionBoundaryPoll();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _disarmLocalPlay() async {
    _localPlayArmed = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _recordedSyncTimer?.cancel();
    _recordedSyncTimer = null;
    try {
      await _activeRecorded?.pause();
      await _pauseRecordedAudio();
      await widget.original?.pause();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _mirrorYoutubePauseToRecorded() async {
    await _disarmLocalPlay();
  }

  /// YouTube play → local play ONLY once. Never seek to YouTube absolute time.
  Future<void> _mirrorYoutubePlayToRecorded() async {
    await _armLocalPlayOnce();
  }

  Future<void> _ensureInitialized(VideoPlayerController? controller) async {
    if (controller == null) return;
    await awaitVideoPlayerReady(controller);
  }

  Future<void> _prepareRecordedAudio() async {
    final path = widget.recordedAudioPath?.trim();
    if (path == null || path.isEmpty) return;
    await _recordedAudio?.dispose();
    await _audioPosSub?.cancel();
    final player = AudioPlayer();
    _recordedAudio = player;
    try {
      if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:') || path.startsWith('data:')) {
        await player.setSourceUrl(path);
      } else if (kIsWeb) {
        await player.setSourceUrl(path);
      } else {
        await player.setSourceDeviceFile(path);
      }
      _audioDuration = await player.getDuration() ?? Duration.zero;
      _audioPosSub = player.onPositionChanged.listen((position) {
        if (!mounted || !_hasAudioRecorded || _preparing) return;
        final ms = position.inMilliseconds;
        // Throttle: update UI at most every 250ms (not every audio callback).
        if (_lastUiPositionMs >= 0 && (ms - _lastUiPositionMs).abs() < 250 && _playing) {
          return;
        }
        _lastUiPositionMs = ms;
        final seconds = (ms / 1000.0).clamp(_minPosition, _maxPosition);
        setState(() {
          _position = seconds;
          _playing = true;
        });
        // Section chip is locked to recordedSection — do not time-scan.
      });
      _audioReady = true;
    } catch (error) {
      debugPrint('recorded audio load error: $error');
      _audioReady = false;
    }
  }

  Future<void> _seekRecordedAudio(double seconds) async {
    final player = _recordedAudio;
    if (player == null || !_hasAudioRecorded) return;
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  Future<void> _playRecordedAudio() async {
    await _recordedAudio?.resume();
  }

  Future<void> _pauseRecordedAudio() async {
    await _recordedAudio?.pause();
  }

  Future<void> _preparePlayback() async {
    _preparing = true;
    if (mounted) setState(() => _playing = false);
    try {
      if (_rangeEnd <= _rangeStart) {
        return;
      }
      await _ensureInitialized(widget.original);
      // Audio-only takes: use audio UI. If a VideoPlayerController exists, prefer video
      // even when a companion audio path string is present.
      final hasVideoController = widget.recorded != null || _ownedRecorded != null;
      final preferAudio = !hasVideoController &&
          ((widget.recordedAudioPath?.trim().isNotEmpty ?? false) ||
              _pathLooksLikeAudioRecording(widget.recordedAudioPath));
      if (preferAudio) {
        widget.recorded?.removeListener(_onRecordedChanged);
        _ownedRecorded?.removeListener(_onRecordedChanged);
        _activeRecordedAudioPath = widget.recordedAudioPath?.trim();
        await _prepareRecordedAudio();
      } else {
        // Web blob: trust initialize() without throwing on lagging isInitialized.
        // Audio UI only if initialize() throws or hasError is explicitly true.
        VideoPlayerController? active = _activeRecorded ?? widget.recorded ?? _ownedRecorded;
        try {
          if (widget.recorded != null) {
            await awaitVideoPlayerReady(widget.recorded!);
          }
          if (_ownedRecorded != null) {
            await awaitVideoPlayerReady(_ownedRecorded!);
          }
          active = _activeRecorded ?? widget.recorded ?? _ownedRecorded;
        } catch (error) {
          debugPrint(
            '[LOOPI] recorded video unusable — switching to audio UI ($error)',
          );
          widget.recorded?.removeListener(_onRecordedChanged);
          _ownedRecorded?.removeListener(_onRecordedChanged);
          final fallbackPath = widget.recordedAudioPath?.trim();
          if (fallbackPath != null && fallbackPath.isNotEmpty) {
            _activeRecordedAudioPath = fallbackPath;
            await _prepareRecordedAudio();
          } else {
            try {
              await active?.pause();
            } catch (_) {}
          }
          active = null;
        }

        if (active != null) {
          if (_recordedControllerHasFatalError(active)) {
            debugPrint(
              '[LOOPI] recorded video unusable — switching to audio UI (hasError)',
            );
            widget.recorded?.removeListener(_onRecordedChanged);
            _ownedRecorded?.removeListener(_onRecordedChanged);
            final fallbackPath = widget.recordedAudioPath?.trim();
            if (fallbackPath != null && fallbackPath.isNotEmpty) {
              _activeRecordedAudioPath = fallbackPath;
              await _prepareRecordedAudio();
            }
          } else {
            _debugPrintSavedDuration(active);
            // Show VideoPlayer immediately — HTML5 tag finishes metadata on mount.
            await _prepareRecordedAudio();
          }
        }
      }
      await _waitYoutubeReady();
      // Seek original (YouTube) to absolute saved start; local clip always to 0.
      await _performInitialOriginalSeek(force: true);
      await _seekLocalRecordedToStart();
      await _forcePauseAll();
      // Re-assert recorded section chip after any async prepare side effects.
      _applyInitialSectionChip(force: true);
      if (mounted) {
        setState(() {
          _playing = false;
        });
      }
    } catch (error) {
      debugPrint('comparison prepare error: $error');
      if (mounted) setState(() => _playing = false);
    } finally {
      _preparing = false;
      // Player may become ready only after prepare ends — retry once.
      if (!_hasInitialSeek && widget.originalYoutube != null) {
        unawaited(_performInitialOriginalSeek());
      }
    }
  }

  /// Waits until the iframe reports ready, then seeks once to the saved section start.
  /// Note: youtube_player_iframe has no [PlayerState.ready]; readiness is [PlayerState.cued]
  /// / paused plus an awaited [seekTo] (which blocks on the internal ready completer).
  Future<void> _performInitialOriginalSeek({bool force = false}) async {
    if (!force && _hasInitialSeek) return;
    if (_disposing || !mounted) return;
    final savedStart = _rangeStart;
    try {
      final youtube = widget.originalYoutube;
      if (youtube != null) {
        await _waitYoutubeReady();
        if (_disposing || !mounted) return;
        if (!force && _hasInitialSeek) return;
        // Prefer routine/videoId — never touch controller.metadata/videoData on Web.
        final videoId = (widget.youtubeVideoId ?? '').trim();
        if (videoId.isNotEmpty && savedStart >= 0) {
          await _yt(
            (player) => player.cueVideoById(
              videoId: videoId,
              startSeconds: savedStart,
              endSeconds: _rangeEnd > savedStart ? _rangeEnd : null,
            ),
          ).timeout(const Duration(seconds: 5), onTimeout: () => null);
        }
        await _yt((player) => player.seekTo(seconds: savedStart, allowSeekAhead: true))
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        await _yt((player) => player.pauseVideo())
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        final at = await _yt((player) => player.currentTime)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        if (at != null && savedStart > 1.0 && at < savedStart - 1.0) {
          await _yt((player) => player.seekTo(seconds: savedStart, allowSeekAhead: true))
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          await _yt((player) => player.pauseVideo())
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
        }
      }
      final original = widget.original;
      if (original != null && original.value.isInitialized) {
        await original.seekTo(Duration(milliseconds: (savedStart * 1000).round()));
        await original.pause();
      }
      _hasInitialSeek = true;
      // Do NOT time-scan section chips here — recordedSection stays locked.
    } catch (error) {
      debugPrint('initial original seek failed: $error');
    }
  }

  Future<void> _forcePauseAll() async {
    try {
      await _activeRecorded?.pause();
    } catch (_) {}
    try {
      await _pauseRecordedAudio();
    } catch (_) {}
    try {
      await widget.original?.pause();
    } catch (_) {}
    await _yt((player) => player.pauseVideo());
  }

  Future<void> _waitYoutubeReady() async {
    final youtube = widget.originalYoutube;
    if (youtube == null) return;
    try {
      await youtube.stream
          .firstWhere(
            (value) =>
                value.playerState == PlayerState.playing ||
                value.playerState == PlayerState.paused ||
                value.playerState == PlayerState.cued ||
                value.playerState == PlayerState.unStarted,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  double _aspectRatioOf(VideoPlayerController? player) {
    if (player != null && player.value.isInitialized) {
      final size = player.value.size;
      if (size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
      final ratio = player.value.aspectRatio;
      if (ratio > 0) return ratio;
    }
    return 16 / 9;
  }

  bool _isVerticalPlayer(VideoPlayerController? player) => _aspectRatioOf(player) < 1;

  // The recorded clip spans the whole practice session, so once it's present it
  // becomes the timeline's source of truth instead of the original's own range.
  bool get _hasAudioRecorded =>
      _audioReady && (_activeRecordedAudioPath?.isNotEmpty ?? false);

  bool get _hasRecorded {
    final recorded = _activeRecorded;
    if (recorded != null) {
      // Web: controller present after initialize() is enough — do not require
      // isInitialized/size (DOM mount resolves those). Only fatal hasError drops us.
      if (kIsWeb) {
        return !_recordedControllerHasFatalError(recorded) || _hasAudioRecorded;
      }
      final videoOk = !_recordedVideoLooksUnusable(recorded);
      if (videoOk) return true;
    }
    return _hasAudioRecorded;
  }

  bool get _hasLoopRange => _rangeEnd > _rangeStart;

  double get _rangeStart {
    // Prefer the saved capture window whenever it is usable.
    if (widget.loopEnd > widget.loopStart) return widget.loopStart;
    // Even when end metadata is missing, honor a non-zero saved start (Section E).
    if (widget.loopStart > 0) return widget.loopStart;
    // Recover from markers before falling back to Section A.
    if (widget.intervalMarkers.isNotEmpty && widget.segments.isNotEmpty) {
      var first = widget.intervalMarkers.first;
      for (final marker in widget.intervalMarkers) {
        if ((marker.endOffsetMillis - marker.startOffsetMillis) >= 200) {
          first = marker;
          break;
        }
      }
      return widget.segments[first.segmentIndex.clamp(0, widget.segments.length - 1)].startSec;
    }
    if (widget.segments.isNotEmpty) return widget.segments.first.startSec;
    return 0;
  }

  double get _rangeEnd {
    if (widget.loopEnd > widget.loopStart) return widget.loopEnd;
    if (widget.loopStart > 0 && widget.segments.isNotEmpty) {
      // Find the segment that owns loopStart and use its end as a fallback.
      for (final segment in widget.segments) {
        if (widget.loopStart >= segment.startSec - 0.05 && widget.loopStart < segment.endSec + 0.05) {
          return segment.endSec > widget.loopStart ? segment.endSec : widget.loopStart + 0.5;
        }
      }
    }
    if (widget.intervalMarkers.isNotEmpty && widget.segments.isNotEmpty) {
      final last = widget.intervalMarkers.last;
      final lastSeg = widget.segments[last.segmentIndex.clamp(0, widget.segments.length - 1)];
      final elapsedSec = (last.endOffsetMillis - last.startOffsetMillis) / 1000.0;
      return (lastSeg.startSec + elapsedSec).clamp(lastSeg.startSec, lastSeg.endSec);
    }
    if (widget.segments.isNotEmpty) return widget.segments.last.endSec;
    return _originalMaxPosition;
  }

  double get _originalMaxPosition {
    final original = widget.original;
    if (original?.value.isInitialized == true) {
      return original!.value.duration.inMilliseconds / 1000.0;
    }
    return 1;
  }

  double get _recordedDurationSeconds {
    if (_hasAudioRecorded && _audioDuration.inMilliseconds > 0) {
      final d = _audioDuration.inMilliseconds / 1000.0;
      if (d > 0.25) return d;
    }
    final recorded = _activeRecorded;
    if (recorded != null) {
      try {
        final d = recorded.value.duration.inMilliseconds / 1000.0;
        if (d > 0.25) return d;
      } catch (_) {}
    }
    // Unknown / not ready — never pretend the clip is 1s (that caused instant EOF).
    return 0;
  }

  double get _minPosition => _hasRecorded ? 0.0 : _rangeStart;
  double get _maxPosition {
    if (_hasRecorded) {
      final d = _recordedDurationSeconds;
      // Until metadata settles, allow scrubbing without triggering EOF logic.
      return d > 0.25 ? d : 3600.0;
    }
    return _hasLoopRange ? _rangeEnd : _originalMaxPosition;
  }
  double get _displayMaxPosition {
    if (_hasRecorded) {
      final d = _recordedDurationSeconds;
      return d > 0.25 ? d : 0.0;
    }
    return _maxPosition;
  }

  Future<double> _currentPlaybackSeconds() async {
    if (_hasAudioRecorded) {
      final position = await _recordedAudio?.getCurrentPosition();
      return (position?.inMilliseconds ?? 0) / 1000.0;
    }
    if (_hasRecorded && _activeRecorded != null) {
      return _activeRecorded!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.original != null && widget.original!.value.isInitialized) {
      return widget.original!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.originalYoutube != null) {
      return await _yt((player) => player.currentTime) ?? 0;
    }
    return 0;
  }

  /// Cap authored section.end to real media length (Shorts-safe).
  double _effectiveComparisonSectionEnd(RoutineSegment segment) {
    double? videoDuration;
    // Do not read youtube.metadata on Web (JS interop TypeError).
    final original = widget.original;
    if (original != null && original.value.isInitialized) {
      final d = original.value.duration.inMilliseconds / 1000.0;
      if (d > 1) videoDuration = d;
    }
    if ((videoDuration == null || videoDuration <= 1) &&
        widget.loopEnd > widget.loopStart) {
      videoDuration = widget.loopEnd;
    }
    final rawEnd = segment.endSec;
    final start = segment.startSec;
    if (videoDuration == null || videoDuration <= 1) return rawEnd;
    if (rawEnd >= videoDuration - 0.05) {
      return (videoDuration - 0.35).clamp(start + 0.05, videoDuration);
    }
    if (rawEnd > videoDuration) {
      return (videoDuration - 0.35).clamp(start + 0.05, videoDuration);
    }
    return rawEnd;
  }

  Future<void> _pauseAtSectionEnd() async {
    if (_sectionBoundaryHit) return;
    _sectionBoundaryHit = true;
    debugPrint(
      '[LOOPI] comparison single-section end '
      '${sectionLabelForIndex(_segmentIndex)} — pause',
    );
    await _stopAtSavedEnd();
  }

  Future<void> _stopAtSavedEnd() async {
    _loopTimer?.cancel();
    _loopTimer = null;
    _recordedSyncTimer?.cancel();
    _recordedSyncTimer = null;
    _localPlayArmed = false;
    if (mounted) setState(() => _playing = false);
    try {
      await widget.original?.pause();
      await _activeRecorded?.pause();
      await _pauseRecordedAudio();
      await _yt((player) => player.pauseVideo());
    } catch (_) {}
  }

  void _onRecordedChanged() {
    if (!mounted || !_hasRecorded || _preparing) return;
    final recorded = _activeRecorded;
    if (recorded == null) return;
    // UI scrubber only — NEVER issue pause/play/seek from this listener.
    final position = recorded.value.position.inMilliseconds / 1000.0;
    final bounded = position.clamp(0.0, _maxPosition);
    final playing = recorded.value.isPlaying;
    final ms = (bounded * 1000).round();
    final shouldUpdateUi = _lastUiPlaying != playing ||
        _lastUiPositionMs < 0 ||
        (ms - _lastUiPositionMs).abs() >= 250;
    if (shouldUpdateUi) {
      _lastUiPlaying = playing;
      _lastUiPositionMs = ms;
      setState(() {
        _position = bounded;
        // Do not flip _playing from listener — YouTube drive owns that flag.
      });
    }
  }

  void _onOriginalChanged() {
    if (_preparing) return;
    final original = widget.original;
    if (!mounted || original == null || !original.value.isInitialized) return;
    final position = original.value.position.inMilliseconds / 1000.0;
    if (widget.segments.isNotEmpty) {
      final segment = widget.segments[_segmentIndex.clamp(0, widget.segments.length - 1)];
      final effectiveEnd = _effectiveComparisonSectionEnd(segment);
      if (!_sectionBoundaryHit &&
          original.value.isPlaying &&
          position + 0.12 >= effectiveEnd) {
        unawaited(_pauseAtSectionEnd());
        return;
      }
    }
    if (_hasRecorded) return;
    final bounded = _hasLoopRange ? position.clamp(_rangeStart, _rangeEnd) : position.clamp(0.0, _maxPosition);
    setState(() {
      _position = bounded;
      _playing = original.value.isPlaying;
    });
  }

  /// Maps a position on the recorded clip (0…duration) onto the original timeline.
  double _originalTimeForRecordedProgress(double recordedSeconds) {
    final span = _rangeEnd - _rangeStart;
    if (!_hasRecorded || span <= 0 || _maxPosition <= 0) {
      return recordedSeconds;
    }
    final progress = (recordedSeconds / _maxPosition).clamp(0.0, 1.0);
    return _rangeStart + progress * span;
  }

  /// Finds which routine section owns [originalSeconds]. UI-only — never seeks.
  int _sectionIndexForOriginalTime(double originalSeconds) {
    final segments = widget.segments;
    if (segments.isEmpty) return 0;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      if (isLast) {
        if (originalSeconds >= segment.startSec && originalSeconds <= segment.endSec + 0.05) {
          return i;
        }
      } else if (originalSeconds >= segment.startSec && originalSeconds < segment.endSec) {
        return i;
      }
    }
    // Nearest section if slightly outside bounds (e.g. seek rounding).
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final mid = (segment.startSec + segment.endSec) / 2;
      final dist = (originalSeconds - mid).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  /// Updates the active section chip from playback time.
  /// Disabled when [recordedSectionIndex] is set — overlapping section starts
  /// must never overwrite the Practice-selected chip (e.g. C → A).
  void _syncSegmentHighlight(double originalSeconds) {
    if (widget.recordedSectionIndex != null) return;
    if (widget.segments.isEmpty || !mounted) return;
    var newIndex = _sectionIndexForOriginalTime(originalSeconds);
    final recorded = _recordedSectionIndices;
    if (recorded.isNotEmpty && !recorded.contains(newIndex)) {
      // Stay on a recorded chip — prefer nearest recorded index.
      newIndex = recorded.reduce(
        (a, b) => (a - newIndex).abs() <= (b - newIndex).abs() ? a : b,
      );
    }
    if (newIndex != _segmentIndex) {
      setState(() => _segmentIndex = newIndex);
    }
  }

  /// Local recorded clip always starts at t=0 (relative), never YouTube absolute time.
  Future<void> _seekLocalRecordedToStart() async {
    try {
      await _activeRecorded?.seekTo(Duration.zero);
    } catch (_) {}
    try {
      await _seekRecordedAudio(0);
    } catch (_) {}
    _lastUiPositionMs = 0;
    if (mounted) setState(() => _position = 0);
  }

  /// Seeks both panes.
  ///
  /// CRITICAL: when a recorded clip exists, [seconds] is ALWAYS local clip time
  /// (0…duration). YouTube gets the mapped absolute time. Never the reverse —
  /// never call this with YouTube absolute timestamps while `_hasRecorded`.
  Future<void> _seekBoth(double seconds) async {
    if (_rangeEnd <= _rangeStart && !_hasRecorded) return;
    if (_hasRecorded) {
      final duration = _recordedDurationSeconds;
      final localMax = duration > 0.25 ? duration : 0.0;
      // Clamp to local timeline only — reject absolute YouTube stamps.
      final local = localMax > 0
          ? seconds.clamp(0.0, localMax).toDouble()
          : 0.0;
      if (mounted) setState(() => _position = local);
      try {
        await _activeRecorded?.seekTo(Duration(milliseconds: (local * 1000).round()));
      } catch (_) {}
      await _seekRecordedAudio(local);
      final progress = duration > 0.25 ? (local / duration).clamp(0.0, 1.0) : 0.0;
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      try {
        await widget.original?.seekTo(Duration(milliseconds: (target * 1000).round()));
      } catch (_) {}
      if (widget.originalYoutube != null) {
        await _yt((player) => player.seekTo(seconds: target, allowSeekAhead: true));
      }
    } else {
      final clamped = seconds.clamp(_minPosition, _maxPosition).toDouble();
      if (mounted) setState(() => _position = clamped);
      await widget.original?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
      if (widget.originalYoutube != null) {
        await _yt((player) => player.seekTo(seconds: clamped, allowSeekAhead: true));
      }
    }
  }

  PracticeIntervalMarker? _markerForSegment(int index) {
    if (widget.intervalMarkers.isEmpty) return null;
    if (index < 0 || index >= widget.segments.length) return null;
    final segment = widget.segments[index];
    final letter = sectionLabelForIndex(index);
    for (final marker in widget.intervalMarkers) {
      if (marker.segmentIndex == index ||
          marker.intervalId == segment.id ||
          marker.intervalId == letter) {
        return marker;
      }
    }
    return null;
  }

  /// Loads an independent section take into the "내 동작" player (runtime only).
  Future<void> _ensureSectionTakeLoaded(int index) async {
    final take = widget.sectionTakesByIndex[index];
    if (take == null) return;
    final path = take.recordedPath?.trim();
    if (take.isAudioRecording || _pathLooksLikeAudioRecording(path)) {
      _activeRecordedAudioPath = path;
      if (path != null && path.isNotEmpty) {
        await _prepareRecordedAudioForPath(path);
      }
      return;
    }
    if (path == null || path.isEmpty) return;
    if (_ownedRecordedPath == path && _ownedRecorded != null) {
      if (_recordedControllerHasFatalError(_ownedRecorded!)) {
        _activeRecordedAudioPath = path;
        await _prepareRecordedAudioForPath(path);
      }
      return;
    }
    widget.recorded?.removeListener(_onRecordedChanged);
    _ownedRecorded?.removeListener(_onRecordedChanged);
    final previousOwned = _ownedRecorded;
    try {
      final next = (kIsWeb || path.startsWith('blob:') || path.startsWith('http'))
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      await awaitVideoPlayerReady(next);
      _debugPrintSavedDuration(next);
      if (_recordedControllerHasFatalError(next)) {
        try {
          await next.dispose();
        } catch (_) {}
        _ownedRecorded = null;
        _ownedRecordedPath = null;
        _activeRecordedAudioPath = path;
        await _prepareRecordedAudioForPath(path);
        if (mounted) setState(() {});
        return;
      }
      try {
        await next.pause();
        await next.seekTo(Duration.zero);
      } catch (e) {
        debugPrint('[LOOPI] recorded pause/seek probe ignored: $e');
      }
      _ownedRecorded = next;
      _ownedRecordedPath = path;
      _activeRecordedAudioPath = null;
      next.addListener(_onRecordedChanged);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[LOOPI] load section take failed: $e');
      _activeRecordedAudioPath = path;
      await _prepareRecordedAudioForPath(path);
      if (mounted) setState(() {});
    } finally {
      if (previousOwned != null && !identical(previousOwned, _ownedRecorded)) {
        try {
          await previousOwned.dispose();
        } catch (_) {}
      }
    }
  }

  Future<void> _prepareRecordedAudioForPath(String path) async {
    await _recordedAudio?.dispose();
    await _audioPosSub?.cancel();
    final player = AudioPlayer();
    _recordedAudio = player;
    try {
      if (path.startsWith('http://') ||
          path.startsWith('https://') ||
          path.startsWith('blob:') ||
          path.startsWith('data:')) {
        await player.setSourceUrl(path);
      } else if (kIsWeb) {
        await player.setSourceUrl(path);
      } else {
        await player.setSourceDeviceFile(path);
      }
      _audioDuration = await player.getDuration() ?? Duration.zero;
      _audioReady = true;
    } catch (e) {
      debugPrint('[LOOPI] section audio load failed: $e');
      _audioReady = false;
    }
  }

  /// Single-section comparison: seek+play this section only; pause at effectiveEnd.
  Future<void> _selectSegment(int index) async {
    if (index < 0 || index >= widget.segments.length) return;
    final recorded = _recordedSectionIndices;
    if (recorded.isNotEmpty && !recorded.contains(index)) return;
    if (_segmentSelectInFlight) return;
    _segmentSelectInFlight = true;
    final segment = widget.segments[index];
    if (_segmentIndex != index) {
      setState(() {
        _segmentIndex = index;
        _sectionBoundaryHit = false;
      });
    } else {
      _sectionBoundaryHit = false;
    }

    _ignoreYoutubeDrive = true;
    _loopTimer?.cancel();
    _recordedSyncTimer?.cancel();
    try {
      final start = segment.startSec;
      final effectiveEnd = _effectiveComparisonSectionEnd(segment);
      final end = effectiveEnd > start ? effectiveEnd : null;
      final speed = segment.speed <= 0 ? 1.0 : segment.speed;

      await widget.original?.pause();
      await _yt((player) => player.pauseVideo());
      await _activeRecorded?.pause();
      await _pauseRecordedAudio();
      _localPlayArmed = false;
      if (mounted && _playing) setState(() => _playing = false);

      await _ensureSectionTakeLoaded(index);

      await widget.original?.setPlaybackSpeed(speed);
      await widget.original?.seekTo(Duration(milliseconds: (start * 1000).round()));

      if (widget.originalYoutube != null) {
        final videoId = (widget.youtubeVideoId ?? '').trim();
        try {
          if (videoId.isNotEmpty) {
            await _yt(
              (player) => player.cueVideoById(
                videoId: videoId,
                startSeconds: start,
                endSeconds: end,
              ),
            );
          }
        } catch (e) {
          debugPrint('[LOOPI] comparison cueVideoById ignored: $e');
        }
        try {
          await _yt((player) => player.setPlaybackRate(speed));
        } catch (_) {}
        try {
          await _yt(
            (player) => player.seekTo(seconds: start, allowSeekAhead: true),
          );
        } catch (e) {
          debugPrint('[LOOPI] comparison seekTo($start) ignored: $e');
        }
      }

      // Park both panes at section start / local 0 — stay PAUSED.
      // Simultaneous play is owned exclusively by the Play button gesture.
      await _seekLocalRecordedToStart();

      if (!mounted || _disposing) return;

      try {
        await widget.original?.pause();
        await _yt((player) => player.pauseVideo());
        await _activeRecorded?.pause();
        await _pauseRecordedAudio();
      } catch (_) {}
      _localPlayArmed = false;
      _loopTimer?.cancel();
      _loopTimer = null;
      if (mounted) setState(() => _playing = false);

      if (_lastLoggedSelectIndex != index) {
        _lastLoggedSelectIndex = index;
        debugPrint(
          '[LOOPI] comparison chip → ${sectionLabelForIndex(index)} '
          'start=$start effectiveEnd=$end speed=$speed (paused — tap Play)',
        );
      }
    } catch (e) {
      debugPrint('[LOOPI] comparison selectSegment failed: $e');
    } finally {
      _ignoreYoutubeDrive = false;
      _segmentSelectInFlight = false;
    }
  }

  void _armSingleSectionBoundaryPoll() {
    _loopTimer?.cancel();
    // Poll YouTube ONLY for: (a) loop-back → local seekTo(0) once,
    // (b) section end → pause both once. Never seek local to absolute YT time.
    _loopTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!mounted || !_playing || _loopingBack || _disposing || _sectionBoundaryHit) {
        return;
      }
      if (widget.segments.isEmpty) return;
      final segment = widget.segments[_segmentIndex.clamp(0, widget.segments.length - 1)];
      final effectiveEnd = _effectiveComparisonSectionEnd(segment);
      final sectionStart = segment.startSec;
      double? originalTime;
      try {
        if (widget.originalYoutube != null) {
          originalTime = await _yt((player) => player.currentTime)
              .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
        } else if (widget.original?.value.isInitialized == true) {
          originalTime = widget.original!.value.position.inMilliseconds / 1000.0;
        }
      } catch (_) {}

      if (_hasRecorded && originalTime != null) {
        final last = _lastYoutubeTime;
        _lastYoutubeTime = originalTime;
        // Loop-back: YouTube jumped near startSec → seek LOCAL to 0 exactly once.
        if (last != null &&
            last > sectionStart + 1.5 &&
            originalTime <= sectionStart + 0.85 &&
            !_localSeekZeroPending) {
          _localSeekZeroPending = true;
          debugPrint(
            '[LOOPI] youtube looped to startSec=$sectionStart — local seekTo(0) once',
          );
          await _seekLocalRecordedToStart();
          try {
            if (_localPlayArmed) {
              await _activeRecorded?.play();
              await _playRecordedAudio();
            }
          } catch (_) {}
          _localSeekZeroPending = false;
        }
      }

      // Grace: don't EOF on YouTube end within first second of local arm.
      final armedAt = _localPlayArmedAt;
      if (armedAt != null &&
          DateTime.now().difference(armedAt) < const Duration(seconds: 1)) {
        return;
      }

      if (originalTime != null && originalTime + 0.12 >= effectiveEnd) {
        unawaited(_pauseAtSectionEnd());
        return;
      }

      // Local natural EOF (real duration only) — no YouTube position mapping.
      if (_hasRecorded) {
        final maxPos = _recordedDurationSeconds;
        if (maxPos > 1.0) {
          try {
            final pos = _activeRecorded?.value.position.inMilliseconds ?? 0;
            if (pos / 1000.0 >= maxPos - 0.12) {
              unawaited(_pauseAtSectionEnd());
            }
          } catch (_) {}
        }
      }
    });
  }

  /// Removed continuous sync — local clip free-runs after one-shot play().
  void _startRecordedSync() {
    _recordedSyncTimer?.cancel();
    _recordedSyncTimer = null;
  }

  Future<void> _togglePlayback() async {
    if (_preparing || _disposing) return;

    // PAUSE — both controllers in the same user gesture (no await before).
    if (_playing) {
      _pauseBothControllersSync();
      _localPlayArmed = false;
      _loopTimer?.cancel();
      _loopTimer = null;
      _recordedSyncTimer?.cancel();
      _recordedSyncTimer = null;
      if (mounted) setState(() => _playing = false);
      return;
    }

    // PLAY — both controllers in the same user gesture BEFORE any await.
    // Browser autoplay blocks YouTube if playVideo() runs after awaited seeks.
    _sectionBoundaryHit = false;
    _startBothControllersSync();
    _localPlayArmed = true;
    _localPlayArmedAt = DateTime.now();
    _armSingleSectionBoundaryPoll();
    if (mounted) setState(() => _playing = true);
  }

  /// Fire YouTube + local play on the current call stack (user gesture).
  void _startBothControllersSync() {
    final yt = widget.originalYoutube;
    final recorded = _activeRecorded;
    final original = widget.original;
    try {
      // ignore: unawaited_futures
      yt?.playVideo();
    } catch (e) {
      debugPrint('[LOOPI] youtube playVideo ignored: $e');
    }
    try {
      // ignore: unawaited_futures
      recorded?.play();
    } catch (e) {
      debugPrint('[LOOPI] local play ignored: $e');
    }
    try {
      // ignore: unawaited_futures
      original?.play();
    } catch (_) {}
    unawaited(_playRecordedAudio());
  }

  /// Fire YouTube + local pause on the current call stack (user gesture).
  void _pauseBothControllersSync() {
    final yt = widget.originalYoutube;
    try {
      // ignore: unawaited_futures
      yt?.pauseVideo();
    } catch (_) {}
    try {
      // ignore: unawaited_futures
      _activeRecorded?.pause();
    } catch (_) {}
    try {
      // ignore: unawaited_futures
      widget.original?.pause();
    } catch (_) {}
    unawaited(_pauseRecordedAudio());
  }

  Future<void> _moveSegment(int delta) async {
    if (widget.segments.isEmpty) return;
    final next = (_segmentIndex + delta).clamp(0, widget.segments.length - 1);
    await _selectSegment(next);
  }

  void _resetOriginalZoom() {
    _originalTransformController.value = Matrix4.identity();
  }

  void _resetRecordedZoom() {
    _recordedTransformController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _disposing = true;
    _loopTimer?.cancel();
    _recordedSyncTimer?.cancel();
    _youtubeSub?.cancel();
    _youtubeSub = null;
    widget.original?.removeListener(_onOriginalChanged);
    widget.recorded?.removeListener(_onRecordedChanged);
    _ownedRecorded?.removeListener(_onRecordedChanged);
    unawaited(_audioPosSub?.cancel());
    unawaited(_recordedAudio?.dispose());
    unawaited(_ownedRecorded?.dispose());
    _originalTransformController.dispose();
    _recordedTransformController.dispose();
    super.dispose();
  }

  Widget _segmentTabs() {
    if (widget.segments.length < 2) return const SizedBox.shrink();
    final recorded = _recordedSectionIndices;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.segments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _segmentIndex;
          final enabled = recorded.isEmpty || recorded.contains(index);
          return Opacity(
            opacity: enabled ? 1.0 : 0.38,
            child: ChoiceChip(
              label: IntervalChipLabel(
                label: sectionLabelForIndex(index),
                isHighlight: widget.segments[index].isHighlight,
              ),
              selected: selected,
              // Unrecorded sections cannot be selected.
              onSelected: !enabled
                  ? null
                  : (value) {
                      if (!value) return;
                      unawaited(_selectSegment(index));
                    },
              selectedColor: LoopiColors.purple,
              side: widget.segments[index].isHighlight
                  ? const BorderSide(color: kHighlightGold, width: 1.6)
                  : null,
              labelStyle: TextStyle(
                color: selected ? Colors.white : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        return SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('동작 비교', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _segmentTabs(),
              if (widget.segments.length > 1) const SizedBox(height: 8),
              if (isLandscape || _isVerticalPlayer(widget.original) || _isVerticalPlayer(_activeRecorded))
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(width: 12),
                      Expanded(child: _videoPane('내 동작', _activeRecorded, _recordedAudioWidget(), _recordedTransformController, _resetRecordedZoom)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(height: 12),
                      Expanded(child: _videoPane('내 동작', _activeRecorded, _recordedAudioWidget(), _recordedTransformController, _resetRecordedZoom)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(onPressed: () => _moveSegment(-1), icon: const Icon(Icons.skip_previous), tooltip: '이전 구간'),
                  IconButton(onPressed: () => _seekBoth(_position - 5), icon: const Icon(Icons.replay_5), tooltip: '5초 뒤로'),
                  IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    tooltip: _playing ? '일시정지' : '재생',
                  ),
                  IconButton(onPressed: () => _seekBoth(_position + 5), icon: const Icon(Icons.forward_5), tooltip: '5초 앞으로'),
                  IconButton(onPressed: () => _moveSegment(1), icon: const Icon(Icons.skip_next), tooltip: '다음 구간'),
                ],
              ),
              Row(
                children: [
                  Text(formatMmSs(_position.clamp(_minPosition, _displayMaxPosition)), style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _position.clamp(_minPosition, _displayMaxPosition),
                      min: _minPosition,
                      max: _displayMaxPosition,
                      onChanged: _seekBoth,
                    ),
                  ),
                  Text(formatMmSs(_displayMaxPosition), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _recordedAudioWidget() {
    // Camera / blob video takes always use VideoPlayer — no audio mock overlay.
    if (_activeRecorded != null) return null;
    if (!_hasAudioRecorded) return null;
    return const _AudioOnlyPreview(recording: false);
  }

  Widget _videoPane(String label, VideoPlayerController? player, Widget? customWidget, TransformationController transformController, VoidCallback onResetZoom) {
    final isRecordedPane = label == '내 동작';
    // Recorded pane: prefer VideoPlayer whenever a controller exists.
    final recordedCustom = isRecordedPane ? null : customWidget;
    var playerUsable = player != null;
    if (player != null && isRecordedPane) {
      playerUsable = !_recordedControllerHasFatalError(player);
    } else if (player != null) {
      try {
        playerUsable = player.value.isInitialized;
      } catch (_) {
        playerUsable = true;
      }
    }
    final isFallback = recordedCustom == null && !playerUsable;
    final fallbackText = label == '내 동작'
        ? '녹화 영상을 불러오는 중…'
        : '원본 영상을 불러오는 중입니다...';
    // YouTube original uses customWidget; recorded pane must NEVER treat
    // audio placeholder as "original youtube" ratio path.
    final isOriginalYoutube = !isRecordedPane && customWidget != null;
    // Match practice: outer UI is always 16:9; recorded VideoPlayer uses native ratio.
    final cropRatio = isRecordedPane ? kPracticeUiAspectRatio : null;
    final ratio = isOriginalYoutube
        ? (widget.originalAspectRatio ?? 16 / 9)
        : (cropRatio ?? _aspectRatioOf(player));
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              onPressed: onResetZoom,
              icon: const Icon(Icons.fullscreen_exit, size: 16),
              tooltip: '원복',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ColoredBox(
            color: bg,
            child: InteractiveViewer(
              transformationController: transformController,
              minScale: 1.0,
              maxScale: 4.0,
              child: isFallback
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          fallbackText,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                  : OrientationBuilder(
                      builder: (context, orientation) {
                        if (isRecordedPane && player != null) {
                          double controllerRatio = 16 / 9;
                          try {
                            if (player.value.isInitialized &&
                                player.value.aspectRatio > 0) {
                              controllerRatio = player.value.aspectRatio;
                            }
                          } catch (_) {}
                          final nativeRatio = nativePreviewAspectRatioFor(
                            controllerAspectRatio: controllerRatio,
                            orientation: orientation,
                          );
                          return Center(
                            child: buildOrientationAwareMediaFrame(
                              orientation: orientation,
                              nativeAspectRatio: nativeRatio,
                              child: VideoPlayer(player),
                            ),
                          );
                        }
                        // Original / custom: letterbox only (no cover crop).
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final safeRatio = ratio > 0
                                ? ratio
                                : uiFrameAspectRatioFor(orientation);
                            var frameW = constraints.maxWidth;
                            var frameH = frameW / safeRatio;
                            if (frameH > constraints.maxHeight) {
                              frameH = constraints.maxHeight;
                              frameW = frameH * safeRatio;
                            }
                            if (!frameW.isFinite ||
                                !frameH.isFinite ||
                                frameW <= 0 ||
                                frameH <= 0) {
                              return const SizedBox.shrink();
                            }
                            return Center(
                              child: SizedBox(
                                width: frameW,
                                height: frameH,
                                child: ClipRect(
                                  child: AspectRatio(
                                    aspectRatio: safeRatio,
                                    child: customWidget ?? VideoPlayer(player!),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone full-screen page shown after a practice recording is saved.
/// Reached via [Navigator.pushReplacement] so it fully replaces the recording
/// screen instead of overlaying a small preview on top of it.
class MotionComparisonViewerPage extends StatefulWidget {
  const MotionComparisonViewerPage({
    super.key,
    required this.title,
    this.original,
    this.recorded,
    this.originalYoutube,
    this.youtubeVideoId,
    this.sourceType = SourceType.youtube,
    this.segments = const [],
    this.loopStart = 0,
    this.loopEnd = 0,
    this.playbackRate = 1.0,
    this.intervalMarkers = const [],
    this.recordedAudioPath,
    this.recordedSectionIndex,
    this.sectionTakesByIndex = const {},
    this.originalAspectRatio,
    this.recordedAspectRatio,
    this.recordedMediaPath,
    this.sourceRoutine,
  });

  final String title;
  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final YoutubePlayerController? originalYoutube;
  final String? youtubeVideoId;
  final SourceType sourceType;
  final List<RoutineSegment> segments;
  final double loopStart;
  final double loopEnd;
  final double playbackRate;
  final List<PracticeIntervalMarker> intervalMarkers;
  final String? recordedAudioPath;
  final int? recordedSectionIndex;
  final Map<int, PracticeResult> sectionTakesByIndex;
  final double? originalAspectRatio;
  final double? recordedAspectRatio;
  final String? recordedMediaPath;
  /// Full practiced routine (community showcase included) for reopen / metadata.
  final SavedRoutine? sourceRoutine;

  @override
  State<MotionComparisonViewerPage> createState() => _MotionComparisonViewerPageState();
}

class _MotionComparisonViewerPageState extends State<MotionComparisonViewerPage> {
  final GlobalKey _comparisonSnapshotKey = GlobalKey();
  YoutubePlayerController? _youtube;
  Widget? _youtubePlayerWidget;
  bool _ownsYoutube = false;
  bool _disposing = false;
  bool _hasInitialSeek = false;
  StreamSubscription<YoutubePlayerValue>? _youtubeSub;
  String? _resolvedAudioPath;
  bool _preferAudioUi = false;
  /// Created from [recordedMediaPath] when [widget.recorded] was not handed off.
  VideoPlayerController? _ownedRecorded;
  bool _ownsRecorded = false;

  VideoPlayerController? get _effectiveRecorded =>
      widget.recorded ?? _ownedRecorded;

  bool get _youtubeAlive => !_disposing && mounted && _youtube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtube, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    final mediaPath = widget.recordedMediaPath?.trim();
    final audioPath = widget.recordedAudioPath?.trim();
    // Audio UI only for explicit audio-only takes — never for camera blob videos.
    _preferAudioUi = widget.recorded == null &&
        audioPath != null &&
        audioPath.isNotEmpty &&
        (mediaPath == null ||
            mediaPath == audioPath ||
            _pathLooksLikeAudioRecording(mediaPath));
    _resolvedAudioPath = _preferAudioUi ? (audioPath ?? mediaPath) : null;

    // Restore VideoPlayer from blob:/file path when controller was not passed.
    if (!_preferAudioUi &&
        widget.recorded == null &&
        mediaPath != null &&
        mediaPath.isNotEmpty) {
      debugPrint('[LOOPI] page init VideoPlayer from recordedMediaPath=$mediaPath');
      _ownedRecorded = (kIsWeb ||
              mediaPath.startsWith('blob:') ||
              mediaPath.startsWith('http://') ||
              mediaPath.startsWith('https://'))
          ? VideoPlayerController.networkUrl(Uri.parse(mediaPath))
          : VideoPlayerController.file(File(mediaPath));
      _ownsRecorded = true;
    }

    final useYoutube = widget.sourceType == SourceType.youtube;
    final videoId = useYoutube
        ? resolveYoutubeVideoId(videoId: widget.youtubeVideoId)
        : null;
    if (useYoutube && videoId != null) {
      unawaited(closeYoutubePlayerSafely(widget.originalYoutube));
      final start = widget.loopStart.isFinite ? widget.loopStart.clamp(0, 24 * 3600).toDouble() : 0.0;
      final end = widget.loopEnd.isFinite && widget.loopEnd > start ? widget.loopEnd : null;
      debugPrint('[LOOPI] comparison YT cue id=$videoId startSeconds=$start endSeconds=$end');
      _youtube = createLoopiYoutubeController(
        videoId: videoId,
        autoPlay: false,
        startSeconds: start,
        endSeconds: end,
      );
      _ownsYoutube = true;
      _youtubePlayerWidget = loopiYoutubePlayer(
        controller: _youtube!,
        aspectRatio: widget.originalAspectRatio ?? 16 / 9,
        backgroundColor: Colors.transparent,
      );
      _youtubeSub = listenYoutubeStream(
        _youtube!.stream,
        _onYoutubeReadySeek,
        isAlive: () => _youtubeAlive,
      );
    } else {
      // Local / network mp4 (or audio): never mount a YouTube iframe.
      unawaited(closeYoutubePlayerSafely(widget.originalYoutube));
      _youtube = null;
      _ownsYoutube = false;
      debugPrint(
        '[LOOPI] comparison local original '
        'source=${widget.sourceType.name} hasController=${widget.original != null}',
      );
    }
    unawaited(_prepareRecorded());
    unawaited(_applyRoutinePlaybackRate());
  }

  void _onYoutubeReadySeek(YoutubePlayerValue value) {
    if (_hasInitialSeek || _disposing) return;
    final state = value.playerState;
    // Package has no PlayerState.ready — cued/paused means the iframe accepts seeks.
    if (state == PlayerState.cued ||
        state == PlayerState.paused ||
        state == PlayerState.playing ||
        state == PlayerState.unStarted ||
        state == PlayerState.buffering) {
      unawaited(_seekOriginalOnce());
    }
  }

  double get _savedSectionStart {
    if (widget.loopEnd > widget.loopStart) return widget.loopStart;
    if (widget.loopStart > 0) return widget.loopStart;
    if (widget.segments.isNotEmpty) {
      // Prefer marker-based section over hardcoding A/0.
      if (widget.intervalMarkers.isNotEmpty) {
        var first = widget.intervalMarkers.first;
        for (final marker in widget.intervalMarkers) {
          if ((marker.endOffsetMillis - marker.startOffsetMillis) >= 200) {
            first = marker;
            break;
          }
        }
        return widget.segments[first.segmentIndex.clamp(0, widget.segments.length - 1)].startSec;
      }
      return widget.segments.first.startSec;
    }
    return widget.loopStart;
  }

  Future<void> _seekOriginalOnce({bool force = false}) async {
    if (!force && _hasInitialSeek) return;
    if (!_youtubeAlive && widget.original == null) return;
    final start = _savedSectionStart;
    final videoId = resolveYoutubeVideoId(videoId: widget.youtubeVideoId);
    try {
      if (_youtube != null) {
        try {
          await _youtube!.stream
              .firstWhere(
                (value) =>
                    value.playerState == PlayerState.playing ||
                    value.playerState == PlayerState.paused ||
                    value.playerState == PlayerState.cued ||
                    value.playerState == PlayerState.unStarted ||
                    value.playerState == PlayerState.buffering,
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
        if (_disposing || (!force && _hasInitialSeek)) return;
        // Re-cue at section start so the iframe cannot stay parked at 00:00.
        if (videoId != null && start >= 0) {
          await _yt(
            (player) => player.cueVideoById(
              videoId: videoId,
              startSeconds: start,
              endSeconds: widget.loopEnd > start ? widget.loopEnd : null,
            ),
          ).timeout(const Duration(seconds: 5), onTimeout: () => null);
        }
        await _yt((player) => player.seekTo(seconds: start, allowSeekAhead: true))
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        await _yt((player) => player.pauseVideo())
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
      }
      if (widget.original != null && widget.original!.value.isInitialized) {
        await widget.original!.seekTo(Duration(milliseconds: (start * 1000).round()));
        await widget.original!.pause();
      }
      _hasInitialSeek = true;
    } catch (error) {
      debugPrint('page initial seek failed: $error');
    }
  }

  Future<void> _prepareRecorded() async {
    if (_preferAudioUi) {
      if (mounted) setState(() {});
      return;
    }
    final recorded = _effectiveRecorded;
    if (recorded == null) {
      debugPrint(
        '[LOOPI] comparison has no recorded controller '
        'mediaPath=${widget.recordedMediaPath}',
      );
      return;
    }
    try {
      await awaitVideoPlayerReady(recorded);
    } catch (error) {
      debugPrint('[LOOPI] comparison recorded init failed: $error');
      return;
    }
    if (_recordedControllerHasFatalError(recorded)) {
      debugPrint('[LOOPI] comparison recorded hasError after init');
      return;
    }
    _debugPrintSavedDuration(recorded);
    try {
      await recorded.pause();
      await recorded.seekTo(Duration.zero);
    } catch (error) {
      debugPrint('[LOOPI] recorded pause/seek probe ignored: $error');
    }
    if (mounted) setState(() {});
  }

  /// Prefer audio UI when the take was audio-only or the video blob is a dummy.
  String? get _effectiveRecordedAudioPath {
    if (_preferAudioUi) {
      return _resolvedAudioPath ?? widget.recordedAudioPath?.trim() ?? widget.recordedMediaPath?.trim();
    }
    return widget.recordedAudioPath?.trim();
  }

  Future<void> _applyRoutinePlaybackRate() async {
    if (widget.loopEnd <= widget.loopStart && widget.recorded == null) return;
    try {
      await widget.original?.setPlaybackSpeed(widget.playbackRate);
      await _yt((player) => player.setPlaybackRate(widget.playbackRate))
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      await _seekOriginalOnce(force: true);
    } catch (_) {}
  }

  void _handleBack() {
    closeShellOrPop(context);
  }

  @override
  void dispose() {
    _disposing = true;
    unawaited(_youtubeSub?.cancel());
    _youtubeSub = null;
    widget.original?.dispose();
    widget.recorded?.dispose();
    if (_ownsRecorded) {
      unawaited(_ownedRecorded?.dispose());
      _ownedRecorded = null;
    }
    if (_ownsYoutube) {
      unawaited(closeYoutubePlayerSafely(_youtube));
    } else {
      unawaited(closeYoutubePlayerSafely(widget.originalYoutube));
    }
    super.dispose();
  }

  String? get _activeRecordedPath {
    final explicit = widget.recordedMediaPath?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final idx = widget.recordedSectionIndex;
    if (idx != null) {
      final take = widget.sectionTakesByIndex[idx];
      final path = take?.recordedPath?.trim();
      if (path != null && path.isNotEmpty) return path;
    }
    return widget.recordedAudioPath?.trim();
  }

  void _openExportSheet() {
    ComparisonExport.showOptionsSheet(
      context: context,
      snapshotKey: _comparisonSnapshotKey,
      recordedMediaPath: _activeRecordedPath,
      recordedController: _effectiveRecorded,
      baseFileName: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always pass the real VideoPlayerController for camera takes.
    // Never null it out when an audio path string exists alongside video.
    final recorded = _preferAudioUi ? null : _effectiveRecorded;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        actions: [
          IconButton(
            tooltip: '저장 / 내보내기',
            icon: const Icon(Icons.download_outlined),
            onPressed: _openExportSheet,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RepaintBoundary(
          key: _comparisonSnapshotKey,
          child: MotionComparisonViewer(
            original: widget.original,
            recorded: recorded,
            originalYoutube: _youtube,
            // Cached once in initState — recreating each build re-fires YT stream.
            originalWidget: _youtubePlayerWidget,
            segments: widget.segments,
            loopStart: widget.loopStart,
            loopEnd: widget.loopEnd,
            intervalMarkers: widget.intervalMarkers,
            recordedAudioPath: _preferAudioUi ? _effectiveRecordedAudioPath : null,
            recordedSectionIndex: widget.recordedSectionIndex,
            sectionTakesByIndex: widget.sectionTakesByIndex,
            originalAspectRatio: widget.originalAspectRatio,
            recordedAspectRatio: widget.recordedAspectRatio,
            youtubeVideoId: widget.youtubeVideoId,
          ),
        ),
      ),
    );
  }
}

class PracticeResultViewer extends StatefulWidget {
  const PracticeResultViewer({
    super.key,
    required this.routine,
    required this.result,
    this.sectionTakesByIndex = const {},
  });

  final SavedRoutine routine;
  final PracticeResult result;
  final Map<int, PracticeResult> sectionTakesByIndex;

  @override
  State<PracticeResultViewer> createState() => _PracticeResultViewerState();
}

class _PracticeResultViewerState extends State<PracticeResultViewer> {
  final GlobalKey _practiceResultSnapshotKey = GlobalKey();
  VideoPlayerController? _original;
  VideoPlayerController? _recorded;
  YoutubePlayerController? _youtube;
  String? _recordedObjectUrl;
  String? _originalObjectUrl;
  bool _loading = true;
  String? _loadError;
  bool _disposing = false;
  bool _hasInitialSeek = false;
  StreamSubscription<YoutubePlayerValue>? _youtubeSub;

  bool get _youtubeAlive => !_disposing && mounted && _youtube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtube, action, isAlive: () => _youtubeAlive);
  }

  bool get _hasRecordedFallback =>
      widget.result.recordedPath == null ||
      widget.result.recordedPath!.trim().isEmpty ||
      widget.result.recordedPath!.toLowerCase().contains('virtual') ||
      widget.result.recordedPath!.toLowerCase().contains('dummy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({double start, double end}) get _savedLoopRange {
    final segments = sanitizeRoutineForPractice(widget.routine).segments;
    final markers = widget.result.intervalMarkers;
    final start = widget.result.startTime;
    final end = widget.result.endTime;

    // Recover when saved start was corrupted to 0 but markers/section say otherwise.
    if (markers.isNotEmpty && segments.isNotEmpty) {
      var first = markers.first;
      for (final marker in markers) {
        if ((marker.endOffsetMillis - marker.startOffsetMillis) >= 200) {
          first = marker;
          break;
        }
      }
      final last = markers.last;
      final markerStart = segments[first.segmentIndex.clamp(0, segments.length - 1)].startSec;
      final lastSeg = segments[last.segmentIndex.clamp(0, segments.length - 1)];
      final sectionEnd = lastSeg.endSec > markerStart ? lastSeg.endSec : markerStart + 0.5;
      if (start.abs() < 0.05 && markerStart > 0.05) {
        final recoveredEnd = end > markerStart ? end.clamp(markerStart, sectionEnd) : sectionEnd;
        return (start: markerStart, end: recoveredEnd > markerStart ? recoveredEnd : sectionEnd);
      }
      if (!(end > start)) {
        final elapsedSec = (last.endOffsetMillis - last.startOffsetMillis) / 1000.0;
        final markerEnd = (lastSeg.startSec + elapsedSec).clamp(lastSeg.startSec, lastSeg.endSec);
        if (markerEnd > markerStart) return (start: markerStart, end: markerEnd);
      }
    }

    if (end > start) {
      return (start: start, end: end);
    }

    final fallbackStart = segments.isNotEmpty ? segments.first.startSec : 0.0;
    final fallbackEnd = segments.isNotEmpty ? segments.last.endSec : fallbackStart + 0.5;
    return (start: fallbackStart, end: fallbackEnd > fallbackStart ? fallbackEnd : fallbackStart + 0.5);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final range = _savedLoopRange;
      final loopStart = range.start;
      final loopEnd = range.end;
      if (loopStart >= loopEnd) {
        throw StateError('재생 구간이 비어 있습니다 (start >= end).');
      }

      // Build controllers first, then clear loading so the YouTube iframe can
      // mount. Awaiting "ready" before mount is what caused infinite spinners.
      if (widget.routine.sourceType == SourceType.youtube) {
        final videoId = resolveYoutubeVideoId(
          videoId: widget.routine.videoId,
          videoUrl: widget.routine.videoUrl,
        );
        if (videoId != null) {
          _youtube = createLoopiYoutubeController(
            videoId: videoId,
            autoPlay: false,
            startSeconds: loopStart,
            endSeconds: loopEnd > loopStart ? loopEnd : null,
          );
          _youtubeSub = listenYoutubeStream(
            _youtube!.stream,
            (value) {
              if (_hasInitialSeek || _disposing) return;
              final state = value.playerState;
              if (state == PlayerState.cued ||
                  state == PlayerState.paused ||
                  state == PlayerState.playing ||
                  state == PlayerState.unStarted ||
                  state == PlayerState.buffering) {
                unawaited(_alignYoutubeAfterMount(loopStart));
              }
            },
            isAlive: () => _youtubeAlive,
          );
        } else {
          throw StateError('유튜브 영상 ID를 찾을 수 없습니다.');
        }
      } else if (widget.routine.sourceType == SourceType.localVideo ||
          widget.routine.sourceType == SourceType.audio) {
        if (widget.routine.localDataBytes != null &&
            widget.routine.localDataBytes!.isNotEmpty) {
          _originalObjectUrl = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
          final url = _originalObjectUrl;
          _original = VideoPlayerController.networkUrl(url == null
              ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
              : Uri.parse(url));
          await _original!.initialize().timeout(const Duration(seconds: 8));
          await _original!.setPlaybackSpeed(widget.result.playbackRate);
          await _original!.pause();
          await _original!.seekTo(Duration(milliseconds: (loopStart * 1000).round()));
          _hasInitialSeek = true;
        } else if (widget.routine.localFilePath != null &&
            widget.routine.localFilePath!.trim().isNotEmpty) {
          final path = widget.routine.localFilePath!.trim();
          _original = kIsWeb
              ? VideoPlayerController.networkUrl(Uri.parse(path))
              : VideoPlayerController.file(File(path));
          await _original!.initialize().timeout(const Duration(seconds: 8));
          await _original!.setPlaybackSpeed(widget.result.playbackRate);
          await _original!.pause();
          await _original!.seekTo(Duration(milliseconds: (loopStart * 1000).round()));
          _hasInitialSeek = true;
        } else {
          throw StateError('원본 로컬 영상을 불러올 수 없습니다.');
        }
      } else {
        throw StateError('지원하지 않는 원본 영상 형식입니다.');
      }

      final bytes = widget.result.recordedDataBytes;
      final path = widget.result.recordedPath;
      final treatAsAudio = widget.result.isAudioRecording ||
          _pathLooksLikeAudioRecording(path) ||
          _hasRecordedFallback;
      try {
        if (treatAsAudio) {
          // Audio-only / dummy: skip VideoPlayer to avoid immediate EOF reset.
          _recorded = null;
        } else if (bytes != null && bytes.isNotEmpty) {
          _recordedObjectUrl = createMediaBlobUrl(bytes, 'video/mp4');
          final uri = _recordedObjectUrl == null
              ? Uri.dataFromBytes(bytes, mimeType: 'video/mp4')
              : Uri.parse(_recordedObjectUrl!);
          _recorded = VideoPlayerController.networkUrl(uri);
          await awaitVideoPlayerReady(_recorded!);
        } else if (!_hasRecordedFallback && path != null && path.trim().isNotEmpty) {
          final value = path.trim();
          // Dead web blob: URLs from a prior session cannot be revived.
          if (kIsWeb && value.startsWith('blob:')) {
            _recorded = null;
          } else {
            _recorded = (kIsWeb || value.startsWith('http://') || value.startsWith('https://'))
                ? createCachedNetworkVideo(Uri.parse(value))
                : VideoPlayerController.file(File(value));
            await awaitVideoPlayerReady(_recorded!);
          }
        }
        if (_recorded != null) {
          if (_recordedControllerHasFatalError(_recorded!)) {
            debugPrint('[LOOPI] PracticeResultViewer empty recorded clip — audio UI');
            try {
              await _recorded?.dispose();
            } catch (_) {}
            _recorded = null;
          } else {
            _debugPrintSavedDuration(_recorded!);
            try {
              await _recorded!.pause();
              await _recorded!.seekTo(Duration.zero);
            } catch (e) {
              debugPrint('[LOOPI] recorded pause/seek probe ignored: $e');
            }
          }
        }
      } catch (error) {
        debugPrint('recorded clip load failed: $error');
        try {
          await _recorded?.dispose();
        } catch (_) {}
        _recorded = null;
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // Seek YouTube only after the player widget is in the tree.
      if (_youtube != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_alignYoutubeAfterMount(loopStart));
        });
      }
    } catch (error, stack) {
      debugPrint('PracticeResultViewer load error: $error\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '영상 로드를 실패했습니다.\n${error.toString()}';
        });
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _alignYoutubeAfterMount(double startSeconds) async {
    if (_hasInitialSeek || _disposing) return;
    final youtube = _youtube;
    if (youtube == null || !_youtubeAlive) return;
    final range = _savedLoopRange;
    final videoId = resolveYoutubeVideoId(
      videoId: widget.routine.videoId,
      videoUrl: widget.routine.videoUrl,
    );
    try {
      await youtube.stream
          .firstWhere(
            (value) =>
                value.playerState == PlayerState.playing ||
                value.playerState == PlayerState.paused ||
                value.playerState == PlayerState.cued ||
                value.playerState == PlayerState.unStarted ||
                value.playerState == PlayerState.buffering,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!_youtubeAlive || _hasInitialSeek) return;
    await _yt((player) => player.setPlaybackRate(widget.result.playbackRate))
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (videoId != null) {
      await _yt(
        (player) => player.cueVideoById(
          videoId: videoId,
          startSeconds: startSeconds,
          endSeconds: range.end > startSeconds ? range.end : null,
        ),
      ).timeout(const Duration(seconds: 5), onTimeout: () => null);
    }
    await _yt((player) => player.seekTo(seconds: startSeconds, allowSeekAhead: true))
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    await _yt((player) => player.pauseVideo())
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    final at = await _yt((player) => player.currentTime)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (at != null && startSeconds > 1.0 && at < startSeconds - 1.0 && _youtubeAlive) {
      await _yt((player) => player.seekTo(seconds: startSeconds, allowSeekAhead: true))
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      await _yt((player) => player.pauseVideo())
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    }
    _hasInitialSeek = true;
  }

  Future<void> _retryLoad() async {
    _hasInitialSeek = false;
    unawaited(_youtubeSub?.cancel());
    _youtubeSub = null;
    _original?.dispose();
    _recorded?.dispose();
    await closeYoutubePlayerSafely(_youtube);
    _original = null;
    _recorded = null;
    _youtube = null;
    revokeMediaBlobUrl(_recordedObjectUrl);
    revokeMediaBlobUrl(_originalObjectUrl);
    _recordedObjectUrl = null;
    _originalObjectUrl = null;
    await _load();
  }

  @override
  void dispose() {
    _disposing = true;
    unawaited(_youtubeSub?.cancel());
    _youtubeSub = null;
    _original?.dispose();
    _recorded?.dispose();
    unawaited(closeYoutubePlayerSafely(_youtube));
    revokeMediaBlobUrl(_recordedObjectUrl);
    revokeMediaBlobUrl(_originalObjectUrl);
    _recordedObjectUrl = null;
    _originalObjectUrl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.result.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => closeShellOrPop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 52, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retryLoad,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final safeRoutine = sanitizeRoutineForPractice(widget.routine);
    final markers = widget.result.intervalMarkers;
    int? recordedSectionIndex = widget.result.recordedSectionIndex;
    if (recordedSectionIndex == null && markers.isNotEmpty) {
      var first = markers.first;
      for (final marker in markers) {
        if ((marker.endOffsetMillis - marker.startOffsetMillis) >= 200) {
          first = marker;
          break;
        }
      }
      recordedSectionIndex = first.segmentIndex;
    } else if (recordedSectionIndex == null) {
      final start = widget.result.startTime;
      final idx = safeRoutine.segments.indexWhere(
        (s) => start >= s.startSec && start < s.endSec,
      );
      if (idx >= 0) recordedSectionIndex = idx;
    }

    final sectionTakes = Map<int, PracticeResult>.from(widget.sectionTakesByIndex);
    if (recordedSectionIndex != null) {
      sectionTakes.putIfAbsent(recordedSectionIndex, () => widget.result);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.result.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => closeShellOrPop(context),
        ),
        actions: [
          IconButton(
            tooltip: '저장 / 내보내기',
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              ComparisonExport.showOptionsSheet(
                context: context,
                snapshotKey: _practiceResultSnapshotKey,
                recordedMediaPath: widget.result.recordedPath,
                recordedController: _recorded,
                baseFileName: widget.result.name,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RepaintBoundary(
          key: _practiceResultSnapshotKey,
          child: MotionComparisonViewer(
          original: _original,
          recorded: _recorded,
          segments: safeRoutine.segments,
          originalYoutube: _youtube,
          originalWidget: _youtube == null
              ? null
              : loopiYoutubePlayer(
                  controller: _youtube!,
                  aspectRatio: originalAspectRatioForRoutine(safeRoutine),
                  backgroundColor: Colors.transparent,
                ),
          loopStart: _savedLoopRange.start,
          loopEnd: _savedLoopRange.end,
          intervalMarkers: widget.result.intervalMarkers,
          recordedAudioPath: (widget.result.isAudioRecording ||
                  _recorded == null ||
                  _pathLooksLikeAudioRecording(widget.result.recordedPath))
              ? widget.result.recordedPath
              : null,
          recordedSectionIndex: recordedSectionIndex,
          sectionTakesByIndex: sectionTakes,
          originalAspectRatio: originalAspectRatioForRoutine(safeRoutine),
          recordedAspectRatio: widget.result.recordedAspectRatio,
          youtubeVideoId: resolveYoutubeVideoId(
            videoId: safeRoutine.videoId,
            videoUrl: safeRoutine.videoUrl,
          ),
          ),
        ),
      ),
    );
  }
}

/// Recording clock that updates WITHOUT rebuilding [CameraPreview] parents.
/// Only this leaf listens to [secondsListenable] / [visibleListenable].
class IsolatedRecordingTimer extends StatelessWidget {
  const IsolatedRecordingTimer({
    super.key,
    required this.secondsListenable,
    required this.visibleListenable,
  });

  final ValueListenable<int> secondsListenable;
  final ValueListenable<bool> visibleListenable;

  static String _format(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visibleListenable,
      builder: (context, visible, _) {
        if (!visible) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: secondsListenable,
          builder: (context, seconds, _) {
            return Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    _format(seconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Keeps one [CameraPreview] instance across orientation / layout rebuilds.
/// Outer frame updates on rotate; MediaStream is never re-initialized.
class _StableCameraSlot extends StatefulWidget {
  const _StableCameraSlot({
    super.key,
    required this.freeze,
    required this.orientation,
    required this.nativeAspectRatio,
    required this.controller,
  });

  final bool freeze; // reserved: recording live — never re-init camera on rotate
  final Orientation orientation;
  final double nativeAspectRatio;
  final CameraController controller;

  @override
  State<_StableCameraSlot> createState() => _StableCameraSlotState();
}

class _StableCameraSlotState extends State<_StableCameraSlot> {
  Widget? _frame;
  late Widget _preview;

  @override
  void initState() {
    super.initState();
    _preview = CameraPreview(widget.controller);
    _frame = _buildFrame();
  }

  @override
  void didUpdateWidget(covariant _StableCameraSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(oldWidget.controller, widget.controller);
    if (controllerChanged) {
      // Only recreate preview when the controller instance actually changes.
      // Orientation changes never call controller.initialize().
      _preview = CameraPreview(widget.controller);
    } else if (widget.freeze && identical(_preview.runtimeType, CameraPreview)) {
      // Keep the same CameraPreview instance while MediaRecorder is live.
    }
    final layoutChanged = controllerChanged ||
        oldWidget.orientation != widget.orientation ||
        oldWidget.nativeAspectRatio != widget.nativeAspectRatio ||
        _frame == null;
    // Layout (orientation / FoV) may update even while recording — never
    // call controller.initialize(); only rebuild the AspectRatio wrappers
    // around the same CameraPreview Element.
    if (layoutChanged) {
      _frame = _buildFrame();
    }
  }

  Widget _buildFrame() {
    return RepaintBoundary(
      child: buildOrientationAwareMediaFrame(
        orientation: widget.orientation,
        nativeAspectRatio: widget.nativeAspectRatio,
        child: _preview,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _frame ?? _buildFrame();
  }
}

class _AudioOnlyPreview extends StatelessWidget {
  const _AudioOnlyPreview({
    this.photoUrl,
    this.recording = false,
    this.seconds = 0,
    this.audioLevel = 0,
  });

  final String? photoUrl;
  final bool recording;
  final int seconds;
  final double audioLevel;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl;
    final active = recording && audioLevel > 0.35;
    final opacity = recording ? (active ? 1.0 : 0.5) : 0.5;
    final scale = recording ? (active ? 1.1 : 1.0) : 1.0;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: LoopiColors.purple.withValues(alpha: 0.25),
              backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo == null || photo.isEmpty
                  ? const Icon(Icons.person, color: Colors.white70, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),
            AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.mic,
                  color: recording ? Colors.redAccent : Colors.white70,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recording ? '${seconds}s' : 'player.audio_only_mode'.tr(),
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioPracticeScreen extends StatefulWidget {
  const AudioPracticeScreen({
    super.key,
    required this.routine,
    this.library,
  });

  final SavedRoutine routine;
  final RoutineLibrary? library;

  @override
  State<AudioPracticeScreen> createState() => _AudioPracticeScreenState();
}

class _AudioPracticeScreenState extends State<AudioPracticeScreen> {
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _reviewPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();

  late final ShadowingSequenceController _sequence;
  late final List<ShadowingStep> _steps;

  int _segmentIndex = 0;
  int _stepIndex = 0;
  ShadowingPhase _phase = ShadowingPhase.idle;
  bool _running = false;
  bool _sourceReady = false;
  String? _error;
  String? _recordingPath;
  bool _reviewPlaying = false;

  @override
  void initState() {
    super.initState();
    _sequence = ShadowingSequenceController(widget.routine.segments);
    _steps = _sequence.buildSteps();
    _prepareSource();
  }

  Future<void> _prepareSource() async {
    try {
      await _loadAudioSource(_player).timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _sourceReady = true);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = '오디오를 준비하는 데 시간이 초과되었습니다.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오디오를 준비하는 데 시간이 초과되었습니다.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '오디오를 준비하지 못했습니다: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오디오를 준비하지 못했습니다: $error')),
        );
      }
    }
  }

  Future<void> _loadAudioSource(AudioPlayer player) async {
    final path = widget.routine.localFilePath;
    if (path != null && !kIsWeb) {
      await player.setSourceDeviceFile(path);
    } else if (widget.routine.localDataBytes != null) {
      await player.setSourceBytes(Uint8List.fromList(widget.routine.localDataBytes!));
    } else if (path != null) {
      await player.setSourceUrl(path);
    } else {
      throw StateError('오디오 파일을 찾을 수 없습니다.');
    }
  }

  Future<void> _showMicrophoneError() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('마이크를 사용할 수 없습니다'),
        content: const Text(
          '마이크 권한이 없거나 장치를 사용할 수 없습니다.\n'
          '브라우저/기기 설정에서 마이크 권한을 허용한 뒤 다시 시도해 주세요.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<String> _recordingTargetPath() async {
    if (kIsWeb) {
      // Web uses an in-memory blob; package ignores path but requires a non-empty string on some versions.
      return 'loopi_shadow_${DateTime.now().microsecondsSinceEpoch}.wav';
    }
    final directory = await getTemporaryDirectory();
    return '${directory.path}/loopi_shadow_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  Future<void> _startContinuousRecording() async {
    final path = await _recordingTargetPath();
    final config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
      numChannels: 1,
      sampleRate: 44100,
    );
    await _recorder.start(config, path: path);
  }

  Future<void> _playSegment(RoutineSegment segment) async {
    await _player.setVolume(1);
    await _player.setPlaybackRate(segment.speed <= 0 ? 1.0 : segment.speed);
    await _player.seek(Duration(milliseconds: (segment.startSec * 1000).round()));
    await _player.resume();
  }

  Future<void> _pauseMedia() async {
    try {
      await _player.pause();
      await _player.setVolume(0);
    } catch (_) {}
  }

  Future<void> _jumpToSegment(int index) async {
    if (_running || index < 0 || index >= widget.routine.segments.length) return;
    final segment = widget.routine.segments[index];
    setState(() {
      _segmentIndex = index;
      _phase = ShadowingPhase.idle;
      _error = null;
    });
    try {
      await _player.setVolume(1);
      await _player.setPlaybackRate(segment.speed <= 0 ? 1.0 : segment.speed);
      await _player.seek(Duration(milliseconds: (segment.startSec * 1000).round()));
      await _player.resume();
    } catch (error) {
      if (mounted) setState(() => _error = '구간 이동 실패: $error');
    }
  }

  Future<void> _startShadowing() async {
    if (_running || _steps.isEmpty) return;
    if (!await _recorder.hasPermission()) {
      await _showMicrophoneError();
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _recordingPath = null;
      _reviewPlaying = false;
      _stepIndex = 0;
      _segmentIndex = 0;
      _phase = ShadowingPhase.listening;
    });

    try {
      await _reviewPlayer.stop();
      await _startContinuousRecording();

      for (var i = 0; i < _steps.length; i++) {
        if (!mounted || !_running) return;
        final step = _steps[i];
        setState(() {
          _stepIndex = i;
          _segmentIndex = step.segmentIndex;
          _phase = step.phase;
        });

        if (step.phase == ShadowingPhase.listening) {
          await _playSegment(step.segment);
          await Future<void>.delayed(step.duration);
          await _pauseMedia();
        } else {
          // Speaking/shadowing window: media stays paused/muted for the same interval length.
          await _pauseMedia();
          await Future<void>.delayed(step.duration);
        }
      }

      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _phase = ShadowingPhase.done;
        _recordingPath = path;
        _running = false;
      });
    } catch (error) {
      try {
        await _recorder.stop();
      } catch (_) {}
      await _pauseMedia();
      if (mounted) {
        setState(() {
          _running = false;
          _phase = ShadowingPhase.idle;
          _error = '섀도잉 연습을 완료하지 못했습니다: $error';
        });
      }
    }
  }

  Future<void> _stopEarly() async {
    if (!_running) return;
    setState(() => _running = false);
    try {
      final path = await _recorder.stop();
      await _pauseMedia();
      if (mounted) {
        setState(() {
          _phase = ShadowingPhase.done;
          _recordingPath = path;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '녹음 중지 실패: $error');
    }
  }

  Future<void> _toggleReviewPlayback() async {
    final path = _recordingPath;
    if (path == null || path.isEmpty) return;
    try {
      if (_reviewPlaying) {
        await _reviewPlayer.pause();
        setState(() => _reviewPlaying = false);
        return;
      }
      if (kIsWeb) {
        await _reviewPlayer.play(UrlSource(path));
      } else {
        await _reviewPlayer.play(DeviceFileSource(path));
      }
      setState(() => _reviewPlaying = true);
      _reviewPlayer.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _reviewPlaying = false);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '녹음 재생 실패: $error');
    }
  }

  Future<void> _saveRecording() async {
    final path = _recordingPath;
    if (path == null || widget.library == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장할 녹음이 없거나 라이브러리가 연결되지 않았습니다.')),
        );
      }
      return;
    }
    final bytes = await StorageService.readMediaBytes(path: path);
    final result = PracticeResult(
      id: 'practice_${DateTime.now().microsecondsSinceEpoch}',
      name: '${widget.routine.name} 섀도잉',
      routineId: widget.routine.id,
      createdAt: DateTime.now(),
      recordedPath: path,
      recordedDataBytes: bytes,
      startTime: widget.routine.segments.first.startSec,
      endTime: widget.routine.segments.last.endSec,
      playbackRate: 1.0,
      category: widget.routine.category,
      isAudioRecording: true,
    );
    await widget.library!.savePracticeResult(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('섀도잉 녹음을 저장했습니다.')),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _reviewPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Color get _phaseColor => switch (_phase) {
        ShadowingPhase.listening => LoopiColors.purple,
        ShadowingPhase.speaking => const Color(0xFFE53935),
        ShadowingPhase.done => const Color(0xFF2E7D32),
        ShadowingPhase.idle => LoopiColors.muted,
      };

  String get _phaseTitle => switch (_phase) {
        ShadowingPhase.listening => 'Listening · 원본 듣기',
        ShadowingPhase.speaking => 'Speaking · 따라 말하기',
        ShadowingPhase.done => '완료 · 녹음 확인',
        ShadowingPhase.idle => '준비됨',
      };

  @override
  Widget build(BuildContext context) {
    final segments = widget.routine.segments;
    final segment = segments[_segmentIndex.clamp(0, segments.length - 1)];
    final currentStep = (_running || _phase == ShadowingPhase.done) && _steps.isNotEmpty
        ? _steps[_stepIndex.clamp(0, _steps.length - 1)]
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.name)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF120F1C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _phaseColor.withValues(alpha: 0.55), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _phase == ShadowingPhase.speaking ? Icons.mic : Icons.graphic_eq,
                    color: _phaseColor,
                    size: 64,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _phaseTitle,
                    style: TextStyle(color: _phaseColor, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sectionLabelForIndex(_segmentIndex)}  '
                    '${formatMmSs(segment.startSec)} – ${formatMmSs(segment.endSec)}  '
                    '${formatSpeedLabel(segment.speed)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (currentStep != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '루프 ${currentStep.loopIndex + 1}/${currentStep.loopTotal}'
                      '${_running ? ' · 단계 ${_stepIndex + 1}/${_steps.length}' : ''}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('구간 선택', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: segments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final active = index == _segmentIndex;
                  return ChoiceChip(
                    label: IntervalChipLabel(
                      label: sectionLabelForIndex(index),
                      isHighlight: segments[index].isHighlight,
                    ),
                    selected: active,
                    showCheckmark: false,
                    selectedColor: LoopiColors.deepPurple,
                    side: segments[index].isHighlight
                        ? const BorderSide(color: kHighlightGold, width: 1.6)
                        : null,
                    labelStyle: TextStyle(
                      color: active ? Colors.white : null,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: _running ? null : (_) => _jumpToSegment(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 10),
            ],
            if (!_sourceReady && _error == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            FilledButton.icon(
              onPressed: !_sourceReady
                  ? null
                  : _running
                      ? _stopEarly
                      : _startShadowing,
              icon: Icon(_running ? Icons.stop : Icons.mic),
              style: FilledButton.styleFrom(
                backgroundColor: _running ? Colors.redAccent : LoopiColors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              label: Text(_running ? '녹음 중지' : '섀도잉 연습 시작'),
            ),
            if (_recordingPath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toggleReviewPlayback,
                      icon: Icon(_reviewPlaying ? Icons.pause : Icons.play_arrow),
                      label: Text(_reviewPlaying ? '녹음 일시정지' : '녹음 들어보기'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.library == null ? null : _saveRecording,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('저장'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '연속 녹음: 듣기(원본 재생) → 말하기(같은 길이 대기)를 구간·루프마다 반복합니다.\n'
              '말하기 구간의 대기 시간은 delay 설정이 아니라 현재 구간 길이와 동일합니다.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

