import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key, required this.library, this.selectedRoutine, this.selectedView});

  final RoutineLibrary library;
  final SavedRoutine? selectedRoutine;
  final Widget? selectedView;

  void _open(BuildContext context, SavedRoutine routine) {
    final Widget screen;
    switch (routine.sourceType) {
      case SourceType.localVideo:
        screen = VideoPracticeScreen(routine: routine, library: library);
        break;
      case SourceType.audio:
        screen = AudioPracticeScreen(routine: routine);
        break;
      case SourceType.youtube:
        screen = VideoPracticeScreen(routine: routine, library: library);
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
      return selectedRoutine!.sourceType == SourceType.audio
          ? AudioPracticeScreen(routine: selectedRoutine!)
          : VideoPracticeScreen(routine: selectedRoutine!, library: library);
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
  const VideoPracticeScreen({super.key, required this.routine, required this.library});

  final SavedRoutine routine;
  final RoutineLibrary library;

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
  bool _virtualRecording = false;
  int _virtualSeconds = 0;
  Timer? _virtualTimer;
  Timer? _recordingTimer;
  final AudioRecorder _recorder = AudioRecorder();
  bool _countingDown = false;
  String _countdownLabel = '';

  // A -> B segment engine state used while recording/virtual-recording so the
  // original video plays through every routine segment sequentially, honoring
  // each segment's speed and repeat count instead of just the first segment.
  int _engineSegmentIndex = 0;
  int _enginePlaysRemaining = 1;
  bool _engineSeeking = false;
  Timer? _enginePollTimer;
  VoidCallback? _engineOnFinished;

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
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('카메라가 감지되지 않았습니다.');
      _camera = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: true);
      await _camera!.initialize();
    } catch (error) {
      _cameraError = error.toString();
    }

    try {
      if (widget.routine.sourceType == SourceType.youtube) {
        _youtubeOriginal = YoutubePlayerController.fromVideoId(
          videoId: widget.routine.videoId,
          autoPlay: false,
          params: const YoutubePlayerParams(showControls: true),
        );
      }
      final path = widget.routine.localFilePath;
      if (path != null && !kIsWeb && widget.routine.sourceType == SourceType.localVideo) {
        _original = VideoPlayerController.file(File(path));
        await Future.any([
          _original!.initialize(),
          Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
        ]);
      } else if (widget.routine.localDataBytes != null && widget.routine.sourceType == SourceType.localVideo) {
        _originalObjectUrl = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
        final uri = _originalObjectUrl == null
            ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(_originalObjectUrl!);
        _original = VideoPlayerController.networkUrl(uri);
        await Future.any([
          _original!.initialize(),
          Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
        ]);
      } else if (path != null && widget.routine.sourceType == SourceType.localVideo) {
        _original = VideoPlayerController.networkUrl(Uri.parse(path));
        await Future.any([
          _original!.initialize(),
          Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
        ]);
      }
      
      // Seek to first segment start time after initialization
      if (widget.routine.segments.isNotEmpty) {
        final firstSegmentStartTime = widget.routine.segments.first.startSec;
        if (_original != null && _original!.value.isInitialized) {
          await _original!.seekTo(Duration(milliseconds: (firstSegmentStartTime * 1000).round()));
        }
        if (_youtubeOriginal != null) {
          await _youtubeOriginal!.seekTo(seconds: firstSegmentStartTime);
        }
      }
    } catch (error) {
      _originalError = '원본 영상을 준비하지 못했습니다: $error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleRecording() async {
    final camera = _camera;
    final cameraAvailable = camera?.value.isInitialized == true;
    final microphoneAvailable = await _recorder.hasPermission();
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
        final file = await camera!.stopVideoRecording();
        _stopSegmentEngine();
        try {
          await _original?.pause();
          await _youtubeOriginal?.pauseVideo();
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
        _recordingTimer?.cancel();
        // Start camera recording and original playback together once the countdown ends.
        await Future.wait([
          camera!.startVideoRecording(),
          _beginSegmentEngine(onFinished: () {
            if (_recording) _toggleRecording();
          }),
        ]);
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '녹화에 실패했습니다: $error');
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
  Future<void> _beginSegmentEngine({required VoidCallback onFinished}) async {
    _engineOnFinished = onFinished;
    _enginePollTimer?.cancel();
    await _playEngineSegment(0);
  }

  Future<void> _playEngineSegment(int index) async {
    if (index < 0 || index >= widget.routine.segments.length) return;
    _engineSegmentIndex = index;
    if (mounted) setState(() {});
    final segment = widget.routine.segments[index];
    _enginePlaysRemaining = segment.loopCount;
    _engineSeeking = true;
    try {
      final original = _original;
      if (original != null) {
        await original.setPlaybackSpeed(segment.speed);
        await original.seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
      }
      if (_youtubeOriginal != null) {
        await _youtubeOriginal!.setPlaybackRate(segment.speed);
        await _youtubeOriginal!.seekTo(seconds: segment.startSec, allowSeekAhead: true);
      }
    } catch (_) {}
    _engineSeeking = false;
    try {
      await _original?.play();
      await _youtubeOriginal?.playVideo();
    } catch (_) {}

    _enginePollTimer?.cancel();
    _enginePollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (_engineSeeking) return;
      try {
        final time = await _engineCurrentTime();
        _onEngineTime(time);
      } catch (_) {}
    });
  }

  Future<double> _engineCurrentTime() async {
    final original = _original;
    if (original != null && original.value.isInitialized) {
      return original.value.position.inMilliseconds / 1000.0;
    }
    if (_youtubeOriginal != null) {
      return await _youtubeOriginal!.currentTime;
    }
    return 0;
  }

  void _onEngineTime(double time) {
    final segment = widget.routine.segments[_engineSegmentIndex];
    if (time + 0.12 < segment.endSec) return;

    if (segment.loopCount == kInfiniteLoop) {
      unawaited(_playEngineSegment(_engineSegmentIndex));
      return;
    }
    _enginePlaysRemaining -= 1;
    if (_enginePlaysRemaining > 0) {
      unawaited(_playEngineSegment(_engineSegmentIndex));
      return;
    }
    if (_engineSegmentIndex + 1 < widget.routine.segments.length) {
      unawaited(_playEngineSegment(_engineSegmentIndex + 1));
      return;
    }
    _enginePollTimer?.cancel();
    _engineOnFinished?.call();
  }

  void _stopSegmentEngine() {
    _enginePollTimer?.cancel();
    _enginePollTimer = null;
    _engineOnFinished = null;
  }

  void _startVirtualRecording() {
    _virtualTimer?.cancel();
    setState(() {
      _virtualRecording = true;
      _virtualSeconds = 0;
    });
    _virtualTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _virtualRecording) {
        setState(() => _virtualSeconds += 1);
      }
    });
    unawaited(_beginSegmentEngine(onFinished: () {
      if (_virtualRecording) _stopVirtualRecording();
    }));
  }

  void _stopVirtualRecording() {
    _virtualTimer?.cancel();
    _stopSegmentEngine();
    _original?.pause();
    _youtubeOriginal?.pauseVideo();
    if (mounted) {
      setState(() => _virtualRecording = false);
      _showSaveDialog();
    }
  }

  Future<void> _finishRecording(String path) async {
    _recordingTimer?.cancel();
    _stopSegmentEngine();
    _recording = false;
    if (mounted) setState(() {});
    await _showSaveDialog(recordedPath: path);
  }

  Future<void> _showSaveDialog({String? recordedPath}) async {
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
      startTime: loopStart,
      endTime: loopEnd,
      playbackRate: playbackRate,
    ));
    if (mounted) await _navigateToComparisonPage(title: name);
  }

  /// Hands the already-initialized player controllers off to a standalone
  /// full-screen result page instead of overlaying them on this screen, so
  /// this screen's dispose() must not tear them down afterwards.
  Future<void> _navigateToComparisonPage({String? title}) async {
    final original = _original;
    final recorded = _recorded;
    final youtube = _youtubeOriginal;
    _original = null;
    _recorded = null;
    _youtubeOriginal = null;
    final segments = widget.routine.segments;
    final loopStart = segments.isNotEmpty ? segments.first.startSec : 0.0;
    final loopEnd = segments.isNotEmpty ? segments.last.endSec : loopStart;
    final playbackRate = segments.isNotEmpty ? segments.first.speed : 1.0;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MotionComparisonViewerPage(
          title: title ?? widget.routine.name,
          original: original,
          recorded: recorded,
          originalYoutube: youtube,
          segments: segments,
          loopStart: loopStart,
          loopEnd: loopEnd,
          playbackRate: playbackRate,
        ),
      ),
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
      await _youtubeOriginal!.seekTo(seconds: widget.routine.segments.first.startSec);
      await recorded.seekTo(Duration.zero);
      await Future.wait([_youtubeOriginal!.playVideo(), recorded.play()]);
    } else {
      return;
    }
    _syncTimer?.cancel();
    _recordingTimer?.cancel();
    _virtualTimer?.cancel();
    _stopSegmentEngine();
    _recorder.dispose();
    await _navigateToComparisonPage();
  }

  @override
  void dispose() {
    _camera?.dispose();
    _original?.dispose();
    _recorded?.dispose();
    _syncTimer?.cancel();
    _enginePollTimer?.cancel();
    _recordingTimer?.cancel();
    _virtualTimer?.cancel();
    _youtubeOriginal?.close();
    revokeMediaBlobUrl(_originalObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.name)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: !_loading && _error == null
          ? FloatingActionButton(
            onPressed: _virtualRecording
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
                              final content = landscape
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: _fitPane(original)),
                                        const SizedBox(width: 12),
                                        Expanded(child: _fitPane(camera)),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(child: _fitPane(original)),
                                        const SizedBox(height: 12),
                                        Expanded(child: _fitPane(camera)),
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
            label: Text(sectionLabelForIndex(index)),
            selected: selected,
            onSelected: _countingDown ? null : (_) => _playEngineSegment(index),
            selectedColor: LoopiColors.purple,
            labelStyle: TextStyle(
              color: selected ? Colors.white : null,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  Widget _fitPane(Widget child) {
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
          child: child,
        ),
      ),
    );
  }

  Widget _originalPane() {
    if (_originalError != null && _youtubeOriginal == null && _original == null) {
      return Container(
        height: 220,
        color: Colors.black87,
        alignment: Alignment.center,
        child: Text(_originalError!, style: const TextStyle(color: Colors.white70)),
      );
    }
    if (_youtubeOriginal != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('원본 영상', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 16 / 9, child: YoutubePlayer(controller: _youtubeOriginal!)),
      ]);
    }
    return _mediaPane('원본 영상', _original);
  }

  Widget _cameraPane() {
    final camera = _camera;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          const Text('카메라 프리뷰', style: TextStyle(fontWeight: FontWeight.w700)),
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
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('카메라가 감지되지 않았습니다 (가상 녹화 모드).'),
        ),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AspectRatio(
            aspectRatio: _previewAspectRatio,
            child: ColoredBox(
              color: Colors.black87,
              child: camera == null || !camera.value.isInitialized
                  ? const Center(
                      child: Text(
                        '카메라가 감지되지 않았습니다\n(가상 녹화 모드)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
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
      ),
    ]);
  }

  Widget _mediaPane(String label, VideoPlayerController? player) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      AspectRatio(
        aspectRatio: player?.value.isInitialized == true ? player!.value.aspectRatio : 16 / 9,
        child: player?.value.isInitialized == true ? VideoPlayer(player!) : const ColoredBox(color: Colors.black),
      ),
    ]);
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
  });

  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final List<RoutineSegment> segments;
  final YoutubePlayerController? originalYoutube;
  final Widget? originalWidget;
  final double loopStart;
  final double loopEnd;

  @override
  State<MotionComparisonViewer> createState() => _MotionComparisonViewerState();
}

