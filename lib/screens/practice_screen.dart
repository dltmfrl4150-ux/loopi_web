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
bool _recordedVideoLooksUnusable(VideoPlayerController? controller) {
  if (controller == null || !controller.value.isInitialized) return true;
  final durationMs = controller.value.duration.inMilliseconds;
  if (durationMs < 250) return true;
  final size = controller.value.size;
  if (size.width < 2 || size.height < 2) return true;
  return false;
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
  double _previewAspectRatio = 9 / 16;
  bool _audioOnlyMode = false;
  bool _audioRecording = false;
  bool _virtualRecording = false;
  int _virtualSeconds = 0;
  Timer? _virtualTimer;
  Timer? _recordingTimer;
  Timer? _maxRecordingTimer;
  final AudioRecorder _recorder = AudioRecorder();
  bool _countingDown = false;
  String _countdownLabel = '';
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
  double _audioLevel = 0;
  double? _captureOriginalEnd;
  /// Segment index where the practice recording actually began (e.g. Section E).
  int? _recordStartSegmentIndex;
  /// Frozen at stop-time so async save/nav cannot lose the section window.
  ({double start, double end})? _lockedSaveRange;

  bool get _youtubeAlive => !_disposing && mounted && _youtubeOriginal != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtubeOriginal, action, isAlive: () => _youtubeAlive);
  }

  static const _aspectRatios = <String, double>{
    '9:16 Shorts / Reels': 9 / 16,
    '16:9 YouTube': 16 / 9,
    '1:1 정사각형': 1,
    '4:3 표준': 4 / 3,
  };

  @override
  void initState() {
    super.initState();
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
    if (mounted) setState(() => _loading = false);
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
          if (mounted) setState(() {});
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
    if (mounted) setState(() {});
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
    // Playback must never depend on camera success. Resolve capture mode first,
    // then always start YouTube, then attempt camera in an isolated try/catch.
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
        await _runCountdown();
        if (mounted) _startVirtualRecording();
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

    await _runCountdown();
    if (!mounted) return;
    await _startPracticeSession(
      preferCamera: useCamera,
      camera: camera,
    );
  }

  /// Starts Practice capture + original playback.
  ///
  /// Order is intentional:
  /// 1) Flip UI to recording
  /// 2) Start YouTube/original immediately (never behind camera await)
  /// 3) Attempt camera in a localized try/catch; on CameraException → audio-only
  Future<void> _startPracticeSession({
    required bool preferCamera,
    CameraController? camera,
  }) async {
    _recording = true;
    _audioOnlyMode = !preferCamera;
    _audioRecording = false;
    _beginRecordClock();
    _recordingTimer?.cancel();
    _armMaxRecordingTimer();
    if (!preferCamera) {
      _virtualSeconds = 0;
      _virtualTimer?.cancel();
      _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && (_audioRecording || _recording)) {
          setState(() => _virtualSeconds += 1);
        }
      });
    }
    if (mounted) setState(() {});

    // 1) GUARANTEED playback — before any camera call.
    unawaited(_beginSegmentEngine(onFinished: () {
      if (!_stopInProgress && !_processingSave) {
        unawaited(_handleStopPressed());
      }
    }));

    // 2) Capture — fully isolated from playback.
    if (preferCamera && camera != null) {
      final cameraOk = await _tryStartCameraRecording(camera);
      if (cameraOk) return;
      // CameraException / timeout: fall through to audio without rethrowing.
      debugPrint('[LOOPI] camera start failed — falling back to audio-only');
    }

    await _tryStartAudioCaptureQuietly();
  }

  /// Localized camera start. Never throws to the caller.
  Future<bool> _tryStartCameraRecording(CameraController camera) async {
    try {
      if (!camera.value.isInitialized) {
        debugPrint('[LOOPI] camera not initialized — skip startVideoRecording');
        return false;
      }
      await camera.startVideoRecording().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('startVideoRecording'),
      );
      _audioOnlyMode = false;
      _audioRecording = false;
      debugPrint('[LOOPI] camera recording started');
      if (mounted) setState(() {});
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
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('카메라 없이 음성만 기록합니다. 원본 영상은 계속 재생됩니다.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[LOOPI] audio capture start ignored: $e');
    }
  }

  /// Stops MediaRecorder with a hard timeout so the preparing overlay cannot
  /// hang forever when the web blob completer never resolves.
  ///
  /// CRITICAL: Never await YouTube `currentTime` / `value` before MediaRecorder
  /// stop — JS-interop TypeErrors can deadlock the Completer and spin forever.
  Future<void> _stopVideoRecordingSafely(CameraController? camera) async {
    // Allow force re-entry when a prior stop left zombie flags (unresponsive Stop).
    if (_stopInProgress || _processingSave) {
      debugPrint(
        '[LOOPI] stop re-entry (stopInProgress=$_stopInProgress '
        'processingSave=$_processingSave recording=$_recording) — forcing unlock',
      );
      _engineAdvancing = false;
      _engineSeeking = false;
      _isTransitioning = false;
      _sectionDelayInFlight = false;
      _cancelEngineListeners();
      _stopInProgress = false;
      _processingSave = false;
    }
    _stopInProgress = true;
    String? recordedPath;
    try {
      if (mounted) setState(() => _processingSave = true);
      // Yield so "녹화 파일을 준비하는 중…" paints before MediaRecorder.stop blocks.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await WidgetsBinding.instance.endOfFrame;

      // Kill polls first so no further YT queries race the stop path.
      _engineAdvancing = false;
      _engineSeeking = false;
      _isTransitioning = false;
      _sectionDelayInFlight = false;
      _stopAmplitudeMonitor();
      _stopSegmentEngine();
      // Offline snapshot only — no YouTube API.
      _snapshotCaptureEndOffline();
      _lockPracticeSaveRange();

      // Isolate MediaRecorder / blob from YouTube entirely.
      try {
        final live = camera ?? _camera;
        if (live != null && live.value.isInitialized && live.value.isRecordingVideo) {
          // Web: stopping tracks first forces MediaRecorder to finalize when
          // there is no video track (otherwise stop can hang ~20s+).
          if (kIsWeb) {
            forceStopActiveCaptureTracks();
            // Brief yield so the browser can emit the final blob chunk.
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          final file = await live.stopVideoRecording().timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () => throw TimeoutException('stopVideoRecording'),
          );
          recordedPath = file.path;
        } else {
          debugPrint(
            '[LOOPI] stopRecording skipped '
            '(cameraNull=${live == null} recording=${live?.value.isRecordingVideo})',
          );
        }
      } catch (error, stack) {
        debugPrint('[LOOPI] MediaRecorder stop isolated failure: $error\n$stack');
        if (error is TimeoutException) {
          // Ensure overlay cannot stay up if the plugin Future is wedged.
          if (kIsWeb) forceStopActiveCaptureTracks();
          rethrow;
        }
      }

      // Web audio-only / no-video-track hangs often leave no path — try mic blob.
      if ((recordedPath == null || recordedPath.isEmpty) && await _recorder.isRecording()) {
        try {
          final audioPath = await _recorder.stop().timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException('recorderStop'),
          );
          if (audioPath != null && audioPath.isNotEmpty) {
            recordedPath = audioPath;
            if (mounted) setState(() => _recording = false);
            unawaited(_haltOriginalPlayback());
            await _endStopProcessing();
            _stopInProgress = false;
            if (!mounted) return;
            await _showSaveDialog(
              recordedPath: recordedPath,
              isAudioRecording: true,
            );
            return;
          }
        } catch (audioError) {
          debugPrint('[LOOPI] audio fallback after video stop failed: $audioError');
        }
      }

      if (mounted) setState(() => _recording = false);

      // Best-effort pause AFTER recorder stopped — never blocks save/finally.
      unawaited(_haltOriginalPlayback());

      if (recordedPath != null && recordedPath.isNotEmpty) {
        // Path-only — do not decode the blob into memory on the stop path.
        await _endStopProcessing();
        _stopInProgress = false;
        if (!mounted) return;
        await _showSaveDialog(
          recordedPath: recordedPath,
          isAudioRecording: _audioOnlyMode || _pathLooksLikeAudioRecording(recordedPath),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹화 파일을 찾지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } on TimeoutException {
      debugPrint('[LOOPI] stopVideoRecording timed out after 1.5s');
      if (mounted) setState(() {
        _recording = false;
        _processingSave = false;
      });
      // Best-effort audio salvage when the camera plugin hangs without a video track.
      String? audioPath;
      try {
        if (await _recorder.isRecording()) {
          audioPath = await _recorder.stop().timeout(const Duration(seconds: 2));
        }
      } catch (_) {}
      if (mounted) {
        if (audioPath != null && audioPath.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('영상 저장이 지연되어 음성만 저장합니다.')),
          );
          await _endStopProcessing();
          _stopInProgress = false;
          await _showSaveDialog(recordedPath: audioPath, isAudioRecording: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('녹화 저장이 시간 초과되었습니다. 다시 시도해 주세요.')),
          );
        }
      }
    } catch (error, stack) {
      debugPrint('stop recording failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹화 저장 준비에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      _stopInProgress = false;
      _recording = false;
      _processingSave = false;
      _engineAdvancing = false;
      _engineSeeking = false;
      if (mounted) setState(() {});
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
      if (_recording) {
        await _stopVideoRecordingSafely(_camera);
      }
    } catch (e, stack) {
      debugPrint('[LOOPI] handleStopPressed failed: $e\n$stack');
      _stopInProgress = false;
      _processingSave = false;
      _recording = false;
      _virtualRecording = false;
      _audioRecording = false;
      if (mounted) setState(() {});
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
          if (mounted) setState(() {});
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
      _virtualSeconds = 0;
      _virtualTimer?.cancel();
      _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _audioRecording) {
          setState(() => _virtualSeconds += 1);
        }
      });
      _beginRecordClock();
      _recordingTimer?.cancel();
      _armMaxRecordingTimer();
      if (mounted) setState(() {});

      // Start YouTube/original immediately — do not await mic start.
      unawaited(_beginSegmentEngine(onFinished: () {
        if (_audioRecording && !_stopInProgress) unawaited(_toggleAudioOnlyRecording());
      }));
      unawaited(() async {
        try {
          await _startPracticeAudioRecording();
          _startAmplitudeMonitor();
        } catch (error) {
          debugPrint('[LOOPI] parallel audio start failed: $error');
          if (mounted) setState(() => _error = '음성 녹화에 실패했습니다: $error');
        }
      }());
    } catch (error) {
      _stopAmplitudeMonitor();
      _audioRecording = false;
      _recording = false;
      if (mounted) setState(() => _error = '음성 녹화에 실패했습니다: $error');
    } finally {
      _stopInProgress = false;
      if (mounted && _processingSave) {
        setState(() => _processingSave = false);
      }
    }
  }

  Future<void> _beginStopProcessing() async {
    if (!mounted) return;
    setState(() => _processingSave = true);
    // Yield so the preparing overlay paints before MediaRecorder work blocks web.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _endStopProcessing() async {
    if (!mounted) {
      _processingSave = false;
      return;
    }
    if (_processingSave) setState(() => _processingSave = false);
  }

  // ignore: unused_element
  Future<void> _attachRecordedFromPath(String path) async {
    final previous = _recorded;
    try {
      final next = (kIsWeb || path.startsWith('blob:') || path.startsWith('http'))
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      _recorded = next;
      await next.initialize().timeout(const Duration(seconds: 8));
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
    if (mounted) setState(() {});
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
    if (mounted) setState(() {});
    for (var i = total; i >= 1; i--) {
      if (!mounted || _stopInProgress || _disposing) {
        _countingDown = false;
        if (mounted) setState(() {});
        return false;
      }
      _countdownLabel = '$i';
      if (mounted) setState(() {});
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted || _stopInProgress || _disposing) {
      _countingDown = false;
      if (mounted) setState(() {});
      return false;
    }
    _countdownLabel = 'START!';
    if (mounted) setState(() {});
    await Future.delayed(const Duration(milliseconds: 500));
    _countingDown = false;
    if (mounted) setState(() {});
    return true;
  }

  bool get _isPracticeRecordingActive =>
      _recording || _virtualRecording || _audioRecording;

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
        if ((normalized - _audioLevel).abs() < 0.04) return;
        setState(() => _audioLevel = normalized);
      },
      onError: (_) {},
    );
  }

  void _stopAmplitudeMonitor() {
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    if (_audioLevel != 0 && mounted) {
      setState(() => _audioLevel = 0);
    } else {
      _audioLevel = 0;
    }
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

  Future<void> _beginSegmentEngine({required VoidCallback onFinished}) async {
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
      'userSelected=$_userSelectedSegmentIndex',
    );
    if (mounted) setState(() {});
    // Warm media duration so Shorts with endSec>duration can still advance.
    unawaited(_engineVideoDuration());
    // Pre-record countdown already consumed the first section's delay.
    await _playEngineSegment(startIndex, epoch: epoch, respectDelay: false);
  }

  Future<void> _playEngineSegment(
    int index, {
    int? epoch,
    bool resetPlays = true,
    bool previewOnly = false,
    bool fromUserSelection = false,
    bool respectDelay = true,
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
    if (mounted) setState(() {});
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
    unawaited(_seekEngineMedia(segment, play: true, token: token));
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
  /// Mirrors Playback mode: cue with endSeconds so YouTube itself stops at End.
  Future<void> _seekEngineMedia(
    RoutineSegment segment, {
    required bool play,
    int? token,
  }) async {
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
            // When play=true, kick playVideo immediately so camera failures
            // elsewhere can never starve original playback.
            if (play) {
              unawaited(
                _yt((player) => player.playVideo())
                    .timeout(const Duration(milliseconds: 800), onTimeout: () => null),
              );
            }
            await _yt((player) => player.setPlaybackRate(segment.speed))
                .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            // Cue with endSeconds — same boundary contract as Playback mode.
            if (videoId != null && videoId.isNotEmpty) {
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
              await _yt((player) => player.playVideo())
                  .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            } else {
              await _yt((player) => player.pauseVideo())
                  .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
            }
          } catch (e) {
            debugPrint('Ignored YouTube interop error to keep listener alive: $e');
            // Last-resort play if cue/seek threw after early play was skipped.
            if (play) {
              unawaited(_yt((player) => player.playVideo()));
            }
          }
        }
      }).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('[LOOPI] engine seek/play timed out — continuing poll');
        },
      );
    } catch (e) {
      debugPrint('[LOOPI] engine seek/play failed: $e');
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
    setState(() {
      _virtualRecording = true;
      _virtualSeconds = 0;
    });
    _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_virtualRecording) return;
      setState(() => _virtualSeconds += 1);
      if (_virtualSeconds >= kMaxPracticeRecordingSeconds) {
        _stopVirtualRecording();
      }
    });
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
      if (mounted) setState(() => _virtualRecording = false);
      unawaited(_haltOriginalPlayback());
      await _endStopProcessing();
      if (mounted) await _showSaveDialog();
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
      if (mounted && _processingSave) {
        setState(() => _processingSave = false);
      }
    }
  }

  Future<void> _showSaveDialog({
    String? recordedPath,
    bool isAudioRecording = false,
    List<int>? recordedBytes,
  }) async {
    if (!mounted) return;
    final controller = TextEditingController(text: '${_dateLabel()} ${widget.routine.name} 연습 1');
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('연습 영상 저장'),
          content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '파일 이름')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('저장하기')),
          ],
        ),
      );
    } catch (error, stack) {
      debugPrint('save dialog failed: $error\n$stack');
      controller.dispose();
      return;
    }
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

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
      await widget.library.savePracticeResult(PracticeResult(
        id: 'practice_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        routineId: widget.routine.id,
        createdAt: DateTime.now(),
        recordedPath: recordedPath,
        recordedDataBytes: recordedBytes,
        startTime: range.start,
        endTime: range.end,
        playbackRate: playbackRate,
        category: widget.routine.category,
        intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
        isAudioRecording: isAudioRecording,
        recordedSectionIndex: sectionIndex,
      ));
      if (!mounted) return;
      await _navigateToComparisonPage(
        title: name,
        recordedAudioPath: isAudioRecording ? recordedPath : null,
        recordedMediaPath: recordedPath,
        loopStart: range.start,
        loopEnd: range.end,
        recordedSectionIndex: sectionIndex,
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
  }) async {
    if (!mounted) return;
    final original = _original;
    final recorded = _recorded;
    final youtube = _youtubeOriginal;
    _original = null;
    _recorded = null;
    _youtubeOriginal = null;
    try {
      try {
        await original?.pause();
        await recorded?.pause();
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
      final sectionTakes =
          widget.library.latestPracticeTakesBySection(widget.routine.id);
      debugPrint(
        '[LOOPI] open comparison source=${widget.routine.sourceType.name} '
        'ytId=$youtubeVideoId hasLocalOriginal=${original != null} '
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
          await recorded?.dispose();
        } catch (_) {}
        return;
      }
      final review = MotionComparisonViewerPage(
        title: title ?? widget.routine.name,
        original: original,
        recorded: recorded,
        originalYoutube: null,
        youtubeVideoId: youtubeVideoId,
        sourceType: widget.routine.sourceType,
        segments: segments,
        loopStart: savedStart,
        loopEnd: savedEnd,
        playbackRate: playbackRate,
        intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
        recordedAudioPath: recordedAudioPath,
        recordedSectionIndex: sectionIndex,
        sectionTakesByIndex: sectionTakes,
        originalAspectRatio: originalAspectRatioForRoutine(widget.routine),
        recordedMediaPath: recordedMediaPath ??
            recordedAudioPath ??
            sectionTakes[sectionIndex]?.recordedPath,
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
        await recorded?.dispose();
      } catch (_) {}
      unawaited(closeYoutubePlayerSafely(youtube));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비교 화면으로 이동하지 못했습니다. 보관함에서 다시 열어 주세요.')),
        );
      }
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
    _maxRecordingTimer?.cancel();
    _recordingTimer?.cancel();
    _syncTimer?.cancel();
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
          ? FloatingActionButton(
            // Pre-record countdown disables FAB; mid-record section delay must
            // still allow Stop.
            onPressed: (_countingDown && !_isPracticeRecordingActive)
                ? null
                : (_recording || _virtualRecording || _audioRecording)
                    ? () => unawaited(_handleStopPressed())
                    : _recorded == null
                        ? _toggleRecording
                        : _playComparison,
            backgroundColor: _recorded == null ? Colors.redAccent : LoopiColors.purple,
            tooltip: _virtualRecording || _recording ? '녹화 중지 및 저장' : '녹화 시작',
            child: _processingSave
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Icon(_virtualRecording || _recording ? Icons.stop : Icons.fiber_manual_record),
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
                    if (_countingDown)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 8,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                            child: Text(
                              _countdownLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                    if (_processingSave)
                      Positioned(
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
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: segments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final selected = index == highlightIndex;
              return ChoiceChip(
                label: IntervalChipLabel(
                  label: sectionLabelForIndex(index),
                  isHighlight: segments[index].isHighlight,
                ),
                selected: selected,
                onSelected: locked ? null : (value) => _onSectionChipSelected(index, value),
                selectedColor: LoopiColors.purple,
                side: segments[index].isHighlight
                    ? const BorderSide(color: kHighlightGold, width: 1.6)
                    : null,
                labelStyle: TextStyle(
                  color: selected
                      ? Colors.white
                      : (locked ? Theme.of(context).disabledColor : null),
                  fontWeight: FontWeight.w700,
                ),
              );
            },
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
                loopiYoutubePlayer(
                  controller: _youtubeOriginal!,
                  aspectRatio: _originalAspectRatio,
                  backgroundColor: Colors.transparent,
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
    final camera = _camera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _audioOnlyMode ? 'player.audio_only_mode'.tr() : '카메라 프리뷰',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            DropdownButton<double>(
              value: _previewAspectRatio,
              isDense: true,
              items: [
                for (final entry in _aspectRatios.entries)
                  DropdownMenuItem(value: entry.value, child: Text(entry.key)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _previewAspectRatio = value);
              },
            ),
          ],
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
            color: Theme.of(context).scaffoldBackgroundColor,
            child: _fittedAspect(
              _previewAspectRatio,
              camera == null || !camera.value.isInitialized
                  ? _AudioOnlyPreview(
                      photoUrl: widget.profilePhotoUrl,
                      recording: _audioRecording || _virtualRecording,
                      seconds: _virtualSeconds,
                      audioLevel: _audioLevel,
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: camera.value.previewSize?.height ?? 320,
                            height: camera.value.previewSize?.width ?? 480,
                            child: CameraPreview(camera),
                          ),
                        ),
                        if (_virtualRecording)
                          DecoratedBox(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                '$_virtualSeconds초',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
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
  /// Runs once unless [force] — avoids rebuild loops from prepare/listeners.
  void _applyInitialSectionChip({bool force = false}) {
    if (_chipInitialized && !force) return;
    final sections = widget.segments;
    final recordedIndices = _recordedSectionIndices;
    var initialIndex = -1;

    final recorded = widget.recordedSectionIndex;
    if (recorded != null && sections.isNotEmpty) {
      initialIndex = recorded.clamp(0, sections.length - 1);
    }
    if (initialIndex < 0 && recordedIndices.isNotEmpty) {
      initialIndex = recordedIndices.reduce((a, b) => a < b ? a : b);
    }

    final savedStartTime = widget.loopStart;
    if (initialIndex < 0 && sections.isNotEmpty) {
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
      '[LOOPI] comparison chip init savedStart=$savedStartTime '
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
    // Keep local recorded video in lockstep when the user taps YouTube to pan/zoom (pauses).
    if (state == PlayerState.paused ||
        state == PlayerState.cued ||
        state == PlayerState.ended) {
      if (_playing) {
        unawaited(_mirrorYoutubePauseToRecorded());
      }
      return;
    }
    if (state == PlayerState.playing) {
      if (!_playing) {
        unawaited(_mirrorYoutubePlayToRecorded());
      }
    }
  }

  Future<void> _mirrorYoutubePauseToRecorded() async {
    try {
      await _activeRecorded?.pause();
      await _pauseRecordedAudio();
      await widget.original?.pause();
    } catch (_) {}
    _loopTimer?.cancel();
    _loopTimer = null;
    _recordedSyncTimer?.cancel();
    _recordedSyncTimer = null;
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _mirrorYoutubePlayToRecorded() async {
    try {
      if (_hasRecorded) {
        await _activeRecorded?.play();
        await _playRecordedAudio();
      }
      await widget.original?.play();
    } catch (_) {}
    if (_hasRecorded) _startRecordedSync();
    _armSingleSectionBoundaryPoll();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _ensureInitialized(VideoPlayerController? controller) async {
    if (controller == null) return;
    if (!controller.value.isInitialized) {
      await controller.initialize().timeout(const Duration(seconds: 8));
    }
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
        _syncSegmentHighlight(_originalTimeForRecordedProgress(seconds));
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
      // Audio-only / empty camera blob: never drive timeline from VideoPlayer (EOF reset).
      final preferAudio = (widget.recordedAudioPath?.trim().isNotEmpty ?? false) ||
          _pathLooksLikeAudioRecording(widget.recordedAudioPath);
      if (preferAudio) {
        widget.recorded?.removeListener(_onRecordedChanged);
        _ownedRecorded?.removeListener(_onRecordedChanged);
        _activeRecordedAudioPath = widget.recordedAudioPath?.trim();
        await _prepareRecordedAudio();
      } else {
        await _ensureInitialized(widget.recorded);
        await _ensureInitialized(_ownedRecorded);
        if (_recordedVideoLooksUnusable(_activeRecorded)) {
          debugPrint('[LOOPI] recorded video unusable — switching to audio UI');
          widget.recorded?.removeListener(_onRecordedChanged);
          _ownedRecorded?.removeListener(_onRecordedChanged);
          final fallbackPath = widget.recordedAudioPath?.trim();
          if (fallbackPath != null && fallbackPath.isNotEmpty) {
            _activeRecordedAudioPath = fallbackPath;
            await _prepareRecordedAudio();
          } else {
            // Treat as no recorded media rather than looping a 0.1s dummy.
            try {
              await _activeRecorded?.pause();
            } catch (_) {}
          }
        } else {
          await _prepareRecordedAudio();
        }
      }
      await _waitYoutubeReady();
      // Seek original to the saved section start BEFORE any play, then force both paused.
      await _performInitialOriginalSeek(force: true);
      await _seekBoth(_minPosition);
      await _forcePauseAll();
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
      _syncSegmentHighlight(savedStart);
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
    final videoOk = recorded != null &&
        recorded.value.isInitialized &&
        !_recordedVideoLooksUnusable(recorded);
    return videoOk || _hasAudioRecorded;
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
      return _audioDuration.inMilliseconds / 1000.0;
    }
    final recorded = _activeRecorded;
    if (recorded != null && recorded.value.isInitialized) {
      return recorded.value.duration.inMilliseconds / 1000.0;
    }
    return 1;
  }

  double get _minPosition => _hasRecorded ? 0.0 : _rangeStart;
  double get _maxPosition => _hasRecorded ? _recordedDurationSeconds : (_hasLoopRange ? _rangeEnd : _originalMaxPosition);
  double get _displayMaxPosition => _maxPosition;

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
    final position = recorded.value.position.inMilliseconds / 1000.0;
    final bounded = position.clamp(_minPosition, _maxPosition);
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
        _playing = playing;
      });
    }
    // Single-section take: pause when the recorded clip itself ends.
    if (!_loopingBack &&
        !_sectionBoundaryHit &&
        position >= _maxPosition - 0.12 &&
        recorded.value.isPlaying) {
      unawaited(_pauseAtSectionEnd());
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

  /// Updates the active section chip from playback time. Must NOT call seek/play.
  /// Never highlight an unrecorded section chip.
  void _syncSegmentHighlight(double originalSeconds) {
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

  Future<void> _seekBoth(double seconds) async {
    if (_rangeEnd <= _rangeStart && !_hasRecorded) return;
    final clamped = seconds.clamp(_minPosition, _maxPosition).toDouble();
    if (mounted) setState(() => _position = clamped);
    if (_hasRecorded) {
      await _activeRecorded?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
      await _seekRecordedAudio(clamped);
      final progress = _maxPosition > 0 ? (clamped / _maxPosition).clamp(0.0, 1.0) : 0.0;
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      await widget.original?.seekTo(Duration(milliseconds: (target * 1000).round()));
      if (widget.originalYoutube != null) {
        await _yt((player) => player.seekTo(seconds: target, allowSeekAhead: true));
      }
    } else {
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
    if (_ownedRecordedPath == path && _ownedRecorded?.value.isInitialized == true) {
      if (_recordedVideoLooksUnusable(_ownedRecorded)) {
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
      await next.initialize().timeout(const Duration(seconds: 8));
      if (_recordedVideoLooksUnusable(next)) {
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
      await next.pause();
      await next.seekTo(Duration.zero);
      _ownedRecorded = next;
      _ownedRecordedPath = path;
      _activeRecordedAudioPath = null;
      next.addListener(_onRecordedChanged);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[LOOPI] load section take failed: $e');
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

      // Independent section take: always start recorded clip at 0.
      await _activeRecorded?.seekTo(Duration.zero);
      await _seekRecordedAudio(0);
      _lastUiPositionMs = 0;
      if (mounted) setState(() => _position = 0);

      if (!mounted || _disposing) return;

      try {
        await widget.original?.play();
        await _yt((player) => player.playVideo());
        await _activeRecorded?.play();
        await _playRecordedAudio();
      } catch (e) {
        debugPrint('[LOOPI] comparison auto-play ignored: $e');
      }
      _armSingleSectionBoundaryPoll();
      if (_hasRecorded) _startRecordedSync();
      if (mounted) setState(() => _playing = true);
      if (_lastLoggedSelectIndex != index) {
        _lastLoggedSelectIndex = index;
        debugPrint(
          '[LOOPI] comparison chip → ${sectionLabelForIndex(index)} '
          'start=$start effectiveEnd=$end speed=$speed',
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
    _loopTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!mounted || !_playing || _loopingBack || _disposing || _sectionBoundaryHit) {
        return;
      }
      if (widget.segments.isEmpty) return;
      final segment = widget.segments[_segmentIndex.clamp(0, widget.segments.length - 1)];
      final effectiveEnd = _effectiveComparisonSectionEnd(segment);
      double? originalTime;
      try {
        if (widget.originalYoutube != null) {
          originalTime = await _yt((player) => player.currentTime)
              .timeout(const Duration(milliseconds: 400), onTimeout: () => null);
        } else if (widget.original?.value.isInitialized == true) {
          originalTime = widget.original!.value.position.inMilliseconds / 1000.0;
        }
      } catch (_) {}
      if (originalTime != null && originalTime + 0.12 >= effectiveEnd) {
        unawaited(_pauseAtSectionEnd());
        return;
      }
      // Independent take: also stop when recorded clip ends.
      if (_hasRecorded) {
        final current = await _currentPlaybackSeconds();
        if (current >= _maxPosition - 0.12) {
          unawaited(_pauseAtSectionEnd());
        }
      }
    });
  }

  /// Optional soft highlight sync only — never force-seek every tick (that caused
  /// 1s stuttering on partial trims). Position is driven by the recorded clip.
  void _startRecordedSync() {
    _recordedSyncTimer?.cancel();
    if (!_hasRecorded) return;
    _recordedSyncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted || !_hasRecorded || !_playing || _disposing || _loopingBack) return;
      final recorded = _activeRecorded;
      if (_hasAudioRecorded) {
        final durationMs = _audioDuration.inMilliseconds;
        if (durationMs <= 0) return;
        final position = await _recordedAudio?.getCurrentPosition();
        final progress = ((position?.inMilliseconds ?? 0) / durationMs).clamp(0.0, 1.0);
        if (progress >= 0.98) unawaited(_pauseAtSectionEnd());
        return;
      }
      if (recorded == null) return;
      final durationMs = recorded.value.duration.inMilliseconds;
      if (durationMs <= 0) return;
      final progress = (recorded.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
      if (progress >= 0.98) unawaited(_pauseAtSectionEnd());
    });
  }

  Future<void> _togglePlayback() async {
    if (_preparing || _disposing) return;
    if (_playing) {
      await _forcePauseAll();
      _loopTimer?.cancel();
      _loopTimer = null;
      _recordedSyncTimer?.cancel();
      _recordedSyncTimer = null;
      if (mounted) setState(() => _playing = false);
      return;
    }

    // Resume current section from its start (single-section playback).
    _sectionBoundaryHit = false;
    if (widget.segments.isNotEmpty) {
      await _selectSegment(_segmentIndex.clamp(0, widget.segments.length - 1));
      return;
    }

    await _seekBoth(_position.clamp(_minPosition, _maxPosition));
    await _forcePauseAll();
    _armSingleSectionBoundaryPoll();
    if (_hasRecorded) _startRecordedSync();

    final starts = <Future<void>>[];
    final recorded = _activeRecorded;
    if (recorded != null && recorded.value.isInitialized) {
      starts.add(recorded.play());
    }
    if (_hasAudioRecorded) {
      starts.add(_playRecordedAudio());
    }
    if (widget.original != null && widget.original!.value.isInitialized) {
      starts.add(widget.original!.play());
    }
    if (widget.originalYoutube != null) {
      starts.add(() async {
        await _yt((player) => player.playVideo());
      }());
    }
    if (starts.isNotEmpty) {
      await Future.wait(starts.map((f) => f.catchError((_) {})));
    }

    if (!mounted) return;
    final recordedPlaying = recorded?.value.isPlaying == true || _hasAudioRecorded;
    final originalPlaying = widget.original?.value.isPlaying == true || widget.originalYoutube != null;
    final started = _hasRecorded ? recordedPlaying : originalPlaying;
    if (!started && _hasRecorded) {
      await _forcePauseAll();
    }
    setState(() => _playing = started);
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
    if (!_hasAudioRecorded) return null;
    return const _AudioOnlyPreview(recording: false);
  }

  Widget _videoPane(String label, VideoPlayerController? player, Widget? customWidget, TransformationController transformController, VoidCallback onResetZoom) {
    final isFallback = customWidget == null && (player == null || !player.value.isInitialized);
    final fallbackText = label == '내 동작'
        ? '[가상 녹화 테스트 데이터]\n녹화 영상 프리뷰'
        : '원본 영상을 불러오는 중입니다...';
    final isOriginalYoutube = customWidget != null;
    final ratio = isOriginalYoutube
        ? (widget.originalAspectRatio ?? 16 / 9)
        : _aspectRatioOf(player);
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
              child: Center(
                child: isFallback
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          fallbackText,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: ratio > 0 ? ratio : 16 / 9,
                        child: customWidget ?? VideoPlayer(player!),
                      ),
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
    this.recordedMediaPath,
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
  final String? recordedMediaPath;

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

  bool get _youtubeAlive => !_disposing && mounted && _youtube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtube, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    _preferAudioUi = (widget.recordedAudioPath?.trim().isNotEmpty ?? false) ||
        _pathLooksLikeAudioRecording(widget.recordedAudioPath) ||
        _pathLooksLikeAudioRecording(widget.recordedMediaPath);
    _resolvedAudioPath = widget.recordedAudioPath?.trim() ??
        (_preferAudioUi ? widget.recordedMediaPath?.trim() : null);
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
    final recorded = widget.recorded;
    if (_preferAudioUi) {
      if (mounted) setState(() {});
      return;
    }
    if (recorded == null) return;
    try {
      if (!recorded.value.isInitialized) {
        await recorded.initialize().timeout(const Duration(seconds: 8));
      }
      if (_recordedVideoLooksUnusable(recorded)) {
        debugPrint('[LOOPI] comparison recorded clip empty — bypass VideoPlayer');
        try {
          await recorded.pause();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _preferAudioUi = true;
            _resolvedAudioPath = widget.recordedAudioPath?.trim() ??
                widget.recordedMediaPath?.trim();
          });
        }
        return;
      }
      // Stay paused — MotionComparisonViewer owns simultaneous play/pause.
      await recorded.pause();
      await recorded.seekTo(Duration.zero);
    } catch (_) {}
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
      recordedController: widget.recorded,
      baseFileName: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioPath = _effectiveRecordedAudioPath;
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
            recorded: audioPath != null ? null : widget.recorded,
            originalYoutube: _youtube,
            // Cached once in initState — recreating each build re-fires YT stream.
            originalWidget: _youtubePlayerWidget,
            segments: widget.segments,
            loopStart: widget.loopStart,
            loopEnd: widget.loopEnd,
            intervalMarkers: widget.intervalMarkers,
            recordedAudioPath: audioPath ?? widget.recordedAudioPath,
            recordedSectionIndex: widget.recordedSectionIndex,
            sectionTakesByIndex: widget.sectionTakesByIndex,
            originalAspectRatio: widget.originalAspectRatio,
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
          await _recorded!.initialize().timeout(const Duration(seconds: 8));
        } else if (!_hasRecordedFallback && path != null && path.trim().isNotEmpty) {
          final value = path.trim();
          // Dead web blob: URLs from a prior session cannot be revived.
          if (kIsWeb && value.startsWith('blob:')) {
            _recorded = null;
          } else {
            _recorded = (kIsWeb || value.startsWith('http://') || value.startsWith('https://'))
                ? createCachedNetworkVideo(Uri.parse(value))
                : VideoPlayerController.file(File(value));
            await _recorded!.initialize().timeout(const Duration(seconds: 8));
          }
        }
        if (_recorded != null && _recorded!.value.isInitialized) {
          if (_recordedVideoLooksUnusable(_recorded)) {
            debugPrint('[LOOPI] PracticeResultViewer empty recorded clip — audio UI');
            try {
              await _recorded?.dispose();
            } catch (_) {}
            _recorded = null;
          } else {
            await _recorded!.pause();
            await _recorded!.seekTo(Duration.zero);
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

