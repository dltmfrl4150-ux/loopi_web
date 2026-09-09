import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart' hide PlayerState;

import '../models/routine_models.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/cached_video.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';
import '../utils/youtube_player_factory.dart';
import '../widgets/app_logo.dart';
import '../widgets/favorite_icon_button.dart';
import '../widgets/highlight_interval.dart';

class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({
    super.key,
    required this.routine,
    this.library,
    this.routines,
    this.repeatPlaylist = true,
    this.embedded = false,
  });

  final SavedRoutine routine;
  final RoutineLibrary? library;
  final List<SavedRoutine>? routines;
  final bool repeatPlaylist;

  /// When true, omit the inner AppBar so a parent screen can own the header.
  final bool embedded;

  List<SavedRoutine> get playlist =>
      (routines == null || routines!.isEmpty) ? [routine] : List.unmodifiable(routines!);

  @override
  State<PracticeModeScreen> createState() => PracticeModeScreenState();
}

class PracticeModeScreenState extends State<PracticeModeScreen> {
  late final YoutubePlayerController _youtubePlayer;
  bool _youtubeInitialized = false;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  Timer? _delayTimer;
  StreamSubscription<YoutubeVideoState>? _stateSub;
  StreamSubscription<YoutubePlayerValue>? _youtubeValueSub;
  int _countdown = 3;
  bool _ready = false;
  int _segmentIndex = 0;
  int _playsRemaining = 1;
  int _playlistIndex = 0;
  DateTime? _ignoreUntil;
  bool _delayPending = false;
  bool _isPlaying = false;
  bool _playPauseBusy = false;
  bool _isSeeking = false;
  // Guards segment/routine transitions so a burst of position callbacks can't
  // re-enter the advance logic while a previous transition is still in flight.
  bool _isAdvancing = false;
  String? _mediaObjectUrl;
  bool _disposing = false;

  bool get _youtubeAlive => !_disposing && _youtubeInitialized && mounted;

  Future<T?> _yt<T>(Future<T> Function() action) {
    return safeYoutubePlayerCall(action, isAlive: () => _youtubeAlive);
  }

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  List<SavedRoutine> get _playlist => widget.playlist;
  SavedRoutine get _currentRoutine => _playlist[_playlistIndex];
  RoutineSegment get _segment => _currentRoutine.segments[_segmentIndex];
  bool get _isGroupPlayback => _playlist.length > 1;
  SavedRoutine get _libraryRoutine => widget.library?.byId(_currentRoutine.id) ?? _currentRoutine;

  bool get _isYouTubeShortsUrl {
    final url = _currentRoutine.videoUrl.toLowerCase();
    return url.contains('/shorts/');
  }