class _MotionComparisonViewerState extends State<MotionComparisonViewer> {
  double _position = 0;
  bool _playing = false;
  int _segmentIndex = 0;
  Timer? _loopTimer;
  Timer? _recordedSyncTimer;
  final TransformationController _originalTransformController = TransformationController();
  final TransformationController _recordedTransformController = TransformationController();

  @override
  void initState() {
    super.initState();
    widget.original?.addListener(_onOriginalChanged);
    widget.recorded?.addListener(_onRecordedChanged);
    _position = _minPosition;
    _seekBoth(_minPosition);
  }

  // The recorded clip spans the whole practice session, so once it's present it
  // becomes the timeline's source of truth instead of the original's own range.
  bool get _hasRecorded => widget.recorded != null && widget.recorded!.value.isInitialized;

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
    if (_hasRecorded) {
      return widget.recorded!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.original != null && widget.original!.value.isInitialized) {
      return widget.original!.value.position.inMilliseconds / 1000.0;
    }
    if (widget.originalYoutube != null) {
      return await widget.originalYoutube!.currentTime;
    }
    return 0;
  }

  void _onRecordedChanged() {
    if (!mounted || !_hasRecorded) return;
    final recorded = widget.recorded!;
    final position = recorded.value.position.inMilliseconds / 1000.0;
    final bounded = position.clamp(_minPosition, _maxPosition);
    setState(() {
      _position = bounded;
      _playing = recorded.value.isPlaying;
    });
    if (position >= _maxPosition - 0.15 && recorded.value.isPlaying) {
      unawaited(_loopBackToStart());
    }
  }

  void _onOriginalChanged() {
    // Once a recorded clip is available it drives the timeline instead.
    if (_hasRecorded) return;
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
      final progress = _maxPosition > 0 ? (clamped / _maxPosition).clamp(0.0, 1.0) : 0.0;
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      await widget.original?.seekTo(Duration(milliseconds: (target * 1000).round()));
      if (widget.originalYoutube != null) {
        await widget.originalYoutube!.seekTo(seconds: target, allowSeekAhead: true);
      }
      _syncSegmentHighlight(target);
    } else {
      await widget.original?.seekTo(Duration(milliseconds: (clamped * 1000).round()));
      if (widget.originalYoutube != null) {
        await widget.originalYoutube!.seekTo(seconds: clamped, allowSeekAhead: true);
      }
      _syncSegmentHighlight(clamped);
    }
  }

  /// Jumps straight to a routine segment's start time/speed, independent of
  /// wherever the recorded clip's own timeline currently sits.
  Future<void> _selectSegment(int index) async {
    if (index < 0 || index >= widget.segments.length) return;
    final segment = widget.segments[index];
    setState(() => _segmentIndex = index);
    try {
      await widget.original?.setPlaybackSpeed(segment.speed);
      await widget.originalYoutube?.setPlaybackRate(segment.speed);
      await widget.original?.seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
      if (widget.originalYoutube != null) {
        await widget.originalYoutube!.seekTo(seconds: segment.startSec, allowSeekAhead: true);
      }
      if (_hasRecorded) {
        final span = _rangeEnd - _rangeStart;
        final progress = span > 0 ? ((segment.startSec - _rangeStart) / span).clamp(0.0, 1.0) : 0.0;
        final recordedTarget = progress * _recordedDurationSeconds;
        await widget.recorded?.seekTo(Duration(milliseconds: (recordedTarget * 1000).round()));
        if (mounted) setState(() => _position = recordedTarget.clamp(_minPosition, _maxPosition));
      } else if (mounted) {
        setState(() => _position = segment.startSec.clamp(_minPosition, _maxPosition));
      }
    } catch (_) {}
  }

  Future<void> _loopBackToStart() async {
    await _seekBoth(_minPosition);
    if (!_playing) return;
    if (widget.original != null) {
      await widget.original!.play();
    }
    if (widget.originalYoutube != null) {
      await widget.originalYoutube!.playVideo();
    }
    if (widget.recorded != null) {
      await widget.recorded!.play();
    }
  }

  /// Since the recorded clip and the original may play at different speeds,
  /// periodically re-align the original to the recorded clip's progress (0.0-1.0).
  void _startRecordedSync() {
    _recordedSyncTimer?.cancel();
    if (!_hasRecorded) return;
    _recordedSyncTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!mounted || !_hasRecorded) return;
      final recorded = widget.recorded!;
      final durationMs = recorded.value.duration.inMilliseconds;
      if (durationMs <= 0) return;
      final progress = (recorded.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
      final target = _rangeStart + progress * (_rangeEnd - _rangeStart);
      try {
        if (widget.original != null && widget.original!.value.isInitialized) {
          final current = widget.original!.value.position.inMilliseconds / 1000.0;
          if ((current - target).abs() > 0.35) {
            await widget.original!.seekTo(Duration(milliseconds: (target * 1000).round()));
          }
        }
        if (widget.originalYoutube != null) {
          final current = await widget.originalYoutube!.currentTime;
          if ((current - target).abs() > 0.35) {
            await widget.originalYoutube!.seekTo(seconds: target, allowSeekAhead: true);
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
      await widget.originalYoutube?.pauseVideo();
    } else {
      if (_position < _minPosition) {
        await _seekBoth(_minPosition);
      }
      _loopTimer?.cancel();
      _loopTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
        if (!mounted) return;
        final current = await _currentPlaybackSeconds();
        if (current >= _maxPosition - 0.1) {
          unawaited(_loopBackToStart());
        }
      });
      if (_hasRecorded) _startRecordedSync();
      await widget.original?.play();
      await widget.recorded?.play();
      await widget.originalYoutube?.playVideo();
    }
    if (mounted) setState(() => _playing = !_playing);
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
    _loopTimer?.cancel();
    _recordedSyncTimer?.cancel();
    widget.original?.removeListener(_onOriginalChanged);
    widget.recorded?.removeListener(_onRecordedChanged);
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
            label: Text(sectionLabelForIndex(index)),
            selected: selected,
            onSelected: (_) => _selectSegment(index),
            selectedColor: LoopiColors.purple,
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
              if (isLandscape)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(width: 12),
                      Expanded(child: _videoPane('내 동작', widget.recorded, null, _recordedTransformController, _resetRecordedZoom)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _videoPane('원본 영상', widget.original, widget.originalWidget, _originalTransformController, _resetOriginalZoom)),
                      const SizedBox(height: 12),
                      Expanded(child: _videoPane('내 동작', widget.recorded, null, _recordedTransformController, _resetRecordedZoom)),
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

  Widget _videoPane(String label, VideoPlayerController? player, Widget? customWidget, TransformationController transformController, VoidCallback onResetZoom) {
    final isFallback = player == null || !player.value.isInitialized;
    final fallbackText = label == '내 동작'
        ? '[가상 녹화 테스트 데이터]\n녹화 영상 프리뷰'
        : '원본 영상을 불러오는 중입니다...';

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
          child: InteractiveViewer(
            transformationController: transformController,
            minScale: 1.0,
            maxScale: 4.0,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Container(
                width: 480,
                height: 270,
                color: Colors.black,
                child: isFallback
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            fallbackText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                    : customWidget != null
                        ? AspectRatio(aspectRatio: 16 / 9, child: customWidget)
                        : AspectRatio(
                            aspectRatio: player.value.aspectRatio,
                            child: VideoPlayer(player),
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
    this.segments = const [],
    this.loopStart = 0,
    this.loopEnd = 0,
    this.playbackRate = 1.0,
  });

  final String title;
  final VideoPlayerController? original;
  final VideoPlayerController? recorded;
  final YoutubePlayerController? originalYoutube;
  final List<RoutineSegment> segments;
  final double loopStart;
  final double loopEnd;
  final double playbackRate;

  @override
  State<MotionComparisonViewerPage> createState() => _MotionComparisonViewerPageState();
}

class _MotionComparisonViewerPageState extends State<MotionComparisonViewerPage> {
  @override
  void initState() {
    super.initState();
    _applyRoutinePlaybackRate();
  }

  Future<void> _applyRoutinePlaybackRate() async {
    try {
      await widget.original?.setPlaybackSpeed(widget.playbackRate);
      await widget.originalYoutube?.setPlaybackRate(widget.playbackRate);
    } catch (_) {}
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.original?.dispose();
    widget.recorded?.dispose();
    widget.originalYoutube?.close();
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
          originalYoutube: widget.originalYoutube,
          originalWidget: widget.originalYoutube == null ? null : YoutubePlayer(controller: widget.originalYoutube!),
          segments: widget.segments,
          loopStart: widget.loopStart,
          loopEnd: widget.loopEnd,
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
        _youtube = YoutubePlayerController.fromVideoId(videoId: widget.routine.videoId, autoPlay: false);
      } else if (widget.routine.localDataBytes != null) {
        final url = createMediaBlobUrl(widget.routine.localDataBytes!, 'video/mp4');
        _original = VideoPlayerController.networkUrl(url == null
            ? Uri.dataFromBytes(widget.routine.localDataBytes!, mimeType: 'video/mp4')
            : Uri.parse(url));
        await Future.any([
          _original!.initialize(),
          Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
        ]);
      } else if (widget.routine.localFilePath != null) {
        _original = kIsWeb
            ? VideoPlayerController.networkUrl(Uri.parse(widget.routine.localFilePath!))
            : VideoPlayerController.file(File(widget.routine.localFilePath!));
        await Future.any([
          _original!.initialize(),
          Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
        ]);
      }

      final path = widget.result.recordedPath;
      if (!_hasRecordedFallback && path != null && path.trim().isNotEmpty) {
        try {
          _recorded = kIsWeb
              ? VideoPlayerController.networkUrl(Uri.parse(path))
              : VideoPlayerController.file(File(path));
          await Future.any([
            _recorded!.initialize(),
            Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
          ]);
        } catch (_) {
          _recorded = null;
        }
      }

      final loopStart = widget.result.startTime > 0
          ? widget.result.startTime
          : (widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : 0.0);
      if (_original != null && _original!.value.isInitialized) {
        await _original!.setPlaybackSpeed(widget.result.playbackRate);
        await _original!.seekTo(Duration(milliseconds: (loopStart * 1000).round()));
      }
      if (_youtube != null) {
        await _youtube!.setPlaybackRate(widget.result.playbackRate);
        await _youtube!.seekTo(seconds: loopStart);
      }
      if (_recorded != null && _recorded!.value.isInitialized) {
        await _recorded!.seekTo(Duration.zero);
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
    _youtube?.close();
    _original = null;
    _recorded = null;
    _youtube = null;
    _recordedObjectUrl = null;
    await _load();
  }

  @override
  void dispose() {
    _original?.dispose();
    _recorded?.dispose();
    _youtube?.close();
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
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.of(context).pop();
            },
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
          onPressed: () {
            if (Navigator.canPop(context)) Navigator.of(context).pop();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: MotionComparisonViewer(
          original: _original,
          recorded: _recorded,
          segments: widget.routine.segments,
          originalYoutube: _youtube,
          originalWidget: _youtube == null ? null : YoutubePlayer(controller: _youtube!),
          loopStart: widget.result.startTime > 0 ? widget.result.startTime : (widget.routine.segments.isNotEmpty ? widget.routine.segments.first.startSec : 0),
          loopEnd: widget.result.endTime > 0 ? widget.result.endTime : (widget.routine.segments.isNotEmpty ? widget.routine.segments.last.endSec : 0),
        ),
      ),
    );
  }
}

