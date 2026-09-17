import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/class_models.dart';
import '../models/routine_models.dart';
import '../theme/loopi_colors.dart';
import '../utils/time_format.dart';
import '../utils/youtube_id.dart';
import '../utils/youtube_player_factory.dart';

/// Hybrid lecture + practice player for a [ClassCourse] lesson unit.
///
/// Does not modify [PracticeModeScreen] or recording engines — uses its own
/// lightweight YouTube/local controllers for lecture and section loops.
class ClassPlayerScreen extends StatefulWidget {
  const ClassPlayerScreen({
    super.key,
    required this.course,
    this.initialUnitIndex = 0,
  });

  final ClassCourse course;
  final int initialUnitIndex;

  @override
  State<ClassPlayerScreen> createState() => _ClassPlayerScreenState();
}

class _ClassPlayerScreenState extends State<ClassPlayerScreen> {
  late int _unitIndex;
  /// `-1` = lecture clip, `0..n-1` = practice sections.
  int _activeLane = -1;
  bool _sequential = true;
  bool _busy = false;

  YoutubePlayerController? _lectureYt;
  YoutubePlayerController? _practiceYt;
  VideoPlayerController? _lectureVideo;
  VideoPlayerController? _practiceVideo;
  Timer? _poll;
  bool _disposing = false;

  ClassLessonUnit get _unit => widget.course.units[_unitIndex.clamp(0, widget.course.units.length - 1)];

  SavedRoutine? get _routine => _unit.practiceRoutine;

  List<RoutineSegment> get _segments => _routine?.segments ?? const [];

  bool get _lectureAlive => !_disposing && mounted && _lectureYt != null;
  bool get _practiceAlive => !_disposing && mounted && _practiceYt != null;

  @override
  void initState() {
    super.initState();
    _unitIndex = widget.initialUnitIndex.clamp(0, widget.course.units.isEmpty ? 0 : widget.course.units.length - 1);
    unawaited(_loadLane(-1, autoPlay: true));
  }

  @override
  void dispose() {
    _disposing = true;
    _poll?.cancel();
    unawaited(closeYoutubePlayerSafely(_lectureYt));
    unawaited(closeYoutubePlayerSafely(_practiceYt));
    _lectureVideo?.dispose();
    _practiceVideo?.dispose();
    super.dispose();
  }

  Future<void> _pauseAll() async {
    try {
      await safeYoutubePlayerCallOn(_lectureYt, (p) => p.pauseVideo(), isAlive: () => _lectureAlive);
    } catch (_) {}
    try {
      await safeYoutubePlayerCallOn(_practiceYt, (p) => p.pauseVideo(), isAlive: () => _practiceAlive);
    } catch (_) {}
    try {
      await _lectureVideo?.pause();
    } catch (_) {}
    try {
      await _practiceVideo?.pause();
    } catch (_) {}
  }

