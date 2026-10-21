import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart' hide PlayerState;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../models/routine_models.dart';
import '../services/player_remote_control.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/browser_fullscreen.dart';
import '../utils/cached_video.dart';
import '../utils/time_format.dart';
import '../utils/media_blob.dart';
import '../utils/playback_seek_keys.dart';
import '../utils/routine_play_gate.dart';
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

class PracticeModeScreenState extends State<PracticeModeScreen>
    implements PlayerRemoteHandler {
  late final YoutubePlayerController _youtubePlayer;
  bool _youtubeInitialized = false;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  Timer? _delayTimer;
  StreamSubscription<YoutubePlayerValue>? _youtubeValueSub;
  Completer<void>? _delayCompleter;
  int _delayEpoch = 0;
  int _countdown = 0;
  bool _delayCountdownActive = false;
  bool _userStartInFlight = false;
  bool _playWhenReady = false;
  bool _ready = false;
  int _segmentIndex = 0;
  int _playlistIndex = 0;
  DateTime? _ignoreUntil;
  bool _delayPending = false;
  bool _isPlaying = false;
  bool _isSeeking = false;
  /// True while Start, playback rate, and playVideo run as one procedure.
  bool _applyingSection = false;
  /// True after that procedure has run once. Later plays are resumes.
  bool _entryApplied = false;
  bool _holdingNativePlay = false;
  bool _rateFixInFlight = false;
  Stopwatch? _playDiagWatch;
  bool _playDiagSawPlaying = false;
  bool _playDiagSawPosition = false;
  double? _playDiagFirstPosition;
  bool _segmentFinished = false;
  bool _pollBusy = false;
  int _pollEpoch = 0;
  int _loopsCompleted = 0;
  /// Wall-clock fallback when YouTube `currentTime` stalls on web.
  DateTime? _sectionWallStart;
  double _sectionAnchorSec = 0;
  double _sectionSpeed = 1;
  double _lastReportedSec = 0;
  DateTime? _lastReportedAt;
  // Guards segment/routine transitions so a burst of position callbacks can't
  // re-enter the advance logic while a previous transition is still in flight.
  bool _isAdvancing = false;
  String? _mediaObjectUrl;
  bool _disposing = false;
  /// Cached media length so section.endSec past EOF (Shorts) still advances.
  double? _cachedMediaDurationSec;
  final TransformationController _transformationController = TransformationController();
  /// In-app fullscreen: video fills the body; controls overlay. Not cleared on segment change.
  bool _isFullscreen = false;

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (kIsWeb) {
      if (_isFullscreen) {
        // 브라우저 전체화면 진입 (OS 레벨에서 탭, 주소창 모두 숨김)
        requestBrowserFullscreen();
      } else {
        // 브라우저 전체화면 해제
        exitBrowserFullscreen();
      }
    }
  }

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
    PlayerRemoteControl.instance.attach(this);
    _playlistIndex = _playlist.indexWhere((routine) => routine.id == widget.routine.id);
    if (_playlistIndex < 0) _playlistIndex = 0;
    _segmentIndex = 0;
    _loopsCompleted = 0;
    _segmentFinished = false;
    _isPlaying = false;
    HardwareKeyboard.instance.addHandler(_handlePlaybackSeekKey);

    if (_inWidgetTest) {
      _ready = true;
      return;
    }
    unawaited(_initializePlayer());
  }

  void _markControlsReady() {
    if (!mounted || _disposing) return;
    if (!_ready) setState(() => _ready = true);
    if (!_playWhenReady || _entryApplied || _userStartInFlight) return;
    _playWhenReady = false;
    unawaited(_startPlaybackFromUser());
  }

  void _beginPlayDiag() {
    _playDiagWatch = Stopwatch()..start();
    _playDiagSawPlaying = false;
    _playDiagSawPosition = false;
    _playDiagFirstPosition = null;
    _logPlayDiag('play_button');
  }

  void _logPlayDiag(String event, {String extra = ''}) {
    if (!kDebugMode) return;
    final elapsed = _playDiagWatch?.elapsedMilliseconds ?? -1;
    debugPrint('[PLAY_DIAG] event=$event elapsed_ms=$elapsed$extra');
  }

  String _youtubeStateLabel() {
    if (!_youtubeInitialized) return 'none';
    return _youtubePlayer.value.playerState.name;
  }

  void _notePlayDiagPosition(double seconds) {
    if (!kDebugMode || _playDiagWatch == null || _playDiagSawPosition) return;
    final first = _playDiagFirstPosition;
    if (first == null) {
      _playDiagFirstPosition = seconds;
      return;
    }
    if (seconds > first + 0.05) {
      _playDiagSawPosition = true;
      _logPlayDiag('position_advanced', extra: ' from=$first to=$seconds');
    }
  }

  /// Counts the section's saved delay, then returns. Does not play.
  Future<void> _runVisibleDelay(int seconds) async {
    if (seconds <= 0 || _inWidgetTest) return;
    _countdownTimer?.cancel();
    final epoch = ++_delayEpoch;
    final completer = Completer<void>();
    _delayCompleter = completer;
    _delayCountdownActive = true;
    _countdown = seconds;
    if (mounted) setState(() {});
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (epoch != _delayEpoch) {
        timer.cancel();
        return;
      }
      if (!mounted || _disposing) {
        timer.cancel();
        _finishDelayWait(epoch);
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        _countdown = 0;
        _delayCountdownActive = false;
        if (mounted) setState(() {});
        _finishDelayWait(epoch);
        return;
      }
      setState(() => _countdown -= 1);
    });
    await completer.future;
  }

  void _finishDelayWait(int epoch) {
    if (epoch != _delayEpoch) return;
    _delayCountdownActive = false;
    final pending = _delayCompleter;
    _delayCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _cancelDelayCountdown() {
    _delayEpoch++;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdown = 0;
    _delayCountdownActive = false;
    final pending = _delayCompleter;
    _delayCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Play button: wait for this section's delaySec, then start the routine once.
  Future<void> _startPlaybackFromUser() async {
    if (_userStartInFlight || _delayCountdownActive || _applyingSection || _entryApplied || _disposing) {
      return;
    }
    _userStartInFlight = true;
    try {
      final delay = _currentRoutine.segments.isEmpty
          ? 0
          : sectionPlaybackDelaySeconds(_currentRoutine.segments.first.delaySec);
      _logPlayDiag('routine_start');
      _logPlayDiag('delay_checked', extra: ' delay_sec=$delay');
      await _runVisibleDelay(delay);
      if (!mounted || _disposing || _entryApplied) return;
      await _playInitialSection();
    } finally {
      _userStartInFlight = false;
    }
  }

  /// Countdown finished: seek to section start, play, then apply the rate.
  /// The play/pause icon updates only from the player listener.
  Future<void> _playInitialSection() async {
    if (_applyingSection || !mounted || _disposing || _currentRoutine.segments.isEmpty) {
      return;
    }
    final stateName = _youtubeStateLabel();
    _logPlayDiag('player_ready_wait_start', extra: ' state=$stateName budget_ms=${kYoutubeStatePollBudget.inMilliseconds}');
    _logPlayDiag('player_ready_wait_end', extra: ' state=$stateName');
    if (_applyingSection || !mounted || _disposing || _currentRoutine.segments.isEmpty) {
      return;
    }
    _applyingSection = true;
    _segmentIndex = 0;
    _loopsCompleted = 0;
    _segmentFinished = false;
    final segment = _currentRoutine.segments.first;
    final speed = segment.speed <= 0 ? 1.0 : segment.speed;
    _anchorSectionClock(atSec: segment.startSec);
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          if (!_youtubeInitialized) return;
          _logPlayDiag('seek_start', extra: ' start_sec=${segment.startSec}');
          await _youtubePlayer.seekTo(seconds: segment.startSec, allowSeekAhead: true);
          _logPlayDiag('seek_end');
          _logPlayDiag('play_command');
          await _youtubePlayer.playVideo();
          _logPlayDiag('rate_start', extra: ' speed=$speed');
          await _applyVerifiedYoutubeRate(speed);
          _logPlayDiag('rate_end');
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          await _videoPlayer?.seekTo(
            Duration(milliseconds: (segment.startSec * 1000).toInt()),
          );
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          await _audioPlayer?.seek(
            Duration(milliseconds: (segment.startSec * 1000).toInt()),
          );
          await _audioPlayer?.resume();
          break;
      }
      _entryApplied = true;
      if (mounted && _playerReportsPlaying) {
        setState(() => _isPlaying = true);
      }
      _logPlayDiag('routine_state_updated', extra: ' playing=$_isPlaying');
    } catch (e) {
      debugPrint('[LOOPI] initial playVideo failed: $e');
    } finally {
      _applyingSection = false;
    }
    if (!mounted || _disposing || !_entryApplied) return;
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 500));
    _armBoundaryPoll();
  }

  bool get _playerReportsPlaying {
    switch (_currentRoutine.sourceType) {
      case SourceType.youtube:
        if (!_youtubeInitialized) return false;
        final state = _youtubePlayer.value.playerState;
        return state == PlayerState.playing || state == PlayerState.buffering;
      case SourceType.localVideo:
        return _videoPlayer?.value.isPlaying ?? false;
      case SourceType.audio:
        return true;
    }
  }

  /// Applies [speed] and reads the player back. YouTube only accepts a fixed
  /// rate list, so a routine speed such as 0.8 becomes the nearest supported rate.
  Future<void> _applyVerifiedYoutubeRate(double speed) async {
    if (!_youtubeAlive) return;
    final target = nearestYoutubePlaybackRate(speed);
    try {
      await _youtubePlayer.setPlaybackRate(target);
      final applied = await _youtubePlayer.playbackRate
          .timeout(const Duration(milliseconds: 800), onTimeout: () => target);
      if (!applied.isFinite || (applied - target).abs() > 0.08) {
        await _youtubePlayer.setPlaybackRate(target);
      }
    } catch (e) {
      debugPrint('[LOOPI] playback rate ignored: $e');
    }
  }

  Future<void> _resumeSectionPlayback() async {
    if (_applyingSection || !mounted || _disposing) return;
    _applyingSection = true;
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          if (!_youtubeAlive) return;
          _logPlayDiag('play_command');
          await _youtubePlayer.playVideo();
          _logPlayDiag('rate_start');
          await _applyVerifiedYoutubeRate(_segment.speed <= 0 ? 1.0 : _segment.speed);
          _logPlayDiag('rate_end');
          break;
        case SourceType.localVideo:
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.resume();
          break;
      }
      if (mounted && _playerReportsPlaying) {
        setState(() => _isPlaying = true);
      }
      _logPlayDiag('routine_state_updated', extra: ' playing=$_isPlaying');
      final now = await _getCurrentTime();
      _notePlayDiagPosition(now);
      _anchorSectionClock(atSec: now > _segment.startSec ? now : _segment.startSec);
      _armBoundaryPoll();
    } catch (e) {
      debugPrint('[LOOPI] play/pause ignored: $e');
    } finally {
      _applyingSection = false;
    }
  }

  void _onYoutubePlayerValue(YoutubePlayerValue value) {
    if (!mounted || _disposing) return;
    final state = value.playerState;
    if (state == PlayerState.playing) {
      if (!_playDiagSawPlaying) {
        _playDiagSawPlaying = true;
        _logPlayDiag('player_playing', extra: ' state=${state.name}');
      }
      final decision = decideIframePlaying(
        entryApplied: _entryApplied,
        applyingSection: _applyingSection,
        holdingForDelay: _delayCountdownActive,
      );
      switch (decision.action) {
        case IframePlayingAction.pauseUntilReady:
          if (_holdingNativePlay) return;
          _holdingNativePlay = true;
          unawaited(() async {
            try {
              if (_youtubeInitialized) await _youtubePlayer.pauseVideo();
            } catch (e) {
              debugPrint('[LOOPI] hold play during countdown ignored: $e');
            } finally {
              _holdingNativePlay = false;
            }
          }());
          return;
        case IframePlayingAction.ignore:
          return;
        case IframePlayingAction.syncPlayback:
          if (!_isPlaying) setState(() => _isPlaying = true);
          _ensureYoutubeRateWhilePlaying(value.playbackRate);
          if (_pollTimer == null) _armBoundaryPoll();
          return;
      }
    }
    if (state == PlayerState.paused || state == PlayerState.ended) {
      if (ignoreIframePause(applyingSection: _applyingSection)) return;
      if (_isPlaying) setState(() => _isPlaying = false);
    }
  }

  void _ensureYoutubeRateWhilePlaying(double reportedRate) {
    if (!_entryApplied || _rateFixInFlight || !_youtubeAlive) return;
    final target = nearestYoutubePlaybackRate(_segment.speed <= 0 ? 1.0 : _segment.speed);
    if ((reportedRate - target).abs() <= 0.08) return;
    _rateFixInFlight = true;
    unawaited(() async {
      try {
        await _applyVerifiedYoutubeRate(target);
      } catch (e) {
        debugPrint('[LOOPI] playback rate reapply ignored: $e');
      } finally {
        _rateFixInFlight = false;
      }
    }());
  }

  void _anchorSectionClock({double? atSec}) {
    _sectionAnchorSec = atSec ?? _segment.startSec;
    _sectionSpeed = _segment.speed <= 0 ? 1.0 : _segment.speed;
    _sectionWallStart = DateTime.now();
    _lastReportedSec = _sectionAnchorSec;
    _lastReportedAt = _sectionWallStart;
  }

  void _pauseSectionClock() {
    final estimated = _estimateSectionTime();
    if (estimated != null) _sectionAnchorSec = estimated;
    _sectionWallStart = null;
  }

  double? _estimateSectionTime() {
    final started = _sectionWallStart;
    if (started == null) return null;
    final elapsed = DateTime.now().difference(started).inMilliseconds / 1000.0;
    if (elapsed < 0) return _sectionAnchorSec;
    return _sectionAnchorSec + elapsed * _sectionSpeed;
  }

  /// Wear / remote channel entry — maps onto existing private controls only.
  @override
  Future<void> handleRemoteCommand(PlayerRemoteCommand command) async {
    if (!mounted || _disposing) return;
    switch (command) {
      case PlayerRemoteCommand.play:
        if (!_isPlaying) await _togglePlayPause();
        break;
      case PlayerRemoteCommand.pause:
        await pausePlayback();
        break;
      case PlayerRemoteCommand.togglePlayPause:
        await _togglePlayPause();
        break;
      case PlayerRemoteCommand.reloopSection:
        await _jumpToSegment(_segmentIndex);
        break;
      case PlayerRemoteCommand.nextSection:
        await _skipToNextSegment();
        break;
      case PlayerRemoteCommand.previousSection:
        await _skipToPreviousSegment();
        break;
    }
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
            throw StateError('YouTube Ã¬ËÂÃ¬ÆÂ IDÃªÂ°â¬ Ã¬ââ Ã¬Å ÂµÃ«â¹ËÃ«â¹Â¤.');
          }
          _youtubePlayer = createLoopiYoutubeController(
            videoId: videoId,
            autoPlay: false,
            startSeconds: _currentRoutine.segments.first.startSec,
          );
          _youtubeInitialized = true;
          if (mounted) setState(() {});
          _youtubeValueSub = listenYoutubeStream(
            _youtubePlayer.stream,
            _onYoutubePlayerValue,
            isAlive: () => _youtubeAlive,
          );
          // Do NOT subscribe to videoStateStream Ã¢â¬â float time payloads crash
          // the package (doubleÃ¢â âMap TypeError). Boundary uses Timer poll only.
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
              _onTime(
                position.inMilliseconds / 1000.0,
                videoDuration: _cachedMediaDurationSec,
              );
            });
            _audioPlayer!.onPlayerStateChanged.listen((state) {
              if (!mounted || _applyingSection) return;
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
      _markControlsReady();
      return;
    }
    _markControlsReady();
  }

  void _onVideoPlayerUpdate() {
    if (_videoPlayer == null || !_ready) return;
    final position = _videoPlayer!.value.position.inMilliseconds / 1000.0;
    final duration = _videoPlayer!.value.isInitialized
        ? _videoPlayer!.value.duration.inMilliseconds / 1000.0
        : _cachedMediaDurationSec;
    if (duration != null && duration > 1) {
      _cachedMediaDurationSec = duration;
    }
    _onTime(position, videoDuration: _cachedMediaDurationSec);
  }

  void _onLocalVideoPlayState() {
    if (!mounted || _videoPlayer == null || _applyingSection) return;
    final playing = _videoPlayer!.value.isPlaying;
    if (_isPlaying != playing) {
      setState(() => _isPlaying = playing);
    }
  }

  Future<void> _startRoutine(int index, {bool immediate = true}) async {
    if (index < 0 || index >= _playlist.length) return;
    _playlistIndex = index;
    _segmentIndex = 0;
    _loopsCompleted = 0;
    _segmentFinished = false;
    _cachedMediaDurationSec = null;
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
            throw StateError('YouTube Ã¬ËÂÃ¬ÆÂ IDÃªÂ°â¬ Ã¬ââ Ã¬Å ÂµÃ«â¹ËÃ«â¹Â¤.');
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
            }
          }
          break;
      }
    } catch (_) {
      _isSeeking = false;
    }

    _armBoundaryPoll();
  }

  Future<double> _getCurrentTime() async {
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          return await _yt(() => _youtubePlayer.currentTime)
                  .timeout(const Duration(milliseconds: 500), onTimeout: () => null) ??
              0;
        case SourceType.localVideo:
          final position = _videoPlayer?.value.position.inMilliseconds;
          return position != null ? position / 1000.0 : 0;
        case SourceType.audio:
          final position = await _audioPlayer?.getCurrentPosition();
          final positionMs = position?.inMilliseconds;
          return positionMs != null ? positionMs / 1000.0 : 0;
      }
    } catch (e) {
      debugPrint('[LOOPI] playback currentTime ignored: $e');
      return 0;
    }
  }

  Future<double?> _mediaDurationSec() async {
    if (_cachedMediaDurationSec != null && _cachedMediaDurationSec! > 1) {
      return _cachedMediaDurationSec;
    }
    try {
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          final d = await _yt(() => _youtubePlayer.duration)
              .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
          if (d != null && d > 1) {
            _cachedMediaDurationSec = d;
            return d;
          }
          break;
        case SourceType.localVideo:
          final player = _videoPlayer;
          if (player != null && player.value.isInitialized) {
            final d = player.value.duration.inMilliseconds / 1000.0;
            if (d > 1) {
              _cachedMediaDurationSec = d;
              return d;
            }
          }
          break;
        case SourceType.audio:
          final d = await _audioPlayer?.getDuration();
          final sec = (d?.inMilliseconds ?? 0) / 1000.0;
          if (sec > 1) {
            _cachedMediaDurationSec = sec;
            return sec;
          }
          break;
      }
    } catch (e) {
      debugPrint('[LOOPI] playback duration ignored: $e');
    }
    return _cachedMediaDurationSec;
  }

  /// Cap authored section.end when it exceeds real Shorts/video length.
  double _effectiveSectionEnd(RoutineSegment segment, double? videoDuration) {
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

  Future<void> _startSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    _segmentIndex = index;
    _loopsCompleted = 0;
    _segmentFinished = false;
    _isSeeking = true;
    _delayPending = true;
    // Keep advancing/seeking locked for the whole prep delay so the boundary
    // poll cannot race ahead and skip Section B's delayTime.
    _ignoreUntil = DateTime.now().add(const Duration(seconds: 30));
    if (_inWidgetTest) {
      _isSeeking = false;
      _delayPending = false;
      return;
    }
    try {
      final segment = _currentRoutine.segments[index];
      final delaySec = segment.delaySec < 0 ? 0 : segment.delaySec;
      final duration = await _mediaDurationSec();
      final effectiveEnd = _effectiveSectionEnd(segment, duration);

      // 1) Seek to section start and hold paused on the first frame.
      // Do not cueVideoById here — reloading the iframe drops the play gesture
      // and ignores our end boundary.
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.pauseVideo());
          await _yt(() => _youtubePlayer.setPlaybackRate(segment.speed));
          await _yt(
            () => _youtubePlayer.seekTo(
              seconds: segment.startSec,
              allowSeekAhead: true,
            ),
          );
          await _yt(() => _youtubePlayer.pauseVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.pause();
          await _videoPlayer?.setPlaybackSpeed(segment.speed);
          await _videoPlayer?.seekTo(
            Duration(milliseconds: (segment.startSec * 1000).toInt()),
          );
          await _videoPlayer?.pause();
          break;
        case SourceType.audio:
          await _audioPlayer?.pause();
          await _audioPlayer?.setPlaybackRate(segment.speed);
          await _audioPlayer?.seek(
            Duration(milliseconds: (segment.startSec * 1000).toInt()),
          );
          await _audioPlayer?.pause();
          break;
      }

      // 2) Honor Section delayTime before play (0 Ã¢â â short settle only).
      if (delaySec > 0) {
        debugPrint(
          '[LOOPI] playback delay ${delaySec}s before '
          '${sectionLabelForIndex(index)} play',
        );
        _ignoreUntil = DateTime.now().add(Duration(seconds: delaySec + 1));
        await _runVisibleDelay(delaySec);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!_ready || _disposing || !mounted) return;

      // 3) Re-apply speed after delay (cue can reset rate), then play.
      final speed = segment.speed <= 0 ? 1.0 : segment.speed;
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          if (!_youtubeAlive) return;
          await _yt(() => _youtubePlayer.setPlaybackRate(speed));
          await _youtubePlayer.playVideo();
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          await _audioPlayer?.resume();
          break;
      }
      _anchorSectionClock();
      debugPrint(
        '[LOOPI] playback section ${sectionLabelForIndex(index)} '
        'start=${segment.startSec} end=${segment.endSec} '
        'effectiveEnd=$effectiveEnd delaySec=$delaySec speed=$speed',
      );
    } catch (e) {
      debugPrint('[LOOPI] playback startSegment failed: $e');
    } finally {
      _isSeeking = false;
      _delayPending = false;
      _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 400));
      _armBoundaryPoll();
    }
  }

  void _cancelBoundaryPoll() {
    _pollEpoch++;
    _pollBusy = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 50ms poll. iframe currentTime lags, so project forward from the last
  /// sample and pause ~200ms early — the pause command itself arrives late.
  void _armBoundaryPoll() {
    _cancelBoundaryPoll();
    if (_segmentFinished || _disposing || !_ready) return;
    final epoch = _pollEpoch;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_pollBusy || epoch != _pollEpoch) return;
      if (!_ready || _isSeeking || _isAdvancing || _segmentFinished || _disposing || _delayPending) {
        return;
      }
      if (!_isPlaying) return;
      _pollBusy = true;
      unawaited(() async {
        try {
          final reported = await _getCurrentTime();
          _notePlayDiagPosition(reported);
          if (epoch != _pollEpoch || _disposing || !_ready || _isSeeking || _isAdvancing || _segmentFinished || _delayPending) {
            return;
          }
          if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;
          final end = _segment.endSec;
          final time = _projectedPlaybackTime(reported);
          if (time + 0.001 < end - 0.2) return;
          timer.cancel();
          _pollTimer = null;
          _pollEpoch++;
          try {
            if (_currentRoutine.sourceType == SourceType.youtube && _youtubeInitialized) {
              await _youtubePlayer.pauseVideo();
            } else if (_currentRoutine.sourceType == SourceType.localVideo) {
              await _videoPlayer?.pause();
            } else {
              await _audioPlayer?.pause();
            }
          } catch (e) {
            debugPrint('[LOOPI] boundary pause ignored: $e');
          }
          await _finishSectionAndAdvance();
        } catch (e) {
          debugPrint('[LOOPI] playback poll ignored: $e');
        } finally {
          if (epoch == _pollEpoch) _pollBusy = false;
        }
      }());
    });
  }

  /// Last iframe sample plus elapsed time, so a stale currentTime cannot run past end.
  double _projectedPlaybackTime(double reported) {
    final now = DateTime.now();
    final speed = _sectionSpeed <= 0 ? 1.0 : _sectionSpeed;
    if (reported >= _segment.startSec - 0.05) {
      _lastReportedSec = reported;
      _lastReportedAt = now;
    }
    var projected = reported;
    final sampledAt = _lastReportedAt;
    if (sampledAt != null) {
      final age = now.difference(sampledAt).inMilliseconds / 1000.0;
      final fromSample = _lastReportedSec + age * speed;
      if (fromSample > projected) projected = fromSample;
    }
    final wall = _estimateSectionTime();
    if (wall != null && wall > projected) projected = wall;
    return projected;
  }

  Future<void> _jumpToSegment(int index) async {
    if (index < 0 || index >= _currentRoutine.segments.length) return;
    await _startSegment(index);
  }

  /// Pauses YouTube / video / audio so background playback cannot leak into
  /// another screen (e.g. Practice Mode).
  Future<void> pausePlayback() async {
    _cancelBoundaryPoll();
    if (mounted) setState(() => _isPlaying = false);
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
    _pauseSectionClock();
  }

  Future<void> _togglePlayPause() async {
    if (_inWidgetTest || _disposing || _applyingSection || _delayCountdownActive || _userStartInFlight) {
      return;
    }
    if (!_ready) {
      if (!_isPlaying && !_entryApplied) {
        _beginPlayDiag();
        _logPlayDiag('play_button_before_player_init');
        _playWhenReady = true;
      }
      return;
    }
    try {
      if (_isPlaying) {
        setState(() => _isPlaying = false);
        await pausePlayback();
        return;
      }
      _beginPlayDiag();
      if (!_entryApplied) {
        await _startPlaybackFromUser();
        return;
      }
      await _resumeSectionPlayback();
    } catch (e) {
      debugPrint('[LOOPI] play/pause ignored: $e');
    }
  }

  bool _handlePlaybackSeekKey(KeyEvent event) {
    if (!mounted || _disposing || !_ready) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final result = playbackSeekKeyResult(
      event: event,
      routeIsCurrent: true,
      textInputFocused: _primaryFocusIsTextInput(),
    );
    final delta = result.delta;
    if (delta != null) {
      unawaited(_seekRelative(delta));
    }
    return result.handled;
  }

  bool _primaryFocusIsTextInput() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Left/right double-tap zones over the picture.
  ///
  /// The center and the bottom strip stay open so a YouTube iframe can still
  /// receive its own single taps. Cross-origin iframe events never reach Flutter.
  Widget _fiveSecondSeekOverlay() {
    if (_inWidgetTest) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 56),
      child: Row(
        children: [
          Expanded(child: _seekDoubleTapZone(-5)),
          const SizedBox(width: 72),
          Expanded(child: _seekDoubleTapZone(5)),
        ],
      ),
    );
  }

  Widget _seekDoubleTapZone(double deltaSeconds) {
    return PointerInterceptor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          if (!_ready || _disposing) return;
          unawaited(_seekRelative(deltaSeconds));
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _flippedMedia(Widget mediaWidget) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.flip(
          flipX: _currentRoutine.isMirroredOn &&
              _currentRoutine.sourceType != SourceType.audio,
          child: mediaWidget,
        ),
        _fiveSecondSeekOverlay(),
      ],
    );
  }

  Future<void> _seekRelative(double seconds) async {
    if (_inWidgetTest) return;
    try {
      final currentTime = await _getCurrentTime();
      final newTime = currentTime + seconds;
      final effectiveEnd = _effectiveSectionEnd(_segment, _cachedMediaDurationSec);
      final clampedTime = newTime.clamp(_segment.startSec, effectiveEnd);
      
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

    // At effectiveEnd, finish this section's loops then advance to the next section.
  void _onTime(double time, {double? videoDuration}) {
    if (!_ready || _delayPending || _isSeeking || _isAdvancing || _segmentFinished) {
      return;
    }
    if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;

    final segmentStart = _segment.startSec;
    final effectiveEnd = _effectiveSectionEnd(_segment, videoDuration ?? _cachedMediaDurationSec);
    if (effectiveEnd <= segmentStart) return;
    if (time < segmentStart - 0.1) return;

    final atMediaEof = videoDuration != null &&
        videoDuration > 1 &&
        time >= videoDuration - 0.4;
    if (!atMediaEof && time + 0.12 < effectiveEnd) return;

    debugPrint(
      '[LOOPI] playback section boundary '
      '${sectionLabelForIndex(_segmentIndex)} time=$time effectiveEnd=$effectiveEnd '
      'rawEnd=${_segment.endSec} duration=$videoDuration',
    );
    unawaited(_finishSectionAndAdvance());
  }

  /// Honors loopCount, then seeks into the next section (countdown/delay + play).
  Future<void> _finishSectionAndAdvance() async {
    if (_isAdvancing || _segmentFinished) return;
    _isAdvancing = true;
    _pollTimer?.cancel();
    _pauseSectionClock();
    try {
      final delaySec = _segment.delaySec;
      final targetLoops = _segment.loopCount == kInfiniteLoop
          ? kInfiniteLoop
          : (_segment.loopCount <= 0 ? 1 : _segment.loopCount);

      if (targetLoops == kInfiniteLoop) {
        await _replayWithDelay(delaySec);
        return;
      }

      _loopsCompleted += 1;
      if (_loopsCompleted < targetLoops) {
        await _replayWithDelay(delaySec);
        return;
      }

      final nextIndex = _segmentIndex + 1;
      if (nextIndex < _currentRoutine.segments.length) {
        debugPrint(
          '[LOOPI] section complete ${sectionLabelForIndex(_segmentIndex)} '
          '→ ${sectionLabelForIndex(nextIndex)}',
        );
        await pausePlayback();
        _isAdvancing = false;
        await _startSegment(nextIndex);
        return;
      }

      if (_isGroupPlayback) {
        _isAdvancing = false;
        await _advanceToNextRoutine(delaySec);
        return;
      }

      _segmentFinished = true;
      _pollTimer?.cancel();
      _pollTimer = null;
      await pausePlayback();
      debugPrint(
        '[LOOPI] routine playback complete '
        '${sectionLabelForIndex(_segmentIndex)} — paused',
      );
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
          await _yt(() => _youtubePlayer.pauseVideo());
          await _yt(() => _youtubePlayer.setPlaybackRate(_segment.speed));
          await _yt(
            () => _youtubePlayer.seekTo(
              seconds: _segment.startSec,
              allowSeekAhead: true,
            ),
          );
          await _yt(() => _youtubePlayer.pauseVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.pause();
          await _videoPlayer?.setPlaybackSpeed(_segment.speed);
          await _videoPlayer?.seekTo(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
          await _videoPlayer?.pause();
          break;
        case SourceType.audio:
          await _audioPlayer?.pause();
          await _audioPlayer?.setPlaybackRate(_segment.speed);
          await _audioPlayer?.seek(Duration(milliseconds: (_segment.startSec * 1000).toInt()));
          await _audioPlayer?.pause();
          break;
      }
    } catch (_) {}
    _isSeeking = false;
    try {
      final speed = _segment.speed <= 0 ? 1.0 : _segment.speed;
      switch (_currentRoutine.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.setPlaybackRate(speed));
          await _yt(() => _youtubePlayer.playVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          await _audioPlayer?.resume();
          break;
      }
      _anchorSectionClock();
      _armBoundaryPoll();
    } catch (_) {}
  }

  Future<void> _replayWithDelay(int delaySec) async {
    final seconds = delaySec < 0 ? 0 : delaySec;
    if (seconds > 0) {
      await _waitDelay(seconds);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!_ready || !mounted) return;
    await _replayCurrent();
  }

  Future<void> _startSegmentWithDelay(int index, int delaySec) async {
    // Delay is applied inside [_startSegment] from the section's delaySec.
    if (!_ready || !mounted) return;
    await _startSegment(index);
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
      // Ã¢ÅÂ¨ Ã¬â¹Â¤Ã¬Â§ËÃ¬Â ÂÃ¬ÅÂ¼Ã«Â¡Å Ã«âÅÃ«Â ËÃ¬ÂÂ´ Ã¬Â´ËÃ«Â§ÅÃ­ÂÂ¼ Ã«Åâ¬ÃªÂ¸Â°Ã­â¢ËÃ«Å â Ã¬Â½âÃ«âÅÃªÂ°â¬ Ã«Â¹Â Ã¬Â Â¸ Ã¬Å¾ËÃ¬âËÃ¬Å ÂµÃ«â¹ËÃ«â¹Â¤!
      await _runVisibleDelay(delaySec);
      if (!_youtubeAlive && _currentRoutine.sourceType == SourceType.youtube) {
        return;
      }
    } catch (_) {
    } finally {
      _delayPending = false;
    }
  }

  Widget _playerControls({bool compact = false}) {
    final iconSize = compact ? 22.0 : 24.0;
    final pad = compact ? 6.0 : 16.0;
    final playButton = Container(
      decoration: const BoxDecoration(
        color: LoopiColors.purple,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: _togglePlayPause,
        iconSize: compact ? 22 : 24,
        padding: EdgeInsets.all(compact ? 8 : 12),
        constraints: compact
            ? const BoxConstraints(minWidth: 40, minHeight: 40)
            : const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
        tooltip: _isPlaying ? 'player.pause'.tr() : 'player.play'.tr(),
        color: Colors.white,
      ),
    );

    if (compact) {
      // Vertical rail for landscape / low-height side panel.
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isGroupPlayback)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_playlistIndex + 1}/${_playlist.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            if (_isGroupPlayback)
              IconButton(
                onPressed: _previousRoutine,
                iconSize: iconSize,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.skip_previous_rounded),
                color: Colors.white,
              ),
            IconButton(
              onPressed: _skipToPreviousSegment,
              iconSize: iconSize,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
              color: Colors.white,
            ),
            IconButton(
              onPressed: () => _seekRelative(-5),
              iconSize: iconSize,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.replay_5),
              color: Colors.white,
            ),
            playButton,
            IconButton(
              onPressed: () => _seekRelative(5),
              iconSize: iconSize,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.forward_5),
              color: Colors.white,
            ),
            IconButton(
              onPressed: _skipToNextSegment,
              iconSize: iconSize,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              color: Colors.white,
            ),
            if (_isGroupPlayback)
              IconButton(
                onPressed: _nextRoutine,
                iconSize: iconSize,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.skip_next_rounded),
                color: Colors.white,
              ),
            IconButton(
              onPressed: _toggleFullscreen,
              iconSize: iconSize,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              color: Colors.white,
              tooltip: _isFullscreen ? '전체화면 종료' : '전체화면',
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_isGroupPlayback)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_playlistIndex + 1} / ${_playlist.length}  ·  ${_currentRoutine.name}',
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
                  color: Colors.white,
                ),
              IconButton(
                onPressed: _skipToPreviousSegment,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                color: Colors.white,
              ),
              IconButton(
                onPressed: () => _seekRelative(-5),
                icon: const Icon(Icons.replay_5),
                tooltip: 'player.rewind_5s'.tr(),
                color: Colors.white,
              ),
              playButton,
              IconButton(
                onPressed: () => _seekRelative(5),
                icon: const Icon(Icons.forward_5),
                tooltip: 'player.forward_5s'.tr(),
                color: Colors.white,
              ),
              IconButton(
                onPressed: _skipToNextSegment,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                color: Colors.white,
              ),
              if (_isGroupPlayback)
                IconButton(
                  onPressed: _nextRoutine,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: Colors.white,
                ),
              IconButton(
                onPressed: _toggleFullscreen,
                icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                tooltip: _isFullscreen ? '전체화면 종료' : '전체화면',
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fullscreenCornerButton() {
    return PointerInterceptor(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: _toggleFullscreen,
          color: Colors.white,
          tooltip: _isFullscreen ? '전체화면 종료' : '전체화면',
          icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    HardwareKeyboard.instance.removeHandler(_handlePlaybackSeekKey);
    PlayerRemoteControl.instance.detach(this);
    _ready = false;
    _cancelDelayCountdown();
    _cancelBoundaryPoll();
    _delayTimer?.cancel();
    _youtubeValueSub?.cancel();
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
    _transformationController.dispose();
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
          mediaWidget: _inWidgetTest ? const ColoredBox(color: Colors.black) : player,
        );
      },
    );
  }

  Widget _intervalButtons({bool compact = false, bool vertical = false}) {
    final count = _currentRoutine.segments.length;
    if (count == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final maxAlong = vertical
            ? box.maxWidth.clamp(0.0, compact ? 40.0 : 96.0)
            : box.maxHeight.clamp(0.0, compact ? 40.0 : 96.0);
        if (!maxAlong.isFinite || maxAlong <= 0) {
          return const SizedBox.shrink();
        }
        if (vertical && box.maxHeight <= 0) return const SizedBox.shrink();
        if (!vertical && box.maxWidth <= 0) return const SizedBox.shrink();

        var diameter = maxAlong;
        if (count > 1) {
          final available = vertical ? box.maxHeight : box.maxWidth;
          final fit = available / (1.35 * count - 0.35);
          if (fit < diameter) diameter = fit;
        }
        diameter = diameter.clamp(compact ? 22.0 : 24.0, maxAlong);
        final gap = count <= 1 ? 0.0 : diameter * (compact ? 0.28 : 0.5);

        final buttons = <Widget>[
          for (var index = 0; index < count; index++) ...[
            if (index > 0) SizedBox(width: vertical ? 0 : gap, height: vertical ? gap : 0),
            SizedBox(
              width: diameter,
              height: diameter,
              child: _sectionCircleButton(index, compact: compact),
            ),
          ],
        ];

        if (vertical) {
          final col = Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: buttons,
          );
          final totalH = count * diameter + (count - 1) * gap;
          if (totalH <= box.maxHeight) {
            return Center(child: col);
          }
          return Center(
            child: SingleChildScrollView(
              child: col,
            ),
          );
        }

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

  Widget _sectionCircleButton(int index, {bool compact = false}) {
    final highlight = _currentRoutine.segments[index].isHighlight;
    return Container(
      decoration: BoxDecoration(
        color: index == _segmentIndex ? LoopiColors.purple : const Color(0xFF2A2438),
        shape: BoxShape.circle,
        border: highlight
            ? Border.all(color: kHighlightGold, width: compact ? 1.6 : 2.4)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
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
                    padding: EdgeInsets.all(compact ? 3 : 6),
                    child: Text(
                      sectionLabelForIndex(index),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12 : 14,
                      ),
                    ),
                  ),
                ),
              ),
              if (highlight)
                Positioned(
                  top: compact ? 1 : 2,
                  right: compact ? 1 : 2,
                  child: HighlightCrown(size: compact ? 8 : 11),
                ),
            ],
          ),
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

  bool get _isLowHeightViewport {
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    return orientation == Orientation.landscape || size.height < 550;
  }

  Widget _mediaStage(Widget mediaWidget) {
    // 모바일 기기(iOS, Android)와 데스크톱 웹을 구분하기 위한 변수
    final bool isDesktopWeb = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);

    return Center(
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final dy = pointerSignal.scrollDelta.dy;
            if (dy == 0) return;

            // Zoom in if scrolling up, out if scrolling down
            final double scaleChange = dy < 0 ? 1.1 : 0.9;
            final Matrix4 matrix = _transformationController.value.clone();
            final double currentScale = matrix.getMaxScaleOnAxis();

            // Clamp the scale bounds (1.0 to 4.0)
            final double targetScale = (currentScale * scaleChange).clamp(1.0, 4.0);
            final double actualScaleChange = targetScale / currentScale;

            if (actualScaleChange == 1.0) return;

            final Offset focalPoint = pointerSignal.localPosition;

            // Scale relative to the exact mouse pointer position
            matrix.translate(focalPoint.dx, focalPoint.dy);
            matrix.scale(actualScaleChange, actualScaleChange, 1.0);
            matrix.translate(-focalPoint.dx, -focalPoint.dy);

            _transformationController.value = matrix;
          }
        },
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1.0,
          maxScale: 4.0,
          // Allow free panning
          panEnabled: true,
          scaleEnabled: true,
          child: AspectRatio(
            aspectRatio: _playerAspectRatio > 0 ? _playerAspectRatio : 16 / 9,
            child: Transform.flip(
              flipX: _currentRoutine.isMirroredOn &&
                  _currentRoutine.sourceType != SourceType.audio,
              child: isDesktopWeb
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        mediaWidget,
                        // 데스크톱 웹 환경: 유튜브 iframe 마우스 스크롤 가로채기 방지용 방패막
                        PointerInterceptor(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    )
                  : mediaWidget, // 모바일 웹 환경: 방패막 없이 순정 터치 줌 활성화
            ),
          ),
        ),
      ),
    );
  }

  Widget _countdownBanner({bool compact = false}) {
    if (_countdown <= 0) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 16, compact ? 4 : 8, compact ? 8 : 16, 0),
      child: Material(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 6 : 12,
            horizontal: compact ? 10 : 16,
          ),
          child: CircleAvatar(
            radius: compact ? 14 : 20,
            backgroundColor: LoopiColors.purple,
            child: Text(
              '$_countdown',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// In-app fullscreen: media fills the body; controls overlay at the bottom.
  Widget _buildFullscreenPlayerBody(Widget mediaWidget) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _mediaStage(mediaWidget)),
        if (_countdown > 0)
          Align(
            alignment: Alignment.topCenter,
            child: _countdownBanner(compact: true),
          ),
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _fullscreenCornerButton(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: PointerInterceptor(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 28, 8, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${sectionLabelForIndex(_segmentIndex)}  '
                        '${formatMmSs(_segment.startSec)} - ${formatMmSs(_segment.endSec)}  '
                        '${formatSpeedLabel(_segment.speed)}  ${formatLoopLabel(_segment.loopCount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 52,
                        child: _intervalButtons(compact: true),
                      ),
                      _playerControls(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait / desktop: unchanged vertical stack.
  Widget _buildPortraitPlayerBody(Widget mediaWidget) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const metadataHeight = 40.0;
        final controlsHeight = _isGroupPlayback ? 120.0 : 88.0;
        final previousVideoCap = constraints.maxHeight * 0.55;
        final previousLeftover = (constraints.maxHeight -
                previousVideoCap -
                metadataHeight -
                controlsHeight)
            .clamp(40.0, constraints.maxHeight);
        final intervalHeight = (previousLeftover * 0.4).clamp(40.0, previousLeftover);

        return Column(
          children: [
            _countdownBanner(),
            // Use the same InteractiveViewer stage as landscape — portrait
            // previously called `_flippedMedia` only, so zoom/pan never attached.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: _mediaStage(mediaWidget),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _fullscreenCornerButton(),
                  ),
                ],
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
                    '${formatMmSs(_segment.startSec)} - ${formatMmSs(_segment.endSec)}  '
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
  }

  /// Landscape / low-height: video gets max height; compact A-F + transport on the right.
  Widget _buildLandscapePlayerBody(Widget mediaWidget) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 75,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _mediaStage(mediaWidget)),
              if (_countdown > 0)
                Align(
                  alignment: Alignment.topCenter,
                  child: _countdownBanner(compact: true),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: _fullscreenCornerButton(),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 4,
                child: IgnorePointer(
                  child: Text(
                    '${sectionLabelForIndex(_segmentIndex)}  '
                    '${formatMmSs(_segment.startSec)}-${formatMmSs(_segment.endSec)}  '
                    '${formatSpeedLabel(_segment.speed)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        PointerInterceptor(
          child: ColoredBox(
            color: const Color(0xE6120F1C),
            child: SizedBox(
              width: 76,
              child: LayoutBuilder(
                builder: (context, rail) {
                  final transportMax = (rail.maxHeight * 0.48).clamp(96.0, 200.0);
                  return Column(
                    children: [
                      const SizedBox(height: 2),
                      Expanded(
                        child: _intervalButtons(compact: true, vertical: true),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: transportMax),
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: _playerControls(compact: true),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainScaffold({required Widget mediaWidget}) {
    final isLandscape = _isLowHeightViewport;
    final content = _isFullscreen
        ? _buildFullscreenPlayerBody(mediaWidget)
        : (isLandscape
            ? _buildLandscapePlayerBody(mediaWidget)
            : _buildPortraitPlayerBody(mediaWidget));

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
              appBar: _isFullscreen
                  ? null
                  : AppBar(
                      toolbarHeight: isLandscape ? 36 : kToolbarHeight,
                      backgroundColor: isLandscape
                          ? Colors.black.withValues(alpha: 0.45)
                          : Colors.transparent,
                      foregroundColor: Colors.white,
                      titleSpacing: isLandscape ? 8 : null,
                      title: Row(
                        children: [
                          if (!isLandscape) ...[
                            const AppLogo(height: 28),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              _currentRoutine.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: isLandscape ? 14 : 20),
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
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'common.favorite_added'.tr()
                                        : 'common.favorite_removed'.tr(),
                                  ),
                                ),
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