class AudioPracticeScreen extends StatefulWidget {
  const AudioPracticeScreen({super.key, required this.routine});

  final SavedRoutine routine;

  @override
  State<AudioPracticeScreen> createState() => _AudioPracticeScreenState();
}

class _AudioPracticeScreenState extends State<AudioPracticeScreen> {
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  int _segmentIndex = 0;
  String _step = '준비';
  bool _running = false;
  String? _error;

  Future<void> _showMicrophoneError() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('마이크를 사용할 수 없습니다'),
        content: const Text('마이크가 연결되어 있지 않거나 권한이 없습니다. 마이크 연결 및 권한을 확인해주세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _loadAudioSource() async {
    final path = widget.routine.localFilePath;
    if (path != null && !kIsWeb) {
      await _player.setSourceDeviceFile(path);
    } else if (widget.routine.localDataBytes != null) {
      await _player.setSourceBytes(Uint8List.fromList(widget.routine.localDataBytes!));
    } else if (path != null) {
      await _player.setSourceUrl(path);
    } else {
      throw StateError('오디오 파일을 찾을 수 없습니다.');
    }
  }

  Future<void> _start() async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      await _showMicrophoneError();
      return;
    }
    setState(() {
      _running = true;
      _segmentIndex = 0;
    });
    try {
      for (var index = 0; index < widget.routine.segments.length; index++) {
        if (!mounted) return;
        final segment = widget.routine.segments[index];
        final repeatCount = segment.loopCount == kInfiniteLoop ? 1 : segment.loopCount.clamp(1, 999);
        for (var repeat = 0; repeat < repeatCount; repeat++) {
          if (!mounted) return;
          setState(() {
            _segmentIndex = index;
            _step = repeatCount > 1
                ? '구간 ${index + 1} 원본 재생 (${repeat + 1}/$repeatCount)'
                : '구간 ${index + 1} 원본 재생';
          });
          await _loadAudioSource();
          await _player.setPlaybackRate(segment.speed);
          await _player.seek(Duration(milliseconds: (segment.startSec * 1000).round()));
          await _player.resume();
          final segmentMs = ((segment.endSec - segment.startSec) * 1000 / segment.speed).round();
          await Future<void>.delayed(Duration(milliseconds: segmentMs));
          await _player.pause();
          if (!mounted) return;
          setState(() => _step = '구간 ${index + 1} 내 음성 녹음');
          setState(() => _step = '구간 ${index + 1} 녹음 준비');
          await Future<void>.delayed(const Duration(seconds: 3));
          final directory = await getTemporaryDirectory();
          final path = '${directory.path}/loopi_${DateTime.now().microsecondsSinceEpoch}.m4a';
          if (await _recorder.hasPermission()) {
            await _recorder.start(const RecordConfig(), path: path);
            await Future<void>.delayed(Duration(milliseconds: segmentMs));
            await _recorder.stop();
          }
        }
      }
      if (mounted) setState(() => _step = '연습 완료');
    } catch (error) {
      if (mounted) setState(() => _error = '오디오 연습을 시작하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.routine.segments[_segmentIndex.clamp(0, widget.routine.segments.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.name)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 180,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.graphic_eq, color: LoopiColors.purple, size: 72),
              Text(_step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              Text('${formatMmSs(segment.startSec)} - ${formatMmSs(segment.endSec)}', style: const TextStyle(color: Colors.white60)),
            ]),
          ),
          const SizedBox(height: 20),
          Text('구간 ${_segmentIndex + 1} / ${widget.routine.segments.length}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: const Icon(Icons.mic),
            label: Text(_running ? _step : '섀도잉 연습 시작'),
          ),
        ]),
      ),
    );
  }
}