  Future<void> _loadLane(int lane, {bool autoPlay = true}) async {
    if (_busy || widget.course.units.isEmpty) return;
    _busy = true;
    _poll?.cancel();
    await _pauseAll();
    if (!mounted) return;
    setState(() => _activeLane = lane);

    try {
      if (lane < 0) {
        await _ensureLectureLoaded();
        if (autoPlay) await _playLecture();
        if (_sequential) _startLectureEndWatch();
      } else {
        await _ensurePracticeLoaded();
        await _playSection(lane, autoPlay: autoPlay);
        if (_sequential) _startSectionEndWatch(lane);
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _ensureLectureLoaded() async {
    final url = _unit.lessonVideoUrl;
    final ytId = extractYoutubeVideoId(url);
    if (ytId != null) {
      if (_lectureYt == null) {
        _lectureYt = createLoopiYoutubeController(videoId: ytId, autoPlay: false);
      } else {
        await safeYoutubePlayerCallOn(
          _lectureYt,
          (p) => p.cueVideoById(videoId: ytId),
          isAlive: () => _lectureAlive,
        );
      }
      return;
    }
    if (_lectureVideo == null && url.startsWith('http')) {
      _lectureVideo = VideoPlayerController.networkUrl(Uri.parse(url));
      await _lectureVideo!.initialize();
    }
  }

  Future<void> _ensurePracticeLoaded() async {
    final routine = _routine;
    if (routine == null) return;
    if (routine.sourceType == SourceType.youtube) {
      final id = resolveYoutubeVideoId(videoId: routine.videoId, videoUrl: routine.videoUrl);
      if (id == null) return;
      if (_practiceYt == null) {
        _practiceYt = createLoopiYoutubeController(videoId: id, autoPlay: false);
      } else {
        await safeYoutubePlayerCallOn(
          _practiceYt,
          (p) => p.cueVideoById(videoId: id),
          isAlive: () => _practiceAlive,
        );
      }
      return;
    }
    final path = routine.localFilePath ?? routine.videoUrl;
    if (path.isEmpty) return;
    if (_practiceVideo == null) {
      _practiceVideo = VideoPlayerController.networkUrl(Uri.parse(path));
      await _practiceVideo!.initialize();
    }
  }

  Future<void> _playLecture() async {
    if (_lectureYt != null) {
      await safeYoutubePlayerCallOn(_lectureYt, (p) => p.playVideo(), isAlive: () => _lectureAlive);
      return;
    }
    await _lectureVideo?.play();
  }

  Future<void> _playSection(int index, {bool autoPlay = true}) async {
    if (index < 0 || index >= _segments.length) return;
    final segment = _segments[index];
    final start = segment.startSec;
    final end = segment.endSec > start ? segment.endSec : null;
    final speed = segment.speed <= 0 ? 1.0 : segment.speed;
    final mirrored = _routine?.isMirroredOn ?? false;

    if (_practiceYt != null) {
      final id = resolveYoutubeVideoId(videoId: _routine!.videoId, videoUrl: _routine!.videoUrl);
      if (id != null) {
        await safeYoutubePlayerCallOn(
          _practiceYt,
          (p) => p.cueVideoById(videoId: id, startSeconds: start, endSeconds: end),
          isAlive: () => _practiceAlive,
        );
      }
      await safeYoutubePlayerCallOn(
        _practiceYt,
        (p) => p.seekTo(seconds: start, allowSeekAhead: true),
        isAlive: () => _practiceAlive,
      );
      await safeYoutubePlayerCallOn(
        _practiceYt,
        (p) => p.setPlaybackRate(speed),
        isAlive: () => _practiceAlive,
      );
      if (autoPlay) {
        await safeYoutubePlayerCallOn(_practiceYt, (p) => p.playVideo(), isAlive: () => _practiceAlive);
      }
      // Mirror is visual-only via Transform.flip in the viewport.
      debugPrint('[LOOPI] class player section ${sectionLabelForIndex(index)} '
          'speed=$speed mirror=$mirrored');
      return;
    }

    final video = _practiceVideo;
    if (video == null || !video.value.isInitialized) return;
    await video.setPlaybackSpeed(speed);
    await video.seekTo(Duration(milliseconds: (start * 1000).round()));
    if (autoPlay) await video.play();
  }

  void _startLectureEndWatch() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_sequential || _activeLane != -1 || _disposing) return;
      try {
        if (_lectureYt != null) {
          final state = await safeYoutubePlayerCallOn(
            _lectureYt,
            (p) async => p.value.playerState,
            isAlive: () => _lectureAlive,
          );
          if (state == PlayerState.ended) {
            await _advanceSequential();
          }
        } else if (_lectureVideo != null && _lectureVideo!.value.isInitialized) {
          final v = _lectureVideo!.value;
          if (v.position >= v.duration - const Duration(milliseconds: 400)) {
            await _advanceSequential();
          }
        }
      } catch (_) {}
    });
  }

  void _startSectionEndWatch(int index) {
    _poll?.cancel();
    if (index < 0 || index >= _segments.length) return;
    final segment = _segments[index];
    final end = segment.endSec;
    var loopsLeft = segment.loopCount <= 0 ? 1 : segment.loopCount;

    _poll = Timer.periodic(const Duration(milliseconds: 350), (_) async {
      if (!_sequential || _activeLane != index || _disposing) return;
      try {
        double? t;
        if (_practiceYt != null) {
          t = await safeYoutubePlayerCallOn(
            _practiceYt,
            (p) => p.currentTime,
            isAlive: () => _practiceAlive,
          );
        } else if (_practiceVideo != null && _practiceVideo!.value.isInitialized) {
          t = _practiceVideo!.value.position.inMilliseconds / 1000.0;
        }
        if (t == null) return;
        if (t >= end - 0.15) {
          loopsLeft -= 1;
          if (loopsLeft > 0) {
            await _playSection(index, autoPlay: true);
          } else {
            await _advanceSequential();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _advanceSequential() async {
    if (!_sequential) return;
    if (_activeLane < 0) {
      if (_segments.isNotEmpty) {
        await _loadLane(0, autoPlay: true);
      }
      return;
    }
    final next = _activeLane + 1;
    if (next < _segments.length) {
      await _loadLane(next, autoPlay: true);
      return;
    }
    // Finished current unit — stop at end.
    await _pauseAll();
    _poll?.cancel();
  }

  Widget _viewport() {
    final showingLecture = _activeLane < 0;
    final mirror = !showingLecture && (_routine?.isMirroredOn ?? false);
    Widget child;
    if (showingLecture) {
      if (_lectureYt != null) {
        child = loopiYoutubePlayer(controller: _lectureYt!, aspectRatio: 16 / 9);
      } else if (_lectureVideo != null && _lectureVideo!.value.isInitialized) {
        child = AspectRatio(
          aspectRatio: _lectureVideo!.value.aspectRatio,
          child: VideoPlayer(_lectureVideo!),
        );
      } else {
        child = const Center(child: CircularProgressIndicator(color: Colors.white));
      }
    } else {
      if (_practiceYt != null) {
        child = loopiYoutubePlayer(controller: _practiceYt!, aspectRatio: 16 / 9);
      } else if (_practiceVideo != null && _practiceVideo!.value.isInitialized) {
        child = AspectRatio(
          aspectRatio: _practiceVideo!.value.aspectRatio,
          child: VideoPlayer(_practiceVideo!),
        );
      } else {
        child = Center(
          child: Text(
            'class.no_practice_routine'.tr(),
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: KeyedSubtree(
        key: ValueKey('lane_$_activeLane'),
        child: Transform.flip(flipX: mirror, child: child),
      ),
    );
  }

  Widget _laneChip({
    required bool selected,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            if (subtitle != null)
              Text(subtitle, style: TextStyle(fontSize: 10, color: selected ? Colors.white70 : null)),
          ],
        ),
        selectedColor: LoopiColors.deepPurple,
        labelStyle: TextStyle(color: selected ? Colors.white : null),
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    return Scaffold(
      backgroundColor: const Color(0xFF120F1C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(unit.unitTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AspectRatio(aspectRatio: 16 / 9, child: _viewport()),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: const Color(0xFF1A1524),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _activeLane < 0
                          ? 'class.mode_lecture'.tr()
                          : 'class.mode_section'.tr(
                              namedArgs: {
                                'label': sectionLabelForIndex(_activeLane),
                                'range':
                                    '${formatMmSs(_segments[_activeLane].startSec)}–${formatMmSs(_segments[_activeLane].endSec)}',
                              },
                            ),
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'class.sequential'.tr(),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    Switch(
                      value: _sequential,
                      activeThumbColor: LoopiColors.purple,
                      onChanged: (v) {
                        setState(() => _sequential = v);
                        if (v) {
                          if (_activeLane < 0) {
                            _startLectureEndWatch();
                          } else {
                            _startSectionEndWatch(_activeLane);
                          }
                        } else {
                          _poll?.cancel();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _laneChip(
                        selected: _activeLane < 0,
                        label: 'class.lane_lecture'.tr(),
                        icon: Icons.tv_outlined,
                        onTap: () => unawaited(_loadLane(-1)),
                      ),
                      for (var i = 0; i < _segments.length; i++)
                        _laneChip(
                          selected: _activeLane == i,
                          label: sectionLabelForIndex(i),
                          subtitle: formatSpeedLabel(_segments[i].speed),
                          onTap: () => unawaited(_loadLane(i)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _sequential ? 'class.sequential_hint'.tr() : 'class.selective_hint'.tr(),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
