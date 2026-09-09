import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' hide PlayerState;
import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../state/shadowing_sequence_controller.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';
import '../utils/cached_video.dart';
import '../services/storage_service.dart';
import '../utils/media_limits.dart';
import '../utils/youtube_player_factory.dart';
import '../widgets/highlight_interval.dart';
import '../widgets/shell_close_scope.dart';

SavedRoutine sanitizeRoutineForPractice(SavedRoutine routine) {
  final videoId = resolveYoutubeVideoId(videoId: routine.videoId, videoUrl: routine.videoUrl) ?? '';
  final segments = routine.segments.map((segment) {
    final start = segment.startSec.isFinite ? segment.startSec.clamp(0, 24 * 3600) : 0.0;
    var end = segment.endSec.isFinite ? segment.endSec : start + 30;
    if (end <= start) end = start + 30;
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
    videoUrl: routine.videoUrl,
    videoId: videoId,
    segments: segments.isNotEmpty
        ? segments
        : [
            RoutineSegment(
              id: 'seg_fallback',
              startSec: 0,
              endSec: 30,
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

  // A -> B segment engine state used while recording/virtual-recording so the
  // original video plays through every routine segment sequentially, honoring
  // each segment's speed and repeat count instead of just the first segment.
  int _engineSegmentIndex = 0;
  int _enginePlaysRemaining = 1;
  bool _engineSeeking = false;
  final Stopwatch _recordClock = Stopwatch();
  final List<PracticeIntervalMarker> _intervalMarkers = [];
  int? _openMarkerIndex;
  Timer? _enginePollTimer;
  StreamSubscription<YoutubeVideoState>? _engineYoutubeSub;
  VoidCallback? _engineOnFinished;
  bool _disposing = false;
  int _engineEpoch = 0;
  bool _engineActive = false;
  bool _engineAdvancing = false;
  bool _stopInProgress = false;

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
    try {
      await Future.any([
        () async {
          final cameras = await availableCameras();
          if (cameras.isEmpty) {
            throw CameraException('cameraNotFound', 'No cameras available');
          }
          _camera = CameraController(cameras.first, kPracticeCameraPreset, enableAudio: true);
          await _camera!.initialize();
        }(),
        Future<void>.delayed(const Duration(seconds: 5), () => throw TimeoutException('camera')),
      ]);
    } on CameraException catch (error) {
      await _camera?.dispose();
      _camera = null;
      _cameraError = error.description ?? error.code;
      await _enableAudioOnlyIfPossible();
    } catch (error) {
      await _camera?.dispose();
      _camera = null;
      _cameraError = error.toString();
      await _enableAudioOnlyIfPossible();
    }
    if (mounted) setState(() {});
  }

  Future<void> _enableAudioOnlyIfPossible() async {
    try {
      final micReady = await _recorder.hasPermission();
      _audioOnlyMode = micReady;
    } catch (_) {
      _audioOnlyMode = false;
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
    final camera = _camera;
    final cameraAvailable = camera?.value.isInitialized == true;
    final microphoneAvailable = await _recorder.hasPermission();
    if (!cameraAvailable && microphoneAvailable) {
      _audioOnlyMode = true;
      await _toggleAudioOnlyRecording();
      return;
    }
    if (!cameraAvailable || !microphoneAvailable) {
      final missing = !cameraAvailable && !microphoneAvailable
          ? '카메라, 마이크가 감지되지 않습니다'
          : !cameraAvailable
              ? '카메라가 감지되지 않습니다'
              : '마이크가 감지되지 않습니다';
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(missing),
          content: const Text('계속 진행하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('아니오')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('네')),
          ],
        ),
      );
      if (proceed == true) {
        await _runCountdown();
        if (mounted) _startVirtualRecording();
      }
      return;
    }
    try {
      if (_recording) {
        if (_stopInProgress) return;
        _stopInProgress = true;
        _stopSegmentEngine();
        unawaited(_haltOriginalPlayback());
        final file = await camera!.stopVideoRecording();
        try {
          await _original?.pause();
        } catch (_) {}
        _recorded = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(file.path))
            : VideoPlayerController.file(File(file.path));
        await _recorded!.initialize();
        _recording = false;
        await _finishRecording(file.path);
      } else {
        await _runCountdown();
        if (!mounted) return;
        _recording = true;
        _beginRecordClock();
        _recordingTimer?.cancel();
        _armMaxRecordingTimer();
        await camera!.startVideoRecording();
        unawaited(_beginSegmentEngine(onFinished: () {
          if (_recording && !_stopInProgress) unawaited(_toggleRecording());
        }));
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '녹화에 실패했습니다: $error');
    } finally {
      _stopInProgress = false;
    }
  }

  Future<void> _toggleAudioOnlyRecording() async {
    try {
      if (_audioRecording) {
        if (_stopInProgress) return;
        _stopInProgress = true;
        _virtualTimer?.cancel();
        _virtualTimer = null;
        _stopSegmentEngine();
        unawaited(_haltOriginalPlayback());
        final path = await _recorder.stop();
        _audioRecording = false;
        _recording = false;
        if (mounted) setState(() {});
        final bytes = await StorageService.readMediaBytes(path: path);
        await _showSaveDialog(
          recordedPath: path,
          isAudioRecording: true,
          recordedBytes: bytes,
        );
        return;
      }
      await _runCountdown();
      if (!mounted) return;
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
      await _startPracticeAudioRecording();
      unawaited(_beginSegmentEngine(onFinished: () {
        if (_audioRecording && !_stopInProgress) unawaited(_toggleAudioOnlyRecording());
      }));
      if (mounted) setState(() {});
    } catch (error) {
      _audioRecording = false;
      _recording = false;
      if (mounted) setState(() => _error = '음성 녹화에 실패했습니다: $error');
    } finally {
      _stopInProgress = false;
    }
  }

  int get _recordingDelaySeconds {
    final segments = widget.routine.segments;
    final configured = segments.isNotEmpty ? segments.first.delaySec : 0;
    return configured > 0 ? configured : 3;
  }

  /// Shows a full-screen 3-2-1-START countdown before recording/playback begins.
  Future<void> _runCountdown() async {
    if (_countingDown || !mounted) return;
    setState(() {
      _countingDown = true;
      _countdownLabel = '$_recordingDelaySeconds';
    });
    for (var i = _recordingDelaySeconds; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdownLabel = '$i');
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _countdownLabel = 'START!');
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _countingDown = false);
  }

  /// Drives the original video/audio through every routine segment in order
  /// (A -> B -> ...), applying each segment's speed and repeat count.
  void _beginRecordClock() {
    _recordClock
      ..reset()
      ..start();
    _intervalMarkers.clear();
    _openMarkerIndex = null;
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
    unawaited(_yt((player) => player.pauseVideo()));
  }

  Future<void> _beginSegmentEngine({required VoidCallback onFinished}) async {
    _engineEpoch += 1;
    final epoch = _engineEpoch;
    _engineActive = true;
    _engineAdvancing = false;
    _engineSeeking = false;
    _engineOnFinished = onFinished;
    _cancelEngineListeners();
    await _playEngineSegment(0, epoch: epoch);
  }

  Future<void> _playEngineSegment(
    int index, {
    int? epoch,
    bool resetPlays = true,
    bool previewOnly = false,
  }) async {
    final token = epoch ?? _engineEpoch;
    if (index < 0 || index >= widget.routine.segments.length) return;
    if (!previewOnly && (!_engineSessionLive || token != _engineEpoch)) {
      _engineSeeking = false;
      _engineAdvancing = false;
      return;
    }

    _engineAdvancing = !previewOnly;
    _engineSeeking = true;
    if (!previewOnly) _cancelEngineListeners();

    _logIntervalTransition(index);
    _engineSegmentIndex = index;
    if (mounted) setState(() {});
    final segment = widget.routine.segments[index];
    if (resetPlays) {
      _enginePlaysRemaining = segment.loopCount == kInfiniteLoop
          ? kInfiniteLoop
          : (segment.loopCount <= 0 ? 1 : segment.loopCount);
    }

    try {
      final original = _original;
      if (original != null) {
        await original.setPlaybackSpeed(segment.speed);
        await original.seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
      }
      if (_youtubeOriginal != null) {
        await _yt((player) => player.setPlaybackRate(segment.speed));
        await _yt(
          (player) => player.seekTo(seconds: segment.startSec, allowSeekAhead: true),
        );
      }
    } catch (_) {}

    if (!previewOnly && (!_engineSessionLive || token != _engineEpoch)) {
      _engineSeeking = false;
      _engineAdvancing = false;
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!previewOnly && (!_engineSessionLive || token != _engineEpoch)) {
      _engineSeeking = false;
      _engineAdvancing = false;
      return;
    }

    try {
      await _original?.play();
      await _yt((player) => player.playVideo());
    } catch (_) {}

    _engineSeeking = false;
    _engineAdvancing = false;
    if (!previewOnly) _armEnginePoll(token);
  }

  void _cancelEngineListeners() {
    _enginePollTimer?.cancel();
    _enginePollTimer = null;
    unawaited(_engineYoutubeSub?.cancel());
    _engineYoutubeSub = null;
  }

  void _armEnginePoll(int token) {
    _cancelEngineListeners();
    if (!_engineSessionLive || token != _engineEpoch) return;
    _enginePollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      unawaited(_engineTick(token));
    });
    final youtube = _youtubeOriginal;
    if (youtube != null) {
      _engineYoutubeSub = listenYoutubeStream(
        youtube.videoStateStream,
        (state) {
          if (!_engineSessionLive || token != _engineEpoch) return;
          _onEngineTime(state.position.inMilliseconds / 1000.0, token);
        },
        isAlive: () => _engineSessionLive && token == _engineEpoch && !_engineSeeking,
      );
    }
  }

  Future<void> _engineTick(int token) async {
    if (!_engineSessionLive || token != _engineEpoch || _engineSeeking || _engineAdvancing) {
      return;
    }
    try {
      final time = await _engineCurrentTime();
      if (!_engineSessionLive || token != _engineEpoch || _engineSeeking || _engineAdvancing) {
        return;
      }
      if (time == null) return;
      _onEngineTime(time, token);
    } catch (_) {}
  }

  Future<double?> _engineCurrentTime() async {
    final original = _original;
    if (original != null && original.value.isInitialized) {
      return original.value.position.inMilliseconds / 1000.0;
    }
    if (_youtubeOriginal != null) {
      return _yt((player) => player.currentTime);
    }
    return null;
  }

  void _onEngineTime(double time, int token) {
    if (!_engineSessionLive || token != _engineEpoch || _engineAdvancing || _engineSeeking) {
      return;
    }
    if (_engineSegmentIndex < 0 || _engineSegmentIndex >= widget.routine.segments.length) {
      return;
    }
    final segment = widget.routine.segments[_engineSegmentIndex];
    if (time < segment.startSec - 1.0 && _engineSegmentIndex > 0) return;
    if (time + 0.2 < segment.endSec) return;

    _engineAdvancing = true;
    _cancelEngineListeners();

    if (segment.loopCount == kInfiniteLoop) {
      unawaited(_playEngineSegment(_engineSegmentIndex, epoch: token, resetPlays: false));
      return;
    }
    _enginePlaysRemaining -= 1;
    if (_enginePlaysRemaining > 0) {
      unawaited(_playEngineSegment(_engineSegmentIndex, epoch: token, resetPlays: false));
      return;
    }
    final next = _engineSegmentIndex + 1;
    if (next < widget.routine.segments.length) {
      unawaited(_playEngineSegment(next, epoch: token));
      return;
    }
    _engineActive = false;
    _engineAdvancing = false;
    final finished = _engineOnFinished;
    _engineOnFinished = null;
    finished?.call();
  }

  void _stopSegmentEngine() {
    _engineEpoch += 1;
    _engineActive = false;
    _engineAdvancing = false;
    _engineSeeking = false;
    _engineOnFinished = null;
    _cancelEngineListeners();
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
    _stopInProgress = true;
    _virtualTimer?.cancel();
    _virtualTimer = null;
    _stopSegmentEngine();
    unawaited(_haltOriginalPlayback());
    if (mounted) {
      setState(() => _virtualRecording = false);
      _showSaveDialog();
    }
    _stopInProgress = false;
  }

  Future<void> _finishRecording(String path) async {
    _recordingTimer?.cancel();
    _virtualTimer?.cancel();
    _stopSegmentEngine();
    unawaited(_haltOriginalPlayback());
    _recording = false;
    if (mounted) setState(() {});
    final bytes = await StorageService.readMediaBytes(path: path);
    await _showSaveDialog(recordedPath: path, recordedBytes: bytes);
  }

  Future<void> _showSaveDialog({
    String? recordedPath,
    bool isAudioRecording = false,
    List<int>? recordedBytes,
  }) async {
    final controller = TextEditingController(text: '${_dateLabel()} ${widget.routine.name} 연습 1');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('연습 영상 저장'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: '파일 이름')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('저장하기')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final loopStart = widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : 0.0;
    final loopEnd = widget.routine.segments.isNotEmpty ? widget.routine.segments.last.endSec : loopStart;
    final playbackRate = widget.routine.segments.isNotEmpty ? widget.routine.segments.first.speed : 1.0;
    await widget.library.savePracticeResult(PracticeResult(
      id: 'practice_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      routineId: widget.routine.id,
      createdAt: DateTime.now(),
      recordedPath: recordedPath,
      recordedDataBytes: recordedBytes,
      startTime: loopStart,
      endTime: loopEnd,
      playbackRate: playbackRate,
      category: widget.routine.category,
      intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
      isAudioRecording: isAudioRecording,
    ));
    if (mounted) {
      await _navigateToComparisonPage(title: name, recordedAudioPath: isAudioRecording ? recordedPath : null);
    }
  }

  /// Hands the already-initialized player controllers off to a standalone
  /// full-screen result page instead of overlaying them on this screen, so
  /// this screen's dispose() must not tear them down afterwards.
  Future<void> _navigateToComparisonPage({String? title, String? recordedAudioPath}) async {
    final original = _original;
    final recorded = _recorded;
    final youtube = _youtubeOriginal;
    _original = null;
    _recorded = null;
    _youtubeOriginal = null;
    try {
      await original?.pause();
      await recorded?.pause();
      await safeYoutubePlayerCallOn(youtube, (player) => player.pauseVideo());
    } catch (_) {}
    final youtubeVideoId = resolveYoutubeVideoId(
      videoId: widget.routine.videoId,
      videoUrl: widget.routine.videoUrl,
    );
    if (youtubeVideoId != null) {
      await closeYoutubePlayerSafely(youtube);
    }
    final segments = widget.routine.segments;
    final loopStart = segments.isNotEmpty ? segments.first.startSec : 0.0;
    final loopEnd = segments.isNotEmpty ? segments.last.endSec : loopStart;
    final playbackRate = segments.isNotEmpty ? segments.first.speed : 1.0;
    if (!mounted) return;
    final review = MotionComparisonViewerPage(
      title: title ?? widget.routine.name,
      original: original,
      recorded: recorded,
      originalYoutube: youtubeVideoId == null ? youtube : null,
      youtubeVideoId: youtubeVideoId,
      segments: segments,
      loopStart: loopStart,
      loopEnd: loopEnd,
      playbackRate: playbackRate,
      intervalMarkers: List<PracticeIntervalMarker>.from(_intervalMarkers),
      recordedAudioPath: recordedAudioPath,
    );
    if (widget.onOpenInShell != null) {
      widget.onOpenInShell!(review);
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => review),
    );
  }

  String _dateLabel() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playComparison() async {
    final recorded = _recorded;
    if (recorded == null) return;
    final start = Duration(milliseconds: (widget.routine.segments.first.startSec * 1000).round());
    final original = _original;
    if (original != null) {
      await Future.wait([original.seekTo(start), recorded.seekTo(Duration.zero)]);
      await Future.wait([original.play(), recorded.play()]);
    } else if (_youtubeOriginal != null) {
      await _yt((player) => player.seekTo(seconds: widget.routine.segments.first.startSec));
      await recorded.seekTo(Duration.zero);
      await _yt((player) => player.playVideo());
      await recorded.play();
    } else {
      return;
    }
    _syncTimer?.cancel();
    _recordingTimer?.cancel();
    _virtualTimer?.cancel();
    _stopSegmentEngine();
    unawaited(_haltOriginalPlayback());
    _recorder.dispose();
    await _navigateToComparisonPage();
  }

  @override
  void dispose() {
    _disposing = true;
    _stopSegmentEngine();
    _virtualTimer?.cancel();
    _camera?.dispose();
    _original?.dispose();
    _recorded?.dispose();
    unawaited(closeYoutubePlayerSafely(_youtubeOriginal));
    revokeMediaBlobUrl(_originalObjectUrl);
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
            onPressed: _countingDown || _stopInProgress
                ? null
                : _virtualRecording
                    ? _stopVirtualRecording
                    : _recorded == null
                        ? _toggleRecording
                        : _playComparison,
            backgroundColor: _recorded == null ? Colors.redAccent : LoopiColors.purple,
            tooltip: _virtualRecording || _recording ? '녹화 중지 및 저장' : '녹화 시작',
            child: Icon(_virtualRecording || _recording ? Icons.stop : Icons.fiber_manual_record),
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
                    if (_countingDown)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black87,
                          child: Center(
                            child: Text(
                              _countdownLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 96, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  /// Lets the user jump directly to a routine segment during recording/preview,
  /// while auto-playing through the routine also highlights the active tab.
  Widget _recordingSegmentTabs() {
    final segments = widget.routine.segments;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _engineSegmentIndex;
          return ChoiceChip(
            label: IntervalChipLabel(
              label: sectionLabelForIndex(index),
              isHighlight: segments[index].isHighlight,
            ),
            selected: selected,
            onSelected: _countingDown
                ? null
                : (_) => _playEngineSegment(
                      index,
                      previewOnly: !_engineActive,
                    ),
            selectedColor: LoopiColors.purple,
            side: segments[index].isHighlight
                ? const BorderSide(color: kHighlightGold, width: 1.6)
                : null,
            labelStyle: TextStyle(
              color: selected ? Colors.white : null,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
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
              color: Colors.black,
              child: _fittedAspect(
                _originalAspectRatio,
                loopiYoutubePlayer(controller: _youtubeOriginal!),
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
            child: Text(
              _audioOnlyMode ? 'player.audio_only_hint'.tr() : '카메라가 감지되지 않았습니다 (가상 녹화 모드).',
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: Colors.black87,
            child: _fittedAspect(
              _previewAspectRatio,
              camera == null || !camera.value.isInitialized
                  ? _AudioOnlyPreview(
                      photoUrl: widget.profilePhotoUrl,
                      recording: _audioRecording || _virtualRecording,
                      seconds: _virtualSeconds,
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
            color: Colors.black,
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

  @override
  State<MotionComparisonViewer> createState() => _MotionComparisonViewerState();
}

class _MotionComparisonViewerState extends State<MotionComparisonViewer> {
  double _position = 0;
  bool _playing = false;
  bool _preparing = true;
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

  bool get _youtubeAlive => !_disposing && mounted && widget.originalYoutube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(widget.originalYoutube, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    _playing = false;
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
      unawaited(_preparePlayback());
    });
  }

  void _onYoutubeChanged(YoutubePlayerValue value) {
    if (!mounted || _hasRecorded || _preparing) return;
    final playing = value.playerState == PlayerState.playing;
    if (_playing != playing) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _ensureInitialized(VideoPlayerController? controller) async {
    if (controller == null) return;
    if (!controller.value.isInitialized) {
      await controller.initialize();
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
        setState(() {
          _position = (position.inMilliseconds / 1000.0).clamp(_minPosition, _maxPosition);
          _playing = true;
        });
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
    try {
      await _ensureInitialized(widget.original);
      await _ensureInitialized(widget.recorded);
      await _prepareRecordedAudio();
      final recorded = widget.recorded;
      if (recorded != null && recorded.value.isInitialized) {
        try {
          await recorded.play();
          await recorded.pause();
        } catch (_) {}
      }
      await _seekBoth(_minPosition);
      if (mounted) {
        setState(() => _playing = false);
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    } finally {
      _preparing = false;
    }
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
  bool get _hasAudioRecorded => _audioReady && (widget.recordedAudioPath?.isNotEmpty ?? false);

  bool get _hasRecorded =>
      (widget.recorded != null && widget.recorded!.value.isInitialized) || _hasAudioRecorded;

  bool get _hasLoopRange => _rangeEnd > _rangeStart;

  double get _rangeStart {
    if (widget.loopStart > 0) return widget.loopStart;
    if (widget.segments.isNotEmpty) return widget.segments.first.startSec;
    return 0;
  }

  double get _rangeEnd {
    if (widget.loopEnd > 0) return widget.loopEnd;
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
    final recorded = widget.recorded;
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
    if (_hasRecorded && widget.recorded != null) {
      return widget.recorded!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.original != null && widget.original!.value.isInitialized) {
      return widget.original!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.originalYoutube != null) {
      return await _yt((player) => player.currentTime) ?? 0;
    }
    return 0;
  }

  void _onRecordedChanged() {
    if (!mounted || !_hasRecorded || _preparing) return;
    final recorded = widget.recorded!;
    final position = recorded.value.position.inMilliseconds / 1000.0;
    final bounded = position.clamp(_minPosition, _maxPosition);
    setState(() {
      _position = bounded;
      _playing = recorded.value.isPlaying;
    });
    if (!_loopingBack && position >= _maxPosition - 0.15 && recorded.value.isPlaying) {
      unawaited(_loopBackToStart());
    }
  }

  void _onOriginalChanged() {
    if (_hasRecorded) return;
    if (_preparing) return;
    final original = widget.original;
    if (!mounted || original == null || !original.value.isInitialized) return;
    final position = original.value.position.inMilliseconds / 1000.0;
    final bounded = _hasLoopRange ? position.clamp(_rangeStart, _rangeEnd) : position.clamp(0.0, _maxPosition);
    setState(() {
      _position = bounded;
      _playing = original.value.isPlaying;
    });
    _syncSegmentHighlight(position);
    if (_hasLoopRange && position >= _rangeEnd - 0.1 && original.value.isPlaying) {
      unawaited(_loopBackToStart());
    }
  }

  void _syncSegmentHighlight(double originalSeconds) {
    if (widget.segments.isEmpty) return;
    var newIndex = _segmentIndex;
    for (var i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      if (originalSeconds >= segment.startSec - 0.15 && originalSeconds <= segment.endSec + 0.15) {
        newIndex = i;
        break;
      }
    }
    if (newIndex != _segmentIndex && mounted) {
      setState(() => _segmentIndex = newIndex);
    }
  }

  Future<void> _seekBoth(double seconds) async {
    final clamped = seconds.clamp(_minPosition, _maxPosition).toDouble();
    setState(() => _position = clamped);
    if (_hasRecorded) {
      await widget.recorded?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
      await _seekRecordedAudio(clamped);
      final progress = _maxPosition > 0 ? (clamped / _maxPosition).clamp(0.0, 1.0) : 0.0;
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      await widget.original?.seekTo(Duration(milliseconds: (target * 1000).round()));
      if (widget.originalYoutube != null) {
        await _yt((player) => player.seekTo(seconds: target, allowSeekAhead: true));
      }
      _syncSegmentHighlight(target);
    } else {
      await widget.original?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
      if (widget.originalYoutube != null) {
        await _yt((player) => player.seekTo(seconds: clamped, allowSeekAhead: true));
      }
      _syncSegmentHighlight(clamped);
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

  /// Jumps straight to a routine segment's start time/speed, independent of
  /// wherever the recorded clip's own timeline currently sits.
  Future<void> _selectSegment(int index) async {
    if (index < 0 || index >= widget.segments.length) return;
    final segment = widget.segments[index];
    setState(() => _segmentIndex = index);
    try {
        // ✨ 1. 딜레이 시간 계산
        final delay = segment.delaySec;
        final waitTime = Duration(milliseconds: 120 + (delay * 1000));

        // ✨ 2. 탐색(Seek) 전 모든 플레이어 일시정지 (재생 중 넘어가는 것 방지)
        await widget.original?.pause();
        await _yt((player) => player.pauseVideo());
        await widget.recorded?.pause();
        await _pauseRecordedAudio();

        // --- 기존 속도 설정 및 위치 이동 코드 (그대로 유지) ---
        await widget.original?.setPlaybackSpeed(segment.speed);
        await _yt((player) => player.setPlaybackRate(segment.speed));
        await widget.original?.seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
        if (widget.originalYoutube != null) {
          await _yt(
            (player) => player.seekTo(seconds: segment.startSec, allowSeekAhead: true),
          );
        }
        
        if (_hasRecorded) {
          final marker = _markerForSegment(index);
          final double recordedTarget;
          if (marker != null) {
            recordedTarget = marker.startOffsetMillis / 1000.0;
          } else {
            final span = _rangeEnd - _rangeStart;
            final progress = span > 0 ? ((segment.startSec - _rangeStart) / span).clamp(0.0, 1.0) : 0.0;
            recordedTarget = progress * _recordedDurationSeconds;
          }
          await widget.recorded?.seekTo(Duration(milliseconds: (recordedTarget * 1000).round()));
          await _seekRecordedAudio(recordedTarget);
          if (mounted) setState(() => _position = recordedTarget.clamp(_minPosition, _maxPosition));
        } else if (mounted) {
          setState(() => _position = segment.startSec.clamp(_minPosition, _maxPosition));
        }
        // --------------------------------------------------

        // ✨ 3. 위치 이동을 마친 후 설정된 시간만큼 멈춰서 대기
        await Future.delayed(waitTime);
        if (!mounted || _disposing) return;

        // ✨ 4. 대기가 끝난 뒤, 원래 재생 중(_playing) 상태였다면 모두 다시 재생
        if (_playing) {
          await widget.original?.play();
          await _yt((player) => player.playVideo());
          await widget.recorded?.play();
          await _playRecordedAudio();
        }

      } catch (_) {}
  }

  Future<void> _loopBackToStart() async {
    if (_loopingBack || _disposing || !mounted) return;
    _loopingBack = true;
    try {
      final nextIndex = _segmentIndex + 1;
      if (nextIndex < widget.segments.length) {
        await _selectSegment(nextIndex);
      } else {
        _loopTimer?.cancel();
        _loopTimer = null;
        _recordedSyncTimer?.cancel();
        _recordedSyncTimer = null;
        if (mounted) setState(() => _playing = false);
        widget.original?.pause();
        unawaited(_yt((player) => player.pauseVideo()));
        widget.recorded?.pause();
        unawaited(_pauseRecordedAudio());
        return;
      }

      if (!_playing) return;
      if (widget.original != null) {
        await widget.original!.play();
      }
      if (widget.originalYoutube != null) {
        await _yt((player) => player.playVideo());
      }
      if (widget.recorded != null) {
        await widget.recorded!.play();
      }
      await _playRecordedAudio();
    } finally {
      _loopingBack = false;
    }
  }

  /// Since the recorded clip and the original may play at different speeds,
  /// periodically re-align the original to the recorded clip's progress (0.0-1.0).
  void _startRecordedSync() {
    _recordedSyncTimer?.cancel();
    if (!_hasRecorded) return;
    _recordedSyncTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!mounted || !_hasRecorded || !_playing || _disposing || _loopingBack) return;
      final double progress;
      if (_hasAudioRecorded) {
        final durationMs = _audioDuration.inMilliseconds;
        if (durationMs <= 0) return;
        final position = await _recordedAudio?.getCurrentPosition();
        progress = ((position?.inMilliseconds ?? 0) / durationMs).clamp(0.0, 1.0);
      } else {
        final recorded = widget.recorded;
        if (recorded == null) return;
        final durationMs = recorded.value.duration.inMilliseconds;
        if (durationMs <= 0) return;
        progress = (recorded.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
      }
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      try {
        if (widget.original != null && widget.original!.value.isInitialized) {
          final current = widget.original!.value.position.inMilliseconds / 1000.0;
          if ((current - target).abs() > 0.35) {
            await widget.original!.seekTo(Duration(milliseconds: (target * 1000).round()));
          }
        }
        if (widget.originalYoutube != null) {
          final current = await _yt((player) => player.currentTime);
          if (current == null) return;
          if (current <= 0.05 && target > 1) return;
          if ((current - target).abs() > 0.35) {
            await _yt((player) => player.seekTo(seconds: target, allowSeekAhead: true));
          }
        }
      } catch (_) {}
      _syncSegmentHighlight(target);
    });
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      _loopTimer?.cancel();
      _loopTimer = null;
      _recordedSyncTimer?.cancel();
      _recordedSyncTimer = null;
      await widget.original?.pause();
      await widget.recorded?.pause();
      await _pauseRecordedAudio();
      await _yt((player) => player.pauseVideo());
    } else {
      if (_position < _minPosition) {
        await _seekBoth(_minPosition);
      }
      _loopTimer?.cancel();
      _loopTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
        if (!mounted || !_playing || _loopingBack || _disposing) return;
        if (_hasRecorded) return;
        final current = await _currentPlaybackSeconds();
        if (!mounted || !_playing || _loopingBack) return;
        if (current >= _maxPosition - 0.1) {
          unawaited(_loopBackToStart());
        }
      });
      if (_hasRecorded) _startRecordedSync();
      await widget.original?.play();
      await widget.recorded?.play();
      await _playRecordedAudio();
      await _yt((player) => player.playVideo());
      if (mounted) {
        final started = widget.recorded?.value.isPlaying == true ||
            widget.original?.value.isPlaying == true ||
            widget.originalYoutube != null;
        setState(() => _playing = started);
      }
      return;
    }
    if (mounted) setState(() => _playing = false);
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
    unawaited(_audioPosSub?.cancel());
    unawaited(_recordedAudio?.dispose());
    _originalTransformController.dispose();
    _recordedTransformController.dispose();
    super.dispose();
  }

  Widget _segmentTabs() {
    if (widget.segments.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.segments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _segmentIndex;
          return ChoiceChip(
            label: IntervalChipLabel(
              label: sectionLabelForIndex(index),
              isHighlight: widget.segments[index].isHighlight,
            ),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _segmentIndex = index;
              });
              _selectSegment(index);
            },
            selectedColor: LoopiColors.purple,
            side: widget.segments[index].isHighlight
                ? const BorderSide(color: kHighlightGold, width: 1.6)
                : null,
            labelStyle: TextStyle(
              color: selected ? Colors.white : null,
              fontWeight: FontWeight.w700,
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
              if (isLandscape || _isVerticalPlayer(widget.original) || _isVerticalPlayer(widget.recorded))
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(width: 12),
                      Expanded(child: _videoPane('내 동작', widget.recorded, _recordedAudioWidget(), _recordedTransformController, _resetRecordedZoom)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(height: 12),
                      Expanded(child: _videoPane('내 동작', widget.recorded, _recordedAudioWidget(), _recordedTransformController, _resetRecordedZoom)),
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
    final ratio = customWidget != null ? 16 / 9 : _aspectRatioOf(player);

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
            color: Colors.black,
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
                          style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
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
    this.segments = const [],
    this.loopStart = 0,
    this.loopEnd = 0,
    this.playbackRate = 1.0,
    this.intervalMarkers = const [],
    this.recordedAudioPath,
  });

  final String title;
  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final YoutubePlayerController? originalYoutube;
  final String? youtubeVideoId;
  final List<RoutineSegment> segments;
  final double loopStart;
  final double loopEnd;
  final double playbackRate;
  final List<PracticeIntervalMarker> intervalMarkers;
  final String? recordedAudioPath;

  @override
  State<MotionComparisonViewerPage> createState() => _MotionComparisonViewerPageState();
}

class _MotionComparisonViewerPageState extends State<MotionComparisonViewerPage> {
  YoutubePlayerController? _youtube;
  bool _ownsYoutube = false;
  bool _disposing = false;

  bool get _youtubeAlive => !_disposing && mounted && _youtube != null;

  Future<T?> _yt<T>(Future<T> Function(YoutubePlayerController player) action) {
    return safeYoutubePlayerCallOn(_youtube, action, isAlive: () => _youtubeAlive);
  }

  @override
  void initState() {
    super.initState();
    final videoId = resolveYoutubeVideoId(videoId: widget.youtubeVideoId);
    if (videoId != null) {
      unawaited(closeYoutubePlayerSafely(widget.originalYoutube));
      _youtube = createLoopiYoutubeController(
        videoId: videoId,
        autoPlay: false,
        startSeconds: widget.loopStart,
      );
      _ownsYoutube = true;
    } else {
      _youtube = widget.originalYoutube;
    }
    unawaited(_prepareRecorded());
    unawaited(_applyRoutinePlaybackRate());
  }

  Future<void> _prepareRecorded() async {
    final recorded = widget.recorded;
    if (recorded == null) return;
    try {
      if (!recorded.value.isInitialized) {
        await recorded.initialize();
      }
      await recorded.play();
      await recorded.pause();
      await recorded.seekTo(Duration.zero);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _applyRoutinePlaybackRate() async {
    try {
      await widget.original?.setPlaybackSpeed(widget.playbackRate);
      await _yt((player) => player.setPlaybackRate(widget.playbackRate));
    } catch (_) {}
  }

  void _handleBack() {
    closeShellOrPop(context);
  }

  @override
  void dispose() {
    _disposing = true;
    widget.original?.dispose();
    widget.recorded?.dispose();
    if (_ownsYoutube) {
      unawaited(closeYoutubePlayerSafely(_youtube));
    } else {
      unawaited(closeYoutubePlayerSafely(widget.originalYoutube));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: MotionComparisonViewer(
          original: widget.original,
          recorded: widget.recorded,
          originalYoutube: _youtube,
          originalWidget: _youtube == null ? null : loopiYoutubePlayer(controller: _youtube!),
          segments: widget.segments,
          loopStart: widget.loopStart,
          loopEnd: widget.loopEnd,
          intervalMarkers: widget.intervalMarkers,
          recordedAudioPath: widget.recordedAudioPath,
        ),
      ),
    );
  }
}

class PracticeResultViewer extends StatefulWidget {
  const PracticeResultViewer({super.key, required this.routine, required this.result});

  final SavedRoutine routine;
  final PracticeResult result;

  @override
  State<PracticeResultViewer> createState() => _PracticeResultViewerState();
}

class _PracticeResultViewerState extends State<PracticeResultViewer> {
  VideoPlayerController? _original;
  VideoPlayerController? _recorded;
  YoutubePlayerController? _youtube;
  String? _recordedObjectUrl;
  bool _loading = true;
  String? _loadError;
  bool _disposing = false;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      if (widget.routine.sourceType == SourceType.youtube) {
        final videoId = resolveYoutubeVideoId(
          videoId: widget.routine.videoId,
          videoUrl: widget.routine.videoUrl,
        );
        if (videoId != null) {
          _youtube = createLoopiYoutubeController(
            videoId: videoId,
            autoPlay: false,
            startSeconds: widget.result.startTime > 0
                ? widget.result.startTime
                : (widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : null),
          );
        }
      } else if (widget.routine.localDataBytes != null) {
        final url = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
        _original = VideoPlayerController.networkUrl(url == null
            ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(url));
        await _original!.initialize().timeout(const Duration(seconds: 8));
      } else if (widget.routine.localFilePath != null) {
        _original = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(widget.routine.localFilePath!))
            : VideoPlayerController.file(File(widget.routine.localFilePath!));
        await _original!.initialize().timeout(const Duration(seconds: 8));
      }

      final bytes = widget.result.recordedDataBytes;
      final path = widget.result.recordedPath;
      try {
        if (bytes != null && bytes.isNotEmpty) {
          _recordedObjectUrl = createMediaBlobUrl(bytes, 'video/mp4');
          final uri = _recordedObjectUrl == null
              ? Uri.dataFromBytes(bytes, mimeType: 'video/mp4')
              : Uri.parse(_recordedObjectUrl!);
          _recorded = VideoPlayerController.networkUrl(uri);
          await _recorded!.initialize().timeout(const Duration(seconds: 8));
        } else if (!_hasRecordedFallback && path != null && path.trim().isNotEmpty) {
          final value = path.trim();
          _recorded = (kIsWeb || value.startsWith('blob:') || value.startsWith('http://') || value.startsWith('https://'))
              ? createCachedNetworkVideo(Uri.parse(value))
              : VideoPlayerController.file(File(value));
          await _recorded!.initialize().timeout(const Duration(seconds: 8));
        }
        if (_recorded != null && _recorded!.value.isInitialized) {
          await _recorded!.play();
          await _recorded!.pause();
          await _recorded!.seekTo(Duration.zero);
        }
      } catch (_) {
        _recorded = null;
      }

      final loopStart = widget.result.startTime > 0
          ? widget.result.startTime
          : (widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : 0.0);
      if (_original != null && _original!.value.isInitialized) {
        await _original!.setPlaybackSpeed(widget.result.playbackRate);
        await _original!.seekTo(Duration(milliseconds: (loopStart * 1000).round()));
      }
      if (_youtube != null) {
        await _yt((player) => player.setPlaybackRate(widget.result.playbackRate));
        await _yt((player) => player.seekTo(seconds: loopStart));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '영상 로드를 실패했습니다.\n${error.toString()}';
        });
      }
      return;
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _retryLoad() async {
    _original?.dispose();
    _recorded?.dispose();
    await closeYoutubePlayerSafely(_youtube);
    _original = null;
    _recorded = null;
    _youtube = null;
    _recordedObjectUrl = null;
    await _load();
  }

  @override
  void dispose() {
    _disposing = true;
    _original?.dispose();
    _recorded?.dispose();
    unawaited(closeYoutubePlayerSafely(_youtube));
    revokeMediaBlobUrl(_recordedObjectUrl);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.result.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => closeShellOrPop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: MotionComparisonViewer(
          original: _original,
          recorded: _recorded,
          segments: widget.routine.segments,
          originalYoutube: _youtube,
          originalWidget: _youtube == null ? null : loopiYoutubePlayer(controller: _youtube!),
          loopStart: widget.result.startTime > 0 ? widget.result.startTime : (widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : 0),
          loopEnd: widget.result.endTime > 0 ? widget.result.endTime : (widget.routine.segments.isNotEmpty ? widget.routine.segments.last.endSec : 0),
          intervalMarkers: widget.result.intervalMarkers,
          recordedAudioPath: widget.result.isAudioRecording ? widget.result.recordedPath : null,
        ),
      ),
    );
  }
}

class _AudioOnlyPreview extends StatefulWidget {
  const _AudioOnlyPreview({
    this.photoUrl,
    this.recording = false,
    this.seconds = 0,
  });

  final String? photoUrl;
  final bool recording;
  final int seconds;

  @override
  State<_AudioOnlyPreview> createState() => _AudioOnlyPreviewState();
}

class _AudioOnlyPreviewState extends State<_AudioOnlyPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.recording) _ripple.repeat();
  }

  @override
  void didUpdateWidget(covariant _AudioOnlyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !oldWidget.recording) {
      _ripple.repeat();
    } else if (!widget.recording && oldWidget.recording) {
      _ripple.stop();
      _ripple.reset();
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  Widget _rippleRing(double t) {
    final scale = 1.0 + (t * 1.6);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent.withValues(alpha: 0.16 * opacity),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.65 * opacity),
            width: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photoUrl;
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
            SizedBox(
              width: 120,
              height: 120,
              child: AnimatedBuilder(
                animation: _ripple,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.recording) ...[
                        _rippleRing(_ripple.value),
                        _rippleRing((_ripple.value + 0.5) % 1.0),
                      ],
                      child!,
                    ],
                  );
                },
                child: Icon(
                  Icons.mic,
                  color: widget.recording ? Colors.redAccent : Colors.white70,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.recording ? '${widget.seconds}s' : 'player.audio_only_mode'.tr(),
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