  double get _playerAspectRatio {
    if (_currentRoutine.sourceType == SourceType.audio) return 16 / 9;
    if (_isYouTubeShortsUrl) return 9 / 16;
    final player = _videoPlayer;
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

  @override
  void initState() {
    super.initState();
    _playlistIndex = _playlist.indexWhere((routine) => routine.id == widget.routine.id);
    if (_playlistIndex < 0) _playlistIndex = 0;
    _segmentIndex = 0;
    _playsRemaining = _currentRoutine.segments.first.loopCount;

    _initializePlayer();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() {
          _countdown = 0;
          _ready = true;
          _isPlaying = true;
        });
        _startSegment(0);
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  Future<void> _initializePlayer() async {
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          if (_inWidgetTest) break;
          final videoId = resolveYoutubeVideoId(
            videoId: _currentRoutine.videoId,
            videoUrl: _currentRoutine.videoUrl,
          );
          if (videoId == null || videoId.isEmpty) {
            throw StateError('YouTube 영상 ID가 없습니다.');
          }
          _youtubePlayer = createLoopiYoutubeController(
            videoId: videoId,
            autoPlay: false,
            startSeconds: _currentRoutine.segments.first.startSec,
          );
          _youtubeInitialized = true;
          _youtubeValueSub = listenYoutubeStream(
            _youtubePlayer.stream,
            (value) {
              final playing = value.playerState == PlayerState.playing ||
                  value.playerState == PlayerState.buffering;
              if (_isPlaying != playing) {
                setState(() => _isPlaying = playing);
              }
            },
            isAlive: () => _youtubeAlive,
          );
          _stateSub = listenYoutubeStream(
            _youtubePlayer.videoStateStream,
            (state) {
              if (!_ready) return;
              _onTime(state.position.inMilliseconds / 1000.0);
            },
            isAlive: () => _youtubeAlive,
          );
          break;
        case SourceType.localVideo:
          if (_currentRoutine.localFilePath != null && !kIsWeb) {
            _videoPlayer = VideoPlayerController.file(File(_currentRoutine.localFilePath!));
            await Future.any([
              _videoPlayer!.initialize(),
              Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
            ]);
            _videoPlayer!.addListener(_onVideoPlayerUpdate);
            _videoPlayer!.addListener(_onLocalVideoPlayState);
          } else if (_currentRoutine.localDataBytes != null) {
            _mediaObjectUrl = createMediaBlobUrl(_currentRoutine.localDataBytes!, 'video/mp4');
            final uri = _mediaObjectUrl == null
                ? Uri.dataFromBytes(_currentRoutine.localDataBytes!, mimeType: 'video/mp4')
                : Uri.parse(_mediaObjectUrl!);
            _videoPlayer = VideoPlayerController.networkUrl(uri);
            await Future.any([
              _videoPlayer!.initialize(),
              Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
            ]);
            _videoPlayer!.addListener(_onVideoPlayerUpdate);
            _videoPlayer!.addListener(_onLocalVideoPlayState);
          } else if (_currentRoutine.localFilePath != null) {
            _videoPlayer = createCachedNetworkVideo(Uri.parse(_currentRoutine.localFilePath!));
            await Future.any([
              _videoPlayer!.initialize(),
              Future.delayed(const Duration(seconds: 30), () => throw Exception('Video initialization timeout')),
            ]);
            _videoPlayer!.addListener(_onVideoPlayerUpdate);
            _videoPlayer!.addListener(_onLocalVideoPlayState);
          }
          break;
        case SourceType.audio:
          if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
            _audioPlayer = AudioPlayer();
            if (_currentRoutine.localFilePath != null && !kIsWeb) {
              await _audioPlayer!.setSourceDeviceFile(_currentRoutine.localFilePath!);
            } else if (_currentRoutine.localDataBytes != null) {
              await _audioPlayer!.setSourceBytes(Uint8List.fromList(_currentRoutine.localDataBytes!));
            } else {
              await _audioPlayer!.setSourceUrl(_currentRoutine.localFilePath!);
            }
            _audioPlayer!.onPositionChanged.listen((position) {
              if (!_ready) return;
              _onTime(position.inMilliseconds / 1000.0);
            });
            _audioPlayer!.onPlayerStateChanged.listen((state) {
              if (!mounted) return;
              final playing = '$state'.contains('playing');
              if (_isPlaying != playing) {
                setState(() => _isPlaying = playing);
              }
            });
          }
          break;
      }
    } catch (error) {
      // Log error but don't crash the app
      print('Player initialization error: $error');
      // Ensure loading state is cleared even on error
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  void _onVideoPlayerUpdate() {
    if (_videoPlayer == null || !_ready) return;
    final position = _videoPlayer!.value.position.inMilliseconds / 1000.0;
    _onTime(position);
  }

  void _onLocalVideoPlayState() {
    if (!mounted || _videoPlayer == null) return;
    final playing = _videoPlayer!.value.isPlaying;
    if (_isPlaying != playing) {
      setState(() => _isPlaying = playing);
    }
  }

  Future<void> _startRoutine(int index, {bool immediate = true}) async {
    if (index < 0 || index >= _playlist.length) return;
    _playlistIndex = index;
    _segmentIndex = 0;
    _playsRemaining = _currentRoutine.segments.first.loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 600));
    _isSeeking = true;
    _isAdvancing = false;
    setState(() {});
    if (_inWidgetTest) return;

    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          final videoId = resolveYoutubeVideoId(
            videoId: _currentRoutine.videoId,
            videoUrl: _currentRoutine.videoUrl,
          );
          if (videoId == null) {
            throw StateError('YouTube 영상 ID가 없습니다.');
          }
          await _yt(() => _youtubePlayer.loadVideoById(videoId: videoId));
          if (!_youtubeAlive) return;
          await _yt(() => _youtubePlayer.setPlaybackRate(_currentRoutine.segments.first.speed));
          await _yt(
            () => _youtubePlayer.seekTo(
              seconds: _currentRoutine.segments.first.startSec,
              allowSeekAhead: true,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 120));
          _isSeeking = false;
          if (immediate && _youtubeAlive) {
            await _yt(() => _youtubePlayer.playVideo());
            if (mounted) setState(() => _isPlaying = true);
          }
          break;
        case SourceType.localVideo:
          if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
            await _videoPlayer?.dispose();
            if (_currentRoutine.localFilePath != null && !kIsWeb) {
              _videoPlayer = VideoPlayerController.file(File(_currentRoutine.localFilePath!));
            } else if (_currentRoutine.localDataBytes != null) {
              _mediaObjectUrl = createMediaBlobUrl(_currentRoutine.localDataBytes!, 'video/mp4');
              _videoPlayer = VideoPlayerController.networkUrl(
                _mediaObjectUrl == null
                    ? Uri.dataFromBytes(_currentRoutine.localDataBytes!, mimeType: 'video/mp4')
                    : Uri.parse(_mediaObjectUrl!),
              );
            } else {
              _videoPlayer = createCachedNetworkVideo(Uri.parse(_currentRoutine.localFilePath!));
            }
            await _videoPlayer!.initialize();
            await _videoPlayer!.setPlaybackSpeed(_currentRoutine.segments.first.speed);
            await _videoPlayer!.seekTo(Duration(milliseconds: (_currentRoutine.segments.first.startSec * 1000).toInt()));
            await Future<void>.delayed(const Duration(milliseconds: 120));
            _isSeeking = false;
            if (immediate) {
              await _videoPlayer!.play();
              if (mounted) setState(() => _isPlaying = true);
            }
            _videoPlayer!.addListener(_onVideoPlayerUpdate);
            _videoPlayer!.addListener(_onLocalVideoPlayState);
          }
          break;
        case SourceType.audio:
          if (_currentRoutine.localFilePath != null || _currentRoutine.localDataBytes != null) {
            await _audioPlayer?.dispose();
            _audioPlayer = AudioPlayer();
            if (_currentRoutine.localFilePath != null && !kIsWeb) {
              await _audioPlayer!.setSourceDeviceFile(_currentRoutine.localFilePath!);
            } else if (_currentRoutine.localDataBytes != null) {
              await _audioPlayer!.setSourceBytes(Uint8List.fromList(_currentRoutine.localDataBytes!));
            } else {
              await _audioPlayer!.setSourceUrl(_currentRoutine.localFilePath!);
            }
            await _audioPlayer!.setPlaybackRate(_currentRoutine.segments.first.speed);
            await _audioPlayer!.seek(Duration(milliseconds: (_currentRoutine.segments.first.startSec * 1000).toInt()));
            await Future<void>.delayed(const Duration(milliseconds: 120));
            _isSeeking = false;
            if (immediate) {
              await _audioPlayer!.resume();
              if (mounted) setState(() => _isPlaying = true);
            }
          }
          break;
      }
    } catch (_) {
      _isSeeking = false;
    }

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready || _isSeeking) return;
      try {
        final time = await _getCurrentTime();
        _onTime(time);
      } catch (_) {}
    });
  }

  Future<double> _getCurrentTime() async {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        return await _yt(() => _youtubePlayer.currentTime) ?? 0;
      case SourceType.localVideo:
        final position = _videoPlayer?.value.position.inMilliseconds;
        return position != null ? position / 1000.0 : 0;
      case SourceType.audio:
        final position = await _audioPlayer?.getCurrentPosition();
        final positionMs = position?.inMilliseconds;
        return positionMs != null ? positionMs / 1000.0 : 0;
    }
  }

  Future<void> _startSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    _segmentIndex = index;
    _playsRemaining = _currentRoutine.segments[index].loopCount;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 500));
    _isSeeking = true;
    _isAdvancing = false;
    setState(() {});
    if (_inWidgetTest) return;
    try {
      // ✨ 세그먼트의 delaySec를 읽어와 대기 시간 계산
      final delay = _currentRoutine.segments[index].delaySec;
      final waitTime = Duration(milliseconds: 120 + (delay * 1000));

      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.pauseVideo());
          await _yt(() => _youtubePlayer.setPlaybackRate(_currentRoutine.segments[index].speed));
          await _yt(
            () => _youtubePlayer.seekTo(
              seconds: _currentRoutine.segments[index].startSec,
              allowSeekAhead: true,
            ),
          );
          await Future<void>.delayed(waitTime);
          _isSeeking = false;
          if (!_youtubeAlive) return;
          await _yt(() => _youtubePlayer.playVideo());
          if (mounted) setState(() => _isPlaying = true);
          break;
        case SourceType.localVideo:
          await _videoPlayer?.pause();
          await _videoPlayer?.setPlaybackSpeed(_currentRoutine.segments[index].speed);
          await _videoPlayer?.seekTo(Duration(milliseconds: (_currentRoutine.segments[index].startSec * 1000).toInt()));
          await Future<void>.delayed(waitTime);
          _isSeeking = false;
          await _videoPlayer?.play();
          if (mounted) setState(() => _isPlaying = true);
          break;
        case SourceType.audio:
          await _audioPlayer?.pause();
          await _audioPlayer?.setPlaybackRate(_currentRoutine.segments[index].speed);
          await _audioPlayer?.seek(Duration(milliseconds: (_currentRoutine.segments[index].startSec * 1000).toInt()));
          await Future<void>.delayed(waitTime);
          _isSeeking = false;
          await _audioPlayer?.resume();
          if (mounted) setState(() => _isPlaying = true);
          break;
      }
    } catch (_) {
      _isSeeking = false;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_ready || _isSeeking) return;
      try {
        final time = await _getCurrentTime();
        _onTime(time);
      } catch (_) {}
    });
  }

  Future<void> _jumpToSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    await _startSegment(index);
  }

  /// Pauses YouTube / video / audio so background playback cannot leak into
  /// another screen (e.g. Practice Mode).
  Future<void> pausePlayback() async {
    if (_inWidgetTest) {
      _isPlaying = false;
      return;
    }
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.pauseVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.pause();
          break;
        case SourceType.audio:
          await _audioPlayer?.pause();
          break;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isPlaying = false);
    } else {
      _isPlaying = false;
    }
  }

  Future<void> _togglePlayPause() async {
    if (_inWidgetTest || !_ready || _playPauseBusy || _disposing) return;
    _playPauseBusy = true;
    try {
      if (_isPlaying) {
        await pausePlayback();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            if (!_youtubeAlive) return;
            await _yt(() => _youtubePlayer.playVideo());
            break;
          case SourceType.localVideo:
            if (_videoPlayer == null || _videoPlayer?.value.isInitialized != true) return;
            await _videoPlayer!.play();
            break;
          case SourceType.audio:
            if (_audioPlayer == null) return;
            await _audioPlayer!.resume();
            break;
        }
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (_) {
    } finally {
      _playPauseBusy = false;
    }
  }

  Future<void> _seekRelative(double seconds) async {
    if (_inWidgetTest) return;
    try {
      final currentTime = await _getCurrentTime();
      final newTime = currentTime + seconds;
      final clampedTime = newTime.clamp(_segment.startSec, _segment.endSec);
      
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(
            () => _youtubePlayer.seekTo(seconds: clampedTime, allowSeekAhead: true),
          );
          break;
        case SourceType.localVideo:
          await _videoPlayer?.seekTo(Duration(milliseconds: (clampedTime * 1000).toInt()));
          break;
        case SourceType.audio:
          await _audioPlayer?.seek(Duration(milliseconds: (clampedTime * 1000).toInt()));
          break;
      }
    } catch (_) {}
  }

  Future<void> _skipToPreviousSegment() async {
    final prevIndex = _segmentIndex > 0 ? _segmentIndex - 1 : 0;
    await _jumpToSegment(prevIndex);
  }

  Future<void> _skipToNextSegment() async {
    final nextIndex = _segmentIndex + 1 < _currentRoutine.segments.length ? _segmentIndex + 1 : 0;
    await _jumpToSegment(nextIndex);
  }

  Future<void> _previousRoutine() async {
    final prev = _playlistIndex - 1;
    if (prev < 0) {
      if (_isGroupPlayback && widget.repeatPlaylist) {
        await _startRoutine(_playlist.length - 1, immediate: true);
      }
      return;
    }
    await _startRoutine(prev, immediate: true);
  }

  Future<void> _nextRoutine() async {
    final next = _playlistIndex + 1;
    if (next >= _playlist.length) {
      if (_isGroupPlayback && widget.repeatPlaylist) {
        await _startRoutine(0, immediate: true);
      }
      return;
    }
    await _startRoutine(next, immediate: true);
  }

  // Detects end-of-segment: `time + 0.12 < segmentEnd` means "not there yet", so
  // this fires once `time >= segmentEnd - 0.12`, tolerant of ms/float rounding.
  void _onTime(double time) {
    if (!_ready || _delayPending || _isSeeking || _isAdvancing) return;
    if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;

    final segmentStart = _segment.startSec;
    final segmentEnd = _segment.endSec;
    if (time < segmentStart - 0.1) return;
    if (time + 0.12 < segmentEnd) return;

    unawaited(_advancePastSegment());
  }

  /// Repeats the current segment, moves on to the next segment/routine, or
  /// stops once everything is done. try/finally guarantees `_isAdvancing`
  /// always clears, even if an awaited player call throws.
  Future<void> _advancePastSegment() async {
    if (_isAdvancing) return;
    _isAdvancing = true;
    try {
      final delaySec = _segment.delaySec;

      // 1. 무한 반복 모드인 경우 현재 구간 무한 반복
      if (_segment.loopCount == kInfiniteLoop) {
        await _replayWithDelay(delaySec);
        return;
      }

      // 2. 지정된 반복 횟수가 남아있는 경우 현재 구간 재반복
      if (_playsRemaining > 1) {
        _playsRemaining--;
        await _replayWithDelay(delaySec);
        return;
      }

      // 3. 반복 횟수를 다 채운 경우 다음 구간(B, C...)으로 전진!
      final nextIndex = _segmentIndex + 1;
      if (nextIndex < _currentRoutine.segments.length) {
        await _startSegment(nextIndex);
      } else {
        // 마지막 구간까지 완료되면 재생을 정지합니다.
        setState(() => _isPlaying = false);
        unawaited(_yt(() => _youtubePlayer.pauseVideo()));
        _videoPlayer?.pause();
        _audioPlayer?.pause();
      }
    } finally {
      _isAdvancing = false;
    }
  }

  Future<void> _replayCurrent() async {
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 280));
    if (_inWidgetTest) return;
    _isSeeking = true;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.setPlaybackRate(_segment.speed));
          await _yt(
            () => _youtubePlayer.seekTo(
              seconds: _segment.startSec,
              allowSeekAhead: true,
            ),
          );
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(_segment.speed);
          await _videoPlayer?.seekTo(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(_segment.speed);
          await _audioPlayer?.seek(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
          break;
      }
    } catch (_) {}
    _isSeeking = false;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.playVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.resume();
          break;
      }
    } catch (_) {}
  }

  Future<void> _replayWithDelay(int delaySec) async {
    await _waitDelay(delaySec);
    if (!_ready || !mounted) return;
    await _replayCurrent();
  }

  Future<void> _startSegmentWithDelay(int index, int delaySec) async {
    await _waitDelay(delaySec);
    if (!_ready || !mounted) return;
    _startSegment(index);
  }

  Future<void> _advanceToNextRoutine(int delaySec) async {
    if (!_ready) return;
    await _waitDelay(delaySec);
    if (!_ready || !mounted) return;

    if (_playlistIndex + 1 < _playlist.length) {
      await _startRoutine(_playlistIndex + 1, immediate: true);
      return;
    }

    if (widget.repeatPlaylist) {
      await _startRoutine(0, immediate: true);
      return;
    }

    _pollTimer?.cancel();
    if (!_inWidgetTest) {
      try {
        switch (_currentRoutine.sourceType) {
          case SourceType.youtube:
            await _yt(() => _youtubePlayer.pauseVideo());
            break;
          case SourceType.localVideo:
            await _videoPlayer?.pause();
            break;
          case SourceType.audio:
            await _audioPlayer?.pause();
            break;
        }
      } catch (_) {}
    }
  }

  Future<void> _waitDelay(int delaySec) async {
    if (delaySec <= 0 || _inWidgetTest) return;
    _delayPending = true;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.pauseVideo());
          break;
        case SourceType.localVideo:
          _videoPlayer?.pause();
          break;
        case SourceType.audio:
          _audioPlayer?.pause();
          break;
      }
      // ✨ 실질적으로 딜레이 초만큼 대기하는 코드가 빠져 있었습니다!
      await Future.delayed(Duration(seconds: delaySec));
      if (!_youtubeAlive && _currentRoutine.sourceType == SourceType.youtube) {
        return;
      }
    } catch (_) {
    } finally {
      _delayPending = false;
    }
  }

  Widget _playerControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_isGroupPlayback)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_playlistIndex + 1} / ${_playlist.length}  •  ${_currentRoutine.name}',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_isGroupPlayback)
                IconButton(
                  onPressed: _previousRoutine,
                  icon: const Icon(Icons.skip_previous_rounded),
                  tooltip: '이전 루틴',
                  color: Colors.white,
                ),
              IconButton(
                onPressed: _skipToPreviousSegment,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                tooltip: '이전 구간',
                color: Colors.white,
              ),
              IconButton(
                onPressed: () => _seekRelative(-5),
                icon: const Icon(Icons.replay_5),
                tooltip: 'player.rewind_5s'.tr(),
                color: Colors.white,
              ),
              Container(
                decoration: BoxDecoration(
                  color: LoopiColors.purple,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  tooltip: _isPlaying ? 'player.pause'.tr() : 'player.play'.tr(),
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () => _seekRelative(5),
                icon: const Icon(Icons.forward_5),
                tooltip: 'player.forward_5s'.tr(),
                color: Colors.white,
              ),
              IconButton(
                onPressed: _skipToNextSegment,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                tooltip: '다음 구간',
                color: Colors.white,
              ),
              if (_isGroupPlayback)
                IconButton(
                  onPressed: _nextRoutine,
                  icon: const Icon(Icons.skip_next_rounded),
                  tooltip: '다음 루틴',
                  color: Colors.white,
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _ready = false;
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _delayTimer?.cancel();
    _stateSub?.cancel();
    _youtubeValueSub?.cancel();
    _stateSub = null;
    _youtubeValueSub = null;
    if (_youtubeInitialized) {
      unawaited(closeYoutubePlayerSafely(_youtubePlayer));
    }
    try {
      _videoPlayer?.pause();
    } catch (_) {}
    _videoPlayer?.dispose();
    try {
      _audioPlayer?.stop();
    } catch (_) {}
    _audioPlayer?.dispose();
    revokeMediaBlobUrl(_mediaObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        return _buildYouTubeScaffold();
      case SourceType.localVideo:
        return _buildVideoScaffold();
      case SourceType.audio:
        return _buildAudioScaffold();
    }
  }

  Widget _buildYouTubeScaffold() {
    if (!_youtubeInitialized) {
      return _buildMainScaffold(mediaWidget: const ColoredBox(color: Colors.black));
    }
    return YoutubePlayerScaffold(
      controller: _youtubePlayer,
      aspectRatio: _playerAspectRatio,
      builder: (context, player) {
        return _buildMainScaffold(
          mediaWidget: _inWidgetTest
              ? const ColoredBox(color: Colors.black)
              : player,
        );
      },
    );
  }

  Widget _intervalButtons() {
    final count = _currentRoutine.segments.length;
    if (count == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final maxD = box.maxHeight.clamp(0.0, 96.0);
        if (!maxD.isFinite || maxD <= 0 || box.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        var diameter = maxD;
        if (count > 1) {
          final fit = box.maxWidth / (1.5 * count - 0.5);
          if (fit < diameter) diameter = fit;
        } else if (diameter > box.maxWidth) {
          diameter = box.maxWidth;
        }
        diameter = diameter.clamp(24.0, maxD);
        final gap = count <= 1 ? 0.0 : diameter * 0.5;
        final buttons = <Widget>[
          for (var index = 0; index < count; index++) ...[
            if (index > 0) SizedBox(width: gap),
            SizedBox(
              width: diameter,
              height: diameter,
              child: _sectionCircleButton(index),
            ),
          ],
        ];
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: buttons,
        );
        final totalWidth = count * diameter + (count - 1) * gap;
        if (totalWidth <= box.maxWidth) {
          return Center(child: row);
        }
        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          ),
        );
      },
    );
  }

  Widget _sectionCircleButton(int index) {
    final highlight = _currentRoutine.segments[index].isHighlight;
    return Material(
      color: index == _segmentIndex ? LoopiColors.purple : const Color(0xFF2A2438),
      shape: CircleBorder(
        side: highlight
            ? const BorderSide(color: kHighlightGold, width: 2.4)
            : BorderSide.none,
      ),
      shadowColor: highlight ? kHighlightGold : Colors.transparent,
      elevation: highlight ? 5 : 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _jumpToSegment(index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    sectionLabelForIndex(index),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (highlight)
              const Positioned(
                top: 2,
                right: 2,
                child: HighlightCrown(size: 11),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoScaffold() {
    return _buildMainScaffold(
      mediaWidget: _videoPlayer != null && _videoPlayer!.value.isInitialized
          ? VideoPlayer(_videoPlayer!)
          : const ColoredBox(color: Colors.black),
    );
  }

  Widget _buildAudioScaffold() {
    return _buildMainScaffold(
      mediaWidget: _buildAudioPlayerWidget(),
    );
  }

  Widget _buildAudioPlayerWidget() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq_rounded, color: LoopiColors.purple, size: 80),
          const SizedBox(height: 16),
          Text(
            'studio.audio_mode'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 8),
          if (_currentRoutine.fileName != null)
            Text(
              _currentRoutine.fileName!,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildMainScaffold({required Widget mediaWidget}) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        const metadataHeight = 40.0;
        final controlsHeight = _isGroupPlayback ? 120.0 : 88.0;
        // Previous layout: video capped at 55% and the interval strip Expanded
        // into the leftover. Keep 40% of that leftover for intervals so the
        // player can use the rest.
        final previousVideoCap = constraints.maxHeight * 0.55;
        final previousLeftover = (constraints.maxHeight - previousVideoCap - metadataHeight - controlsHeight)
            .clamp(40.0, constraints.maxHeight);
        final intervalHeight = (previousLeftover * 0.4).clamp(40.0, previousLeftover);

        return Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
                  child: AspectRatio(
                    aspectRatio: _playerAspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.flip(
                          flipX: _currentRoutine.isMirroredOn &&
                              _currentRoutine.sourceType != SourceType.audio,
                          child: mediaWidget,
                        ),
                        if (!_ready)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'player.get_ready'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                CircleAvatar(
                                  radius: 42,
                                  backgroundColor: LoopiColors.purple,
                                  child: Text(
                                    '$_countdown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: metadataHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${sectionLabelForIndex(_segmentIndex)}  '
                    '${formatMmSs(_segment.startSec)} – ${formatMmSs(_segment.endSec)}  '
                    '${formatSpeedLabel(_segment.speed)}  ${formatLoopLabel(_segment.loopCount)}  '
                    '${formatDelayLabel(_segment.delaySec)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: intervalHeight,
              child: _intervalButtons(),
            ),
            _playerControls(),
          ],
        );
      },
    );

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: LoopiColors.purple,
          brightness: Brightness.dark,
        ),
      ),
      child: widget.embedded
          ? ColoredBox(color: const Color(0xFF120F1C), child: content)
          : Scaffold(
              backgroundColor: const Color(0xFF120F1C),
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                title: Row(
                  children: [
                    const AppLogo(height: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentRoutine.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (widget.library != null)
                    FavoriteButton(
                      initialValue: _libraryRoutine.isFavorite,
                      onChanged: (value) async {
                        await widget.library!.setFavorite(_currentRoutine.id, value);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(value ? '즐겨찾기에 추가했습니다.' : '즐겨찾기에서 삭제했습니다.')),
                        );
                      },
                    ),
                ],
              ),
              body: content,
            ),
    );
  }
}
