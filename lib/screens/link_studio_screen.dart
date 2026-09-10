import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/routine_models.dart';
import '../services/database_service.dart';
import '../state/link_studio_session.dart';
import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../utils/cached_video.dart';
import '../utils/time_format.dart';
import '../utils/youtube_id.dart';
import '../utils/youtube_player_factory.dart';
import '../utils/media_blob.dart';
import '../widgets/app_logo.dart';
import '../widgets/highlight_interval.dart';
import '../widgets/load_cached_routine_dialog.dart';
import '../widgets/save_routine_dialog.dart';
import 'practice_mode_screen.dart';

const String kDefaultVideoUrl = 'https://www.youtube.com/watch?v=M7lc1UVf-VE';

const double _kStudioHPad = 16;
const double _kStudioVPad = 12;
const double _kStudioUrlGap = 12;
const double _kStudioUrlBarHeight = 64;
const double _kStudioColumnGap = 6;
const double _kStudioMinSettingsWidth = 240;

String? _platformFilePath(PlatformFile? file) {
  if (file == null || kIsWeb) return null;
  return file.path;
}

String? _createSelectedVideoBlobUrl(PlatformFile file) {
  final extension = file.extension?.toLowerCase();
  final mimeType = switch (extension) {
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    _ => 'video/mp4',
  };
  return createMediaBlobUrl(file.bytes!, mimeType);
}

class LinkStudioScreen extends StatefulWidget {
  const LinkStudioScreen({
    super.key,
    required this.library,
    this.initialVideoUrl = kDefaultVideoUrl,
    this.sourceType = SourceType.youtube,
    this.embedded = false,
    this.active = true,
    this.file,
    this.localFilePath,
    this.fileName,
    this.editingRoutine,
  });

  final RoutineLibrary library;
  final String initialVideoUrl;
  final SourceType sourceType;
  final bool embedded;
  /// When false (e.g. another bottom-nav tab is selected), playback pauses.
  final bool active;
  final PlatformFile? file;
  final String? localFilePath;
  final String? fileName;
  final SavedRoutine? editingRoutine;

  bool get isEditMode => editingRoutine != null;

  @override
  State<LinkStudioScreen> createState() => _LinkStudioScreenState();
}

class _LinkStudioScreenState extends State<LinkStudioScreen> with WidgetsBindingObserver {
  final LinkStudioSession _session = LinkStudioSession();
  final TextEditingController _urlController = TextEditingController();
  final List<TextEditingController> _startControllers = [];
  final List<TextEditingController> _endControllers = [];
  final List<FocusNode> _startFocus = [];
  final List<FocusNode> _endFocus = [];

  late YoutubePlayerController _youtubePlayer;
  bool _youtubeInitialized = false;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _stateSub;

  Timer? _loopPlaybackTimer;
  Timer? _delayTimer;
  Timer? _routineTimer;
  Timer? _playbackMonitorTimer;
  int _routineSessionId = 0;
  DateTime? _lastSeekAt;

  bool _isSeeking = false;
  bool _isAdvancing = false;
  DateTime? _ignoreUntil;
  String _videoUrl = kDefaultVideoUrl;
  String _videoId = 'M7lc1UVf-VE';
  RangeValues? _rangeBeforeDrag;
  bool _saveDialogOpen = false;

  int _highlightedSection = 0;
  Completer<void>? _delayCompleter;
  String? _lastDetectedClipboardText;
  String? _dismissedClipboardRaw;
  String? _mediaObjectUrl;
  bool _audioLoading = false;
  String? _videoLoadError;
  bool _showClipboardBanner = false;
  bool? _isMirrored = false;
  bool _disposing = false;
  /// Best-effort title from iframe metadata (no YouTube Data API).
  String? _videoTitle;
  final DatabaseService _database = DatabaseService();
  final ScrollController _routineListHorizontalController = ScrollController();
  final ScrollController _routineListVerticalController = ScrollController();

  bool get _youtubeAlive => !_disposing && _youtubeInitialized && mounted;

  Future<T?> _yt<T>(Future<T> Function() action) {
    return safeYoutubePlayerCall(action, isAlive: () => _youtubeAlive);
  }

  bool get _inWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  bool get _isYouTubeShortsUrl => _videoUrl.toLowerCase().contains('/shorts/');

  double get _mediaAspectRatio {
    if (_session.sourceType == SourceType.audio) return 16 / 9;
    if (_videoPlayer != null && _videoPlayer!.value.isInitialized) {
      final size = _videoPlayer!.value.size;
      if (size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
      final ratio = _videoPlayer!.value.aspectRatio;
      if (ratio > 0) return ratio;
    }
    if (_isYouTubeShortsUrl) return 9 / 16;
    return 16 / 9;
  }

  bool get _isVerticalMedia =>
      _session.sourceType != SourceType.audio && _mediaAspectRatio < 1;

  bool _videoFitsInColumn(BoxConstraints constraints, double ratio) {
    final availableH = constraints.maxHeight;
    final availableW = constraints.maxWidth;
    if (availableH <= 0 || availableW <= 0 || ratio <= 0) return true;
    final contentW = (availableW - _kStudioHPad * 2).clamp(1.0, availableW);
    final videoH = contentW / ratio;
    final needed = _kStudioVPad * 2 + _kStudioUrlBarHeight + _kStudioUrlGap + videoH;
    return needed + 8 <= availableH;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final editing = widget.editingRoutine;
    if (editing != null) {
      _videoUrl = editing.videoUrl.isNotEmpty ? editing.videoUrl : kDefaultVideoUrl;
      _videoId = resolveYoutubeVideoId(videoId: editing.videoId, videoUrl: _videoUrl) ??
          'M7lc1UVf-VE';
      _urlController.text = _videoUrl;
      _session.loadFromRoutine(editing);
      _isMirrored = editing.isMirroredOn;
    } else {
      _videoUrl = widget.initialVideoUrl;
      _urlController.text = _videoUrl;
      _videoId = extractYoutubeVideoId(_videoUrl) ?? 'M7lc1UVf-VE';
      _session.setSourceType(
        widget.sourceType,
        localFilePath: _platformFilePath(widget.file) ?? widget.localFilePath,
        fileName: widget.file?.name ?? widget.fileName,
        localDataBytes: widget.file?.bytes,
      );
    }
    _syncRowControllers();
    _session.addListener(_onSessionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) {
        unawaited(_checkClipboardForDetectedLink());
      }
    });

    final sourceType = editing?.sourceType ?? widget.sourceType;
    switch (sourceType) {
      case SourceType.youtube:
        if (!_inWidgetTest) {
          _initializeYouTubePlayer();
        }
        break;
      case SourceType.localVideo:
        _initializeVideoPlayer();
        break;
      case SourceType.audio:
        _initializeAudioPlayer();
        break;
    }
  }

  Future<void> _initializeYouTubePlayer() async {
    _youtubePlayer = createLoopiYoutubeController(
      videoId: _videoId,
      autoPlay: false,
    );
    _youtubeInitialized = true;
    _valueSub = listenYoutubeStream(
      _youtubePlayer.stream,
      _onPlayerValue,
      isAlive: () => _youtubeAlive,
    );
    _stateSub = listenYoutubeStream(
      _youtubePlayer.videoStateStream,
      _onVideoState,
      isAlive: () => _youtubeAlive,
    );
  }

  @override
  void didUpdateWidget(LinkStudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _haltPlayback(stopTest: true);
    } else if (!oldWidget.active && widget.active) {
      unawaited(_checkClipboardForDetectedLink());
    }
  }

  @override
  void deactivate() {
    _haltPlayback();
    super.deactivate();
  }

  void _haltPlayback({bool stopTest = false}) {
    _loopPlaybackTimer?.cancel();
    _delayTimer?.cancel();
    _routineTimer?.cancel();
    _playbackMonitorTimer?.cancel();
    if (stopTest && _session.isTesting) {
      _routineSessionId++;
      _session.stopTest();
    }
    unawaited(_pause());
  }

  Future<void> _initializeVideoPlayer() async {
    final editing = widget.editingRoutine;
    final path = _platformFilePath(widget.file) ?? widget.localFilePath ?? editing?.localFilePath;
    if (path != null && !kIsWeb) {
      _videoPlayer = VideoPlayerController.file(File(path));
    } else if (widget.file?.bytes != null) {
      final extension = widget.file!.extension?.toLowerCase();
      final mimeType = switch (extension) {
        'webm' => 'video/webm',
        'mov' => 'video/quicktime',
        'mkv' => 'video/x-matroska',
        _ => 'video/mp4',
      };
      _mediaObjectUrl = createMediaBlobUrl(widget.file!.bytes!, mimeType);
      final uri = _mediaObjectUrl == null
          ? Uri.dataFromBytes(widget.file!.bytes!, mimeType: mimeType)
          : Uri.parse(_mediaObjectUrl!);
      _videoPlayer = VideoPlayerController.networkUrl(uri);
    } else if (editing?.localDataBytes != null) {
      _mediaObjectUrl = createMediaBlobUrl(editing!.localDataBytes!, 'video/mp4');
      final uri = _mediaObjectUrl == null
          ? Uri.dataFromBytes(editing.localDataBytes!, mimeType: 'video/mp4')
          : Uri.parse(_mediaObjectUrl!);
      _videoPlayer = VideoPlayerController.networkUrl(uri);
    } else if (path != null) {
      _videoPlayer = createCachedNetworkVideo(Uri.parse(path));
    } else {
      return;
    }
    _videoLoadError = null;
    try {
      await _videoPlayer!.initialize().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Video initialization timed out'),
          );
      _session.setVideoDuration(_videoPlayer!.value.duration.inMilliseconds / 1000.0);
      _videoPlayer!.addListener(_onVideoPlayerUpdate);
    } catch (error) {
      debugPrint('Video initialization error: $error');
      _videoLoadError = '영상을 불러오지 못했습니다. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _initializeAudioPlayer() async {
    _audioLoading = true;
    if (mounted) setState(() {});
    final editing = widget.editingRoutine;
    final path = _platformFilePath(widget.file) ?? widget.localFilePath ?? editing?.localFilePath;
    _audioPlayer = AudioPlayer();
    try {
      if (path != null && !kIsWeb) {
        await _audioPlayer!.setSourceDeviceFile(path);
      } else if (widget.file?.bytes != null) {
        await _audioPlayer!.setSourceBytes(widget.file!.bytes!);
      } else if (editing?.localDataBytes != null) {
        await _audioPlayer!.setSourceBytes(Uint8List.fromList(editing!.localDataBytes!));
      } else if (path != null) {
        await _audioPlayer!.setSourceUrl(path);
      } else {
        return;
      }
      final duration = await _audioPlayer!.getDuration();
      if (duration != null) {
        _session.setVideoDuration(duration.inMilliseconds / 1000.0);
      }
      _audioPlayer!.onPositionChanged.listen((position) {
        final seconds = position.inMilliseconds / 1000.0;
        _syncSectionHighlight(seconds);
      });
    } finally {
      _audioLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _onVideoPlayerUpdate() {
    if (_videoPlayer == null) return;
    final duration = _videoPlayer!.value.duration.inMilliseconds / 1000.0;
    final position = _videoPlayer!.value.position.inMilliseconds / 1000.0;
    
    if (duration > 1 && (_session.videoDuration - duration).abs() > 0.5) {
      _session.setVideoDuration(duration);
    }
    
    _syncSectionHighlight(position);
  }

  void _onSessionChanged() {
    _syncRowControllers();
    if (mounted) setState(() {});
  }

  void _onPlayerValue(YoutubePlayerValue value) {
    final title = value.metaData.title.trim();
    if (title.isNotEmpty) {
      _videoTitle = title;
    }
    final seconds = value.metaData.duration.inMilliseconds / 1000.0;
    if (seconds > 1 && (_session.videoDuration - seconds).abs() > 0.5) {
      _session.setVideoDuration(seconds);
    }
  }

  void _onVideoState(YoutubeVideoState state) {
    _syncSectionHighlight(state.position.inMilliseconds / 1000.0);
  }

  void _syncSectionHighlight(double time) {
    final index = _sectionIndexForTime(time);
    if (index == _highlightedSection) return;
    _highlightedSection = index;
    if (mounted) setState(() {});
  }

  int _sectionIndexForTime(double time) {
    final segments = _session.segments;
    if (_session.isTesting) {
      final playing = _session.testSegmentIndex.clamp(0, segments.length - 1);
      final segment = segments[playing];
      if (time >= segment.startSec - 0.3 && time <= segment.endSec + 0.3) {
        return playing;
      }
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (time >= segment.startSec && time <= segment.endSec) {
        return i;
      }
    }
    if (_session.isTesting) return _session.testSegmentIndex;
    return _session.selectedIndex;
  }

  void _syncRowControllers() {
    while (_startControllers.length < _session.segments.length) {
      final index = _startControllers.length;
      final segment = _session.segments[index];
      _startControllers.add(TextEditingController(text: formatMmSs(segment.startSec)));
      _endControllers.add(TextEditingController(text: formatMmSs(segment.endSec)));
      _startFocus.add(FocusNode()..addListener(_onTimeFocusChanged));
      _endFocus.add(FocusNode()..addListener(_onTimeFocusChanged));
    }
    while (_startControllers.length > _session.segments.length) {
      _startControllers.removeLast().dispose();
      _endControllers.removeLast().dispose();
      _startFocus.removeLast()
        ..removeListener(_onTimeFocusChanged)
        ..dispose();
      _endFocus.removeLast()
        ..removeListener(_onTimeFocusChanged)
        ..dispose();
    }
    for (var i = 0; i < _session.segments.length; i++) {
      final segment = _session.segments[i];
      if (!_startFocus[i].hasFocus) {
        final text = formatMmSs(segment.startSec);
        if (_startControllers[i].text != text) {
          _startControllers[i].text = text;
        }
      }
      if (!_endFocus[i].hasFocus) {
        final text = formatMmSs(segment.endSec);
        if (_endControllers[i].text != text) {
          _endControllers[i].text = text;
        }
      }
    }
  }

  void _onTimeFocusChanged() {
    for (var i = 0; i < _session.segments.length; i++) {
      if (!_startFocus[i].hasFocus) {
        _commitTimeField(index: i, isStart: true, allowSeek: false);
      }
      if (!_endFocus[i].hasFocus) {
        _commitTimeField(index: i, isStart: false, allowSeek: false);
      }
    }
  }

  void _onTimeChanged(String value, int index, bool isStart) {
    if (value.isEmpty) return;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final hasColon = value.contains(':');
    final complete = (hasColon && value.split(':').length >= 2) || digits.length >= 4;
    if (!complete) return;
    if (parseTimeInput(value) == null) return;
    _commitTimeField(index: index, isStart: isStart, allowSeek: true);
  }

  Future<void> _seekTo(double seconds, {bool force = false}) async {
    if (_inWidgetTest) return;
    debugPrint('[SEEK] seconds=$seconds');
    final now = DateTime.now();
    if (!force &&
        _lastSeekAt != null &&
        now.difference(_lastSeekAt!) < const Duration(milliseconds: 40)) {
      return;
    }
    _lastSeekAt = now;

    try {
      switch (_session.sourceType) {
        case SourceType.youtube:
          await _yt(
            () => _youtubePlayer.seekTo(seconds: seconds, allowSeekAhead: true),
          );
          break;
        case SourceType.localVideo:
          await _videoPlayer?.seekTo(Duration(milliseconds: (seconds * 1000).toInt()));
          break;
        case SourceType.audio:
          await _audioPlayer?.seek(Duration(milliseconds: (seconds * 1000).toInt()));
          break;
      }
    } catch (_) {}
  }

  Future<void> _applySpeed(double speed) async {
    if (_inWidgetTest) return;
    try {
      switch (_session.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.setPlaybackRate(speed));
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          break;
      }
    } catch (_) {}
  }

  Future<void> _pause() async {
    if (_inWidgetTest) return;
    try {
      switch (_session.sourceType) {
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

  Future<double> _getCurrentTime() async {
    switch (_session.sourceType) {
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



  void _commitTimeField({required int index, required bool isStart, bool allowSeek = true}) {
    final controller = isStart ? _startControllers[index] : _endControllers[index];
    final ok = _session.applyManualTime(index: index, isStart: isStart, text: controller.text);
    final segment = _session.segments[index];
    controller.text = formatMmSs(isStart ? segment.startSec : segment.endSec);
    
    // allowSeek가 false이거나 테스트(루틴 재생) 중이면 절대 비디오 위치를 건드리지 않음
    if (ok && index == _session.selectedIndex && allowSeek && !_session.isTesting) {
      _routineSessionId++;
      _routineTimer?.cancel();
      _loopPlaybackTimer?.cancel();
      _playbackMonitorTimer?.cancel();
      _seekTo(isStart ? segment.startSec : segment.endSec, force: true);
    }
  }

  Future<void> _loadUrl() async {
    final trimmed = _urlController.text.trim();
    final id = extractYoutubeVideoId(trimmed);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }

    // Editing an existing routine already owns its sections — skip cache prompt.
    final skipCachePrompt = widget.isEditMode;

    // 1) Firestore cache first — skip YouTube Data API metadata when present.
    final cached = skipCachePrompt ? null : await _database.getCachedVideo(id);
    if (!mounted) return;

    final useCachedSections = cached != null && cached.hasSections
        ? await showLoadCachedRoutineDialog(context)
        : null;
    if (!mounted) return;

    setState(() {
      _videoId = id;
      _videoUrl = trimmed;
      if (cached != null && cached.title.isNotEmpty) {
        _videoTitle = cached.title;
      }
    });

    if (cached != null) {
      debugPrint(
        '[LOOPI] cached_videos hit $id sections=${cached.sections.length} '
        'choice=$useCachedSections',
      );
      if (useCachedSections == true) {
        _session.applyCachedSections(
          cached.sections,
          duration: cached.duration > 1 ? cached.duration : null,
        );
      } else {
        // "새로 설정" or dismissed → default empty window (keep cached duration if known).
        _session.resetToDefaultSections(
          duration: cached.duration > 1 ? cached.duration : null,
        );
      }
      _syncRowControllers();
      if (mounted) setState(() {});
    } else {
      debugPrint('[LOOPI] cached_videos miss $id — loading via player (no Data API)');
      // No cache: default/empty sections; duration fills in from iframe metadata.
      _session.resetToDefaultSections();
      _syncRowControllers();
      if (mounted) setState(() {});
    }

    // Playback still uses the iframe player (not YouTube Data API quota).
    await _yt(() => _youtubePlayer.cueVideoById(videoId: id));
  }

  Future<void> _persistCachedVideo(SavedRoutine routine) async {
    final id = resolveYoutubeVideoId(videoId: routine.videoId, videoUrl: routine.videoUrl);
    if (id == null || id.isEmpty) return;
    if (routine.sourceType != SourceType.youtube) return;
    await _database.upsertCachedVideo(
      videoId: id,
      title: (_videoTitle?.trim().isNotEmpty == true) ? _videoTitle!.trim() : routine.name,
      duration: _session.videoDuration,
      thumbnailUrl: youtubeThumbnailUrl(id) ?? '',
      sections: routine.segments,
    );
  }

  String? _normalizeYoutubeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final explicitId = extractYoutubeVideoId(trimmed);
    if (explicitId != null) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && (uri.host.contains('youtube.com') || uri.host.contains('youtu.be'))) {
        return trimmed;
      }
      return 'https://www.youtube.com/watch?v=$explicitId';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube.com') && !host.contains('youtu.be')) {
      return null;
    }
    return uri.toString();
  }

  Future<void> _pasteFromClipboard() async {
    String? pasted;
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      pasted = clipboardData?.text?.trim();
    } catch (error) {
      debugPrint('Clipboard.getData paste failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }
    if (pasted == null || pasted.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }

    final normalized = _normalizeYoutubeUrl(pasted);
    if (normalized == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
      return;
    }

    _urlController.text = normalized;
    setState(() {
      _videoUrl = normalized;
      _videoId = extractYoutubeVideoId(normalized) ?? _videoId;
    });
    await _loadUrl();
  }

  Future<void> _openYoutubeSearchOrHome() async {
    final query = _urlController.text.trim();
    final uri = query.isEmpty
        ? Uri.parse('https://www.youtube.com')
        : (extractYoutubeVideoId(query) != null
            ? Uri.parse(query)
            : Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}'));

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('studio.url_placeholder'.tr())),
      );
    }
  }

  void _dismissClipboardBanner({String? rawClipboard}) {
    if (!mounted) {
      _showClipboardBanner = false;
      _dismissedClipboardRaw = rawClipboard ?? _dismissedClipboardRaw;
      return;
    }
    setState(() {
      _showClipboardBanner = false;
      _dismissedClipboardRaw = rawClipboard ?? _dismissedClipboardRaw;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  Future<void> _checkClipboardForDetectedLink() async {
    String? text;
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      text = clipboardData?.text?.trim();
    } catch (error) {
      // Flutter Web throws paste_fail when clipboard permission is denied
      // or the read is not tied to a user gesture.
      debugPrint('Clipboard.getData detection skipped: $error');
      return;
    }
    if (text == null || text.isEmpty) return;
    // Ignore the same copied text until the clipboard actually changes.
    if (text == _dismissedClipboardRaw) return;

    final normalized = _normalizeYoutubeUrl(text);
    if (normalized == null) return;
    if (_showClipboardBanner && normalized == _lastDetectedClipboardText) return;

    _lastDetectedClipboardText = normalized;
    if (!mounted) return;

    _urlController.text = normalized;
    setState(() => _showClipboardBanner = true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text('link_studio.detected_copied_link'.tr()),
        showCloseIcon: true,
        closeIconColor: Colors.redAccent,
        action: SnackBarAction(
          label: 'studio.load'.tr(),
          onPressed: () {
            _dismissClipboardBanner(rawClipboard: text);
            _loadUrl();
          },
        ),
        duration: const Duration(seconds: 10),
      ),
    )
        .closed
        .then((reason) {
      if (!mounted) return;
      if (reason == SnackBarClosedReason.action) return;
      setState(() => _showClipboardBanner = false);
      if (reason == SnackBarClosedReason.dismiss ||
          reason == SnackBarClosedReason.swipe ||
          reason == SnackBarClosedReason.timeout) {
        _dismissedClipboardRaw = text;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkClipboardForDetectedLink());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _haltPlayback();
    }
  }

  Future<void> _selectRow(int index) async {
    if (_session.isTesting) return;
    _routineSessionId++;
    _routineTimer?.cancel();
    _loopPlaybackTimer?.cancel();
    _playbackMonitorTimer?.cancel();
    
    _session.selectSegment(index);
    final segment = _session.segments[index];
    _applySpeed(segment.speed);
    _seekTo(segment.startSec, force: true);
  }

  void _onRangeChangeStart(RangeValues values) {
    _rangeBeforeDrag = values;
  }

  void _onRangeChanged(RangeValues values) {
    if (_session.isTesting) return;
    _routineSessionId++;
    _routineTimer?.cancel();
    _loopPlaybackTimer?.cancel();
    _playbackMonitorTimer?.cancel();
    
    final previous = _rangeBeforeDrag ?? _session.activeRange;
    final startMoved = (values.start - previous.start).abs();
    final endMoved = (values.end - previous.end).abs();
    _session.updateActiveRange(values);
    _rangeBeforeDrag = _session.activeRange;
    if (startMoved >= endMoved) {
      _seekTo(_session.active.startSec);
    } else {
      _seekTo(_session.active.endSec);
    }
  }

  bool get _isPlayerReady {
    if (_inWidgetTest) return true;
    switch (_session.sourceType) {
      case SourceType.youtube:
        return _youtubeInitialized;
      case SourceType.localVideo:
        return _videoPlayer != null && _videoPlayer!.value.isInitialized;
      case SourceType.audio:
        return _audioPlayer != null && !_audioLoading;
    }
  }

  Future<void> _toggleTestPlayback() async {
    if (_session.isTesting) {
      await _stopTestPlayback();
      return;
    }
    if (!_isPlayerReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('영상을 불러오는 중입니다. 잠시 후 다시 시도해주세요.')),
      );
      return;
    }

    _routineSessionId++;
    _routineTimer?.cancel();
    _loopPlaybackTimer?.cancel();
    _playbackMonitorTimer?.cancel();
    _isSeeking = false;
    _isAdvancing = false;

    final activeIndex = _session.selectedIndex.clamp(0, _session.segments.length - 1);
    _session.selectSegment(activeIndex);
    _session.beginTest(startIndex: activeIndex);
    await _jumpToSegment(activeIndex);
  }

  Future<void> _jumpToSegment([int? targetIndex]) async {
    if (!mounted || !_session.isTesting) return;

    if (targetIndex != null) {
      _session.selectSegment(targetIndex);
    }

    _routineSessionId++;
    final int currentSession = _routineSessionId;
    _playbackMonitorTimer?.cancel();

    final segment = _session.testSegment;
    final double startSec = segment.startSec;
    final double endSec = segment.endSec;
    final double speed = segment.speed;
    final int delaySec = segment.delaySec;


    debugPrint('[SEGMENT] start=$startSec end=$endSec');

    if (endSec <= startSec) return;

    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 500));
    _isSeeking = true;
    _isAdvancing = false;
    setState(() {});

    if (_inWidgetTest) return;

    try {
      // 딜레이 시간 계산: 기본 120ms + (사용자 설정 딜레이 초 * 1000)ms
      final waitDuration = Duration(milliseconds: 120 + (delaySec * 1000));

      switch (_session.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.setPlaybackRate(speed));
          await _seekTo(startSec, force: true);
          await Future<void>.delayed(waitDuration);
          _isSeeking = false;
          if (!_youtubeAlive) return;
          await _yt(() => _youtubePlayer.playVideo());
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(speed);
          await _seekTo(startSec, force: true);
          await Future<void>.delayed(waitDuration);
          _isSeeking = false;
          await _videoPlayer?.play();
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(speed);
          await _seekTo(startSec, force: true);
          await Future<void>.delayed(waitDuration);
          _isSeeking = false;
          await _audioPlayer?.resume();
          break;
      }
    } catch (_) {
      _isSeeking = false;
    }

    _playbackMonitorTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) async {
      if (_routineSessionId != currentSession || !_session.isTesting || !mounted) {
        timer.cancel();
        return;
      }

      if (_isSeeking || _isAdvancing) return;

      try {
        final time = await _getCurrentTime();
        _onTime(time, startSec, endSec);
      } catch (_) {}
    });
  }

  void _onTime(double time, double startSec, double endSec) {
    if (_isSeeking || _isAdvancing) return;
    if (_ignoreUntil != null && DateTime.now().isBefore(_ignoreUntil!)) return;

    if (time < startSec - 0.1) return;
    if (time + 0.12 < endSec) return;

    unawaited(_advanceLoopSegment());
  }
  Future<void> _advanceLoopSegment() async {
    if (_isAdvancing) return;
    _isAdvancing = true;

    try {
      if (!_session.isTesting || !mounted) return;

      final segment = _session.testSegment;
      final delaySec = segment.delaySec;
      final result = _session.onLoopHit();

      switch (result) {
        case LoopHitResult.seekToStart:
          debugPrint('🔁 [Repeat Loop] Count: ${_session.playsRemaining}');
          await _replayWithDelay(delaySec);
          break;
        case LoopHitResult.nextSegment:
          debugPrint('⏭️ [Next Loop] Moving to next segment: ${_session.testSegmentIndex}');
          await _startSegmentWithDelay(_session.testSegmentIndex, delaySec);
          break;
        case LoopHitResult.finished:
          debugPrint('🏁 [Routine Finished]');
          await _stopTestPlayback();
          break;
      }
    } finally {
      _isAdvancing = false;
    }
  }

  Future<void> _replayWithDelay(int delaySec) async {
    await _waitDelay(delaySec);
    if (!_session.isTesting || !mounted) return;
    await _replayCurrent();
  }

  Future<void> _startSegmentWithDelay(int index, int delaySec) async {
    await _waitDelay(delaySec);
    if (!_session.isTesting || !mounted) return;
    await _jumpToSegment(index);
  }

  Future<void> _replayCurrent() async {
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 280));
    if (_inWidgetTest) return;
    _isSeeking = true;

    try {
      final segment = _session.testSegment;
      switch (_session.sourceType) {
        case SourceType.youtube:
          await _yt(() => _youtubePlayer.setPlaybackRate(segment.speed));
          await _seekTo(segment.startSec, force: true);
          break;
        case SourceType.localVideo:
          await _videoPlayer?.setPlaybackSpeed(segment.speed);
          await _seekTo(segment.startSec, force: true);
          break;
        case SourceType.audio:
          await _audioPlayer?.setPlaybackRate(segment.speed);
          await _seekTo(segment.startSec, force: true);
          break;
      }
    } catch (_) {}

    _isSeeking = false;

    try {
      switch (_session.sourceType) {
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

  Future<void> _waitDelay(int delaySec) async {
    if (delaySec <= 0 || _inWidgetTest) return;
    try {
      await _pause();
    } catch (_) {}
    _delayCompleter = Completer<void>();
    _delayTimer?.cancel();
    _delayTimer = Timer(Duration(seconds: delaySec), () {
      final pending = _delayCompleter;
      if (pending != null && !pending.isCompleted) pending.complete();
    });
    await _delayCompleter!.future;
    _delayCompleter = null;
  }

  Future<void> _stopTestPlayback() async {
    _routineSessionId++;
    _delayTimer?.cancel();
    _delayTimer = null;
    _loopPlaybackTimer?.cancel();
    _loopPlaybackTimer = null;
    _routineTimer?.cancel();
    _routineTimer = null;
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = null;
    _isSeeking = false;
    _isAdvancing = false;
    _session.stopTest();
    _highlightedSection = _session.selectedIndex;
    if (!_inWidgetTest) {
      try {
        await _pause();
        await _applySpeed(_session.active.speed);
        await _seekTo(_session.active.startSec, force: true);
      } catch (_) {}
    }
  }

  Future<void> _onSavePressed() async {
    if (_session.isTesting) {
      await _stopTestPlayback();
    }
    if (!mounted) return;

    setState(() => _saveDialogOpen = true);
    if (!_inWidgetTest) {
      try {
        await _pause();
      } catch (_) {}
    }
    if (!mounted) return;

    final editing = widget.editingRoutine;
    final result = await showSaveRoutineDialog(
      context,
      initialName: editing?.name,
      allowOverwrite: editing != null,
      initialCategory: editing?.category,
    );
    if (!mounted) return;
    setState(() => _saveDialogOpen = false);
    if (result == null) return;

    final overwrite = result.overwrite && editing != null;
    final routine = _session.toSavedRoutine(
      name: result.name,
      videoUrl: _videoUrl,
      videoId: _videoId,
      id: overwrite ? editing.id : null,
      createdAt: overwrite ? editing.createdAt : null,
      isFavorite: overwrite ? editing.isFavorite : false,
      authorId: overwrite ? editing.authorId : 'me',
      authorName: overwrite ? editing.authorName : '나',
      category: result.category,
      isMirrored: _isMirrored ?? false,
    );

    if (overwrite) {
      await widget.library.update(routine);
      unawaited(_persistCachedVideo(routine));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${result.name}" 루틴을 덮어썼습니다.')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(routine);
      }
      return;
    }

    await widget.library.save(routine);
    unawaited(_persistCachedVideo(routine));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${result.name}" ${'studio.save_success'.tr()}')),
    );

    if (editing != null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(routine);
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeModeScreen(routine: routine, library: widget.library),
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _haltPlayback();
    _loopPlaybackTimer?.cancel();
    _delayTimer?.cancel();
    _routineTimer?.cancel();
    _playbackMonitorTimer?.cancel();
    _valueSub?.cancel();
    _stateSub?.cancel();
    _valueSub = null;
    _stateSub = null;
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _routineListHorizontalController.dispose();
    _routineListVerticalController.dispose();
    _urlController.dispose();
    for (final c in _startControllers) {
      c.dispose();
    }
    for (final c in _endControllers) {
      c.dispose();
    }
    for (final n in _startFocus) {
      n.removeListener(_onTimeFocusChanged);
      n.dispose();
    }
    for (final n in _endFocus) {
      n.removeListener(_onTimeFocusChanged);
      n.dispose();
    }
    if (_youtubeInitialized) {
      unawaited(closeYoutubePlayerSafely(_youtubePlayer));
    }
    _videoPlayer?.dispose();
    _audioPlayer?.dispose();
    revokeMediaBlobUrl(_mediaObjectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testing = _session.isTesting;
    
    switch (_session.sourceType) {
      case SourceType.youtube:
        return _buildYouTubeScaffold(testing);
      case SourceType.localVideo:
        return _buildVideoScaffold(testing);
      case SourceType.audio:
        return _buildAudioScaffold(testing);
    }
  }

  Widget _buildYouTubeScaffold(bool testing) {
    if (!_youtubeInitialized) {
      return _buildMainScaffold(
        testing: testing,
        mediaWidget: Center(
          child: Text(
            'studio.player_placeholder'.tr(),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        showUrlBar: true,
      );
    }
    return YoutubePlayerScaffold(
      controller: _youtubePlayer,
      aspectRatio: _isVerticalMedia ? 9 / 16 : 16 / 9,
      builder: (context, player) {
        return _buildMainScaffold(
          testing: testing,
          mediaWidget: _inWidgetTest || _saveDialogOpen
              ? Center(
                  child: Text(
                    'studio.player_placeholder'.tr(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : player,
          showUrlBar: true,
        );
      },
    );
  }

  Widget _buildVideoScaffold(bool testing) {
    return _buildMainScaffold(
      testing: testing,
      mediaWidget: _videoLoadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _videoLoadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _initializeVideoPlayer,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            )
          : _videoPlayer != null && _videoPlayer!.value.isInitialized
              ? VideoPlayer(_videoPlayer!)
              : const Center(
                  child: CircularProgressIndicator(),
                ),
      showUrlBar: false,
    );
  }

  Widget _buildAudioScaffold(bool testing) {
    return _buildMainScaffold(
      testing: testing,
      mediaWidget: _buildAudioPlayerWidget(),
      showUrlBar: false,
    );
  }

  Widget _buildAudioPlayerWidget() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq_rounded, color: LoopiColors.purple, size: 64),
          const SizedBox(height: 16),
          if (_audioLoading) const CircularProgressIndicator(color: LoopiColors.purple),
          if (_audioLoading) const SizedBox(height: 12),
          Text(
            'studio.audio_mode'.tr(),
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_session.fileName != null)
            Text(
              _session.fileName!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildMainScaffold({
    required bool testing,
    required Widget mediaWidget,
    required bool showUrlBar,
  }) {
    final sourceBar = showUrlBar ? _urlBar() : _fileInfoBar();
    final ratio = _mediaAspectRatio <= 0 ? 16 / 9 : _mediaAspectRatio;

    return Scaffold(
      backgroundColor: LoopiColors.pageBackground(context),
      appBar: widget.embedded || !Navigator.of(context).canPop()
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: LoopiColors.text(context),
              elevation: 0,
              title: const AppLogo(height: 30),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = !_videoFitsInColumn(constraints, ratio);
                if (sideBySide) {
                  return _buildSideBySideBody(
                    constraints: constraints,
                    sourceBar: sourceBar,
                    mediaWidget: mediaWidget,
                    ratio: ratio,
                    testing: testing,
                  );
                }
                return _buildStackedBody(
                  sourceBar: sourceBar,
                  mediaWidget: mediaWidget,
                  ratio: ratio,
                  testing: testing,
                );
              },
            ),
          ),
          _bottomBar(testing),
        ],
      ),
    );
  }

  Widget _buildStackedBody({
    required Widget sourceBar,
    required Widget mediaWidget,
    required double ratio,
    required bool testing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kStudioHPad, _kStudioVPad, _kStudioHPad, _kStudioVPad),
      child: Column(
        children: [
          sourceBar,
          const SizedBox(height: _kStudioUrlGap),
          AspectRatio(
            aspectRatio: ratio,
            child: _mediaSurface(mediaWidget),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _intervalControlsScroll(testing: testing, compact: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBySideBody({
    required BoxConstraints constraints,
    required Widget sourceBar,
    required Widget mediaWidget,
    required double ratio,
    required bool testing,
  }) {
    final innerH = (constraints.maxHeight - _kStudioVPad * 2).clamp(1.0, constraints.maxHeight);
    final innerW = (constraints.maxWidth - _kStudioHPad * 2).clamp(1.0, constraints.maxWidth);
    var videoWidth = innerH * ratio;
    final maxVideoWidth =
        (innerW - _kStudioColumnGap - _kStudioMinSettingsWidth).clamp(80.0, innerW);
    if (videoWidth > maxVideoWidth) videoWidth = maxVideoWidth;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kStudioHPad, _kStudioVPad, _kStudioHPad, _kStudioVPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: videoWidth,
            child: _fittedMedia(mediaWidget, ratio),
          ),
          const SizedBox(width: _kStudioColumnGap),
          Expanded(
            child: Column(
              children: [
                sourceBar,
                const SizedBox(height: 8),
                Expanded(
                  child: _intervalControlsScroll(testing: testing, compact: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaSurface(Widget mediaWidget) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Transform.flip(
              flipX: _isMirrored ?? false,
              child: mediaWidget,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fittedMedia(Widget mediaWidget, double ratio) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite || !constraints.maxWidth.isFinite) {
          return AspectRatio(
            aspectRatio: ratio,
            child: _mediaSurface(mediaWidget),
          );
        }
        var width = constraints.maxWidth;
        var height = width / ratio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * ratio;
        }
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: _mediaSurface(mediaWidget),
          ),
        );
      },
    );
  }

  Widget _intervalControlsScroll({required bool testing, required bool compact}) {
    return ScrollConfiguration(
      behavior: const _MouseDragScrollBehavior(),
      child: ListView(
        controller: _routineListVerticalController,
        primary: false,
        children: [_intervalControls(testing, compact: compact)],
      ),
    );
  }

  Widget _intervalControls(bool testing, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionChips(),
        SizedBox(height: compact ? 4 : 8),
        _timeline(compact: compact),
        SizedBox(height: compact ? 8 : 16),
        _routineTable(testing, compact: compact),
      ],
    );
  }

  Widget _urlBar() {
    return Material(
      color: LoopiColors.card(context),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                enabled: !_session.isTesting,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Paste a YouTube URL',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  suffixIcon: IconButton(
                    tooltip: 'link_studio.paste_from_clipboard'.tr(),
                    onPressed: _session.isTesting ? null : _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, color: LoopiColors.deepPurple),
                  ),
                ),
                onSubmitted: (_) => _loadUrl(),
              ),
            ),
            TextButton(
              onPressed: _session.isTesting ? null : _loadUrl,
              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: LoopiColors.deepPurple),
              child: Text('studio.load'.tr()),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'link_studio.search_on_youtube'.tr(),
              onPressed: _openYoutubeSearchOrHome,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000).withValues(alpha: 0.12),
                foregroundColor: const Color(0xFFFF0000),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileInfoBar() {
    return Material(
      color: LoopiColors.card(context),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              _session.sourceType == SourceType.audio 
                  ? Icons.graphic_eq_rounded 
                  : Icons.videocam_rounded,
              color: LoopiColors.deepPurple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _session.fileName ?? 'studio.file_selected'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _session.sourceType == SourceType.audio 
                        ? 'studio.audio_mode'.tr() 
                        : 'studio.video_mode'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _session.isTesting ? null : _changeFile,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('studio.change_file'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: LoopiColors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: _session.sourceType == SourceType.audio
          ? FileType.custom
          : FileType.video,
      allowedExtensions: _session.sourceType == SourceType.audio
          ? ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'mov', 'webm']
          : null,
      allowMultiple: false,
      withData: true,
    );
    
    if (result != null && result.files.isNotEmpty) {
      final selectedFile = result.files.single;
      final filePath = _platformFilePath(selectedFile);
      final fileBytes = selectedFile.bytes;
      if (filePath == null && fileBytes == null) return;
      final fileName = result.files.single.name;
      
      if (_session.sourceType == SourceType.localVideo) {
        await _videoPlayer?.dispose();
        revokeMediaBlobUrl(_mediaObjectUrl);
        _mediaObjectUrl = _createSelectedVideoBlobUrl(selectedFile);
        _videoPlayer = filePath != null
            ? VideoPlayerController.file(File(filePath))
            : VideoPlayerController.networkUrl(
                _mediaObjectUrl == null
                    ? Uri.dataFromBytes(fileBytes!, mimeType: 'video/mp4')
                    : Uri.parse(_mediaObjectUrl!),
              );
        _videoLoadError = null;
        try {
          await _videoPlayer!.initialize().timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw TimeoutException('Video initialization timed out'),
              );
          _session.setVideoDuration(_videoPlayer!.value.duration.inMilliseconds / 1000.0);
          _videoPlayer!.addListener(_onVideoPlayerUpdate);
        } catch (error) {
          debugPrint('Video initialization error: $error');
          _videoLoadError = '영상을 불러오지 못했습니다. 다시 시도해주세요.';
        }
      } else if (_session.sourceType == SourceType.audio) {
        await _audioPlayer?.dispose();
        _audioPlayer = AudioPlayer();
        if (filePath != null) {
          await _audioPlayer!.setSourceDeviceFile(filePath);
        } else {
          await _audioPlayer!.setSourceBytes(fileBytes!);
        }
        final duration = await _audioPlayer!.getDuration();
        if (duration != null) {
          _session.setVideoDuration(duration.inMilliseconds / 1000.0);
        }
        _audioPlayer!.onPositionChanged.listen((position) {
          _syncSectionHighlight(position.inMilliseconds / 1000.0);
        });
      }
      
      _session.setSourceType(
        _session.sourceType,
        localFilePath: filePath,
        fileName: fileName,
        localDataBytes: fileBytes,
      );
      
      if (mounted) setState(() {});
    }
  }

  Widget _sectionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: Row(
        children: [
          for (var i = 0; i < _session.segments.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(
                builder: (context) {
                  final testing = _session.isTesting;
                  final active = testing ? i == _highlightedSection : i == _session.selectedIndex;
                  final highlight = _session.segments[i].isHighlight;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: Text(sectionLabelForIndex(i)),
                        selected: active,
                        showCheckmark: !testing,
                        selectedColor: testing
                            ? LoopiColors.deepPurple
                            : LoopiColors.purple.withValues(alpha: 0.18),
                        labelStyle: TextStyle(
                          color: highlight
                              ? kHighlightPink
                              : testing && active
                                  ? Colors.white
                                  : active
                                      ? LoopiColors.purple
                                      : LoopiColors.text(context),
                          fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
                        ),
                        onSelected: testing ? null : (_) => _selectRow(i),
                      ),
                      if (i != 0 && !testing)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _session.removeSegment(i),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '삭제',
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeline({bool compact = false}) {
    final range = _session.activeRange;
    final max = _session.videoDuration <= 0 ? 1.0 : _session.videoDuration;
    return Material(
      color: LoopiColors.card(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
            : const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'studio.timeline'.tr(),
              style: TextStyle(fontWeight: FontWeight.w700, color: LoopiColors.text(context)),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${'studio.start'.tr()} ${formatMmSs(range.start)}', style: TextStyle(color: LoopiColors.textMuted(context), fontSize: 12)),
                const Spacer(),
                Text('${'studio.end'.tr()} ${formatMmSs(range.end)}', style: TextStyle(color: LoopiColors.textMuted(context), fontSize: 12)),
              ],
            ),
            RangeSlider(
              values: RangeValues(
                range.start.clamp(0.0, max),
                range.end.clamp(0.0, max),
              ),
              min: 0,
              max: max,
              divisions: max.floor().clamp(1, 6000),
              activeColor: LoopiColors.purple,
              labels: RangeLabels(formatMmSs(range.start), formatMmSs(range.end)),
              onChangeStart: _session.isTesting ? null : _onRangeChangeStart,
              onChanged: _session.isTesting ? null : _onRangeChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mirrorToggleButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: '미러 모드 (좌우 반전)',
        onPressed: () {
          setState(() {
            _isMirrored = !(_isMirrored ?? false);
          });
        },
        isSelected: _isMirrored ?? false,
        style: IconButton.styleFrom(
          backgroundColor: (_isMirrored ?? false) ? LoopiColors.purple.withValues(alpha: 0.22) : Colors.transparent,
          foregroundColor: (_isMirrored ?? false) ? LoopiColors.purple : LoopiColors.muted,
        ),
        icon: const Icon(Icons.flip_outlined),
        selectedIcon: const Icon(Icons.flip),
      ),
    );
  }

  Widget _routineTable(bool testing, {required bool compact}) {
    return Material(
      color: LoopiColors.card(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(6, 6, 6, 4)
            : const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'studio.routine_list'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                if (_session.sourceType != SourceType.audio) _mirrorToggleButton(),
                IconButton.filled(
                  onPressed: testing ? null : _session.addSegment,
                  style: IconButton.styleFrom(backgroundColor: LoopiColors.deepPurple),
                  icon: const Icon(Icons.add, color: Colors.white),
                  tooltip: 'studio.add_section'.tr(),
                ),
              ],
            ),
            SizedBox(height: compact ? 4 : 8),
            LayoutBuilder(
              builder: (context, tableConstraints) {
                final table = DataTable(
                  showCheckboxColumn: false,
                  columnSpacing: compact ? 8 : 16,
                  horizontalMargin: compact ? 4 : 8,
                  headingRowHeight: compact ? 28 : 36,
                  dataRowMinHeight: compact ? 40 : 52,
                  dataRowMaxHeight: compact ? 48 : 64,
                  headingTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LoopiColors.muted,
                  ),
                  columns: [
                    DataColumn(label: Text('studio.section'.tr())),
                    DataColumn(label: Text('studio.start'.tr())),
                    DataColumn(label: Text('studio.end'.tr())),
                    DataColumn(label: Text('studio.speed'.tr())),
                    DataColumn(label: Text('studio.loop'.tr())),
                    DataColumn(label: Text('studio.delay'.tr())),
                    const DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (var i = 0; i < _session.segments.length; i++)
                      _buildRow(i, testing, compact: compact),
                  ],
                );
                return ScrollConfiguration(
                  behavior: const _MouseDragScrollBehavior(),
                  child: Scrollbar(
                    controller: _routineListHorizontalController,
                    thumbVisibility: true,
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is! PointerScrollEvent) return;
                        if (!_routineListHorizontalController.hasClients) return;
                        final delta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
                            ? event.scrollDelta.dy
                            : event.scrollDelta.dx;
                        final next = _routineListHorizontalController.offset + delta;
                        _routineListHorizontalController.jumpTo(
                          next.clamp(
                            0.0,
                            _routineListHorizontalController.position.maxScrollExtent,
                          ),
                        );
                      },
                      child: SingleChildScrollView(
                        controller: _routineListHorizontalController,
                        scrollDirection: Axis.horizontal,
                        primary: false,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: tableConstraints.maxWidth),
                          child: table,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(int index, bool testing, {required bool compact}) {
    final selected = index == _session.selectedIndex;
    return DataRow(
      selected: selected,
      color: WidgetStatePropertyAll(
        selected ? LoopiColors.purple.withValues(alpha: 0.08) : Colors.transparent,
      ),
      onSelectChanged: testing ? null : (_) => _selectRow(index),
      cells: [
        DataCell(
          _scaleDownCell(
            compact: true,
            child: Tooltip(
              message: 'studio.set_highlight'.tr(),
              child: InkWell(
                onTap: testing ? null : () => _session.toggleHighlight(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    sectionLabelForIndex(index),
                    style: TextStyle(
                      fontWeight: _session.segments[index].isHighlight
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: _session.segments[index].isHighlight ? kHighlightPink : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        DataCell(_scaleDownCell(compact: true, child: _timeField(index: index, isStart: true, enabled: !testing, compact: compact))),
        DataCell(_scaleDownCell(compact: true, child: _timeField(index: index, isStart: false, enabled: !testing, compact: compact))),
        DataCell(_scaleDownCell(compact: true, child: _speedDropdown(index, testing))),
        DataCell(_scaleDownCell(compact: true, child: _loopDropdown(index, testing))),
        DataCell(_scaleDownCell(compact: true, child: _delayDropdown(index, testing))),
        DataCell(
          IconButton(
            tooltip: 'Delete section',
            visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
            onPressed: testing || index == 0 || _session.segments.length <= 1
                ? null
                : () => _session.removeSegment(index),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Widget _scaleDownCell({required bool compact, required Widget child}) {
    return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
  }

  Widget _speedDropdown(int index, bool testing) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<double>(
        value: _session.segments[index].speed,
        isDense: true,
        onChanged: testing
            ? null
            : (value) {
                if (value == null) return;
                _session.selectSegment(index);
                _session.setSpeed(index, value);
                _applySpeed(value);
              },
        items: [
          for (final speed in kPlaybackSpeeds)
            DropdownMenuItem(value: speed, child: Text(formatSpeedLabel(speed))),
        ],
      ),
    );
  }

  Widget _loopDropdown(int index, bool testing) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _session.segments[index].loopCount,
        isDense: true,
        onChanged: testing
            ? null
            : (value) {
                if (value == null) return;
                _session.selectSegment(index);
                _session.setLoopCount(index, value);
              },
        items: [
          for (var n = 1; n <= 10; n++)
            DropdownMenuItem(value: n, child: Text('${n}x')),
          const DropdownMenuItem(value: kInfiniteLoop, child: Text('Infinite')),
        ],
      ),
    );
  }

  Widget _delayDropdown(int index, bool testing) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: kDelaySeconds.contains(_session.segments[index].delaySec)
            ? _session.segments[index].delaySec
            : kDelaySeconds.first,
        isDense: true,
        onChanged: testing
            ? null
            : (value) {
                if (value == null) return;
                _session.selectSegment(index);
                _session.setDelaySec(index, value);
              },
        items: [
          for (final delay in kDelaySeconds)
            DropdownMenuItem(value: delay, child: Text(formatDelayLabel(delay))),
        ],
      ),
    );
  }

  Widget _timeField({
    required int index,
    required bool isStart,
    required bool enabled,
    bool compact = false,
  }) {
    return SizedBox(
      width: compact ? 56 : 72,
      child: TextField(
        controller: isStart ? _startControllers[index] : _endControllers[index],
        focusNode: isStart ? _startFocus[index] : _endFocus[index],
        enabled: enabled,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: compact ? 12 : 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 3 : 6, vertical: compact ? 4 : 8),
        ),
        onTap: () {
          if (!enabled) return;
          _session.selectSegment(index);
        },
        onSubmitted: (_) => _commitTimeField(index: index, isStart: isStart, allowSeek: true),
        onEditingComplete: () => _commitTimeField(index: index, isStart: isStart, allowSeek: true),
        onChanged: (value) => _onTimeChanged(value, index, isStart),
      ),
    );
  }

  Widget _bottomBar(bool testing) {
    return Material(
      color: LoopiColors.card(context),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _toggleTestPlayback,
                  style: FilledButton.styleFrom(
                    backgroundColor: testing ? Colors.redAccent : LoopiColors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(testing ? 'Stop Routine' : 'Start Routine'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: testing ? null : _onSavePressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: LoopiColors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Save Routine'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  const _MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  /// Flutter web throws `TypeError: Null is not a subtype of ScrollController`
  /// when [MaterialScrollBehavior] injects a [Scrollbar] with a null controller.
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    final controller = details.controller;
    if (controller == null) return child;
    switch (axisDirectionToAxis(details.direction)) {
      case Axis.horizontal:
        return child;
      case Axis.vertical:
        return Scrollbar(controller: controller, child: child);
    }
  }
}