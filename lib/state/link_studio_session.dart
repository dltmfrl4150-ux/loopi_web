import 'package:flutter/material.dart';

import '../models/routine_category.dart';
import '../models/routine_models.dart';
import '../utils/time_format.dart';

enum LoopHitResult { seekToStart, nextSegment, finished }

/// Holds LinkStudio segment list, selection, and in-app test-playback counters.
class LinkStudioSession extends ChangeNotifier {
  LinkStudioSession({double initialDuration = 180, SourceType sourceType = SourceType.youtube})
    : _videoDuration = initialDuration,
      _sourceType = sourceType,
      _segments = [
        RoutineSegment(
          id: 'seg_0',
          startSec: 0,
          endSec: _defaultEnd(initialDuration),
        ),
      ];

  static const double minGap = 1;

  final List<RoutineSegment> _segments;
  int _selectedIndex = 0;
  double _videoDuration;
  int _idSeed = 1;
  SourceType _sourceType;
  String? _localFilePath;
  String? _fileName;
  List<int>? _localDataBytes;

  bool isTesting = false;
  int testSegmentIndex = 0;
  int playsRemaining = 1;

  List<RoutineSegment> get segments => List.unmodifiable(_segments);
  int get selectedIndex => _selectedIndex;
  double get videoDuration => _videoDuration;
  RoutineSegment get active => _segments[_selectedIndex];
  RangeValues get activeRange => RangeValues(active.startSec, active.endSec);
  SourceType get sourceType => _sourceType;
  String? get localFilePath => _localFilePath;
  String? get fileName => _fileName;
  List<int>? get localDataBytes => _localDataBytes;

  static double _defaultEnd(double duration) {
    if (duration <= minGap) return duration;
    return 30.clamp(minGap, duration).toDouble();
  }

  void setVideoDuration(double duration) {
    if (duration <= 0) return;
    if ((duration - _videoDuration).abs() < 0.05) return;
    _videoDuration = duration;

    // Only expand the default first-segment end when there is a single section.
    // Multi-section routines must keep author-set windows (do not stretch A→full).
    if (_segments.length == 1 && (_segments[0].endSec - 30.0).abs() < 0.05) {
      _segments[0] = _segments[0].copyWith(endSec: duration);
    }

    for (var i = 0; i < _segments.length; i++) {
      _segments[i] = _clampSegment(_segments[i]);
    }
    notifyListeners();
  }

  /// Replace sections with a single default window (fresh start).
  void resetToDefaultSections({double? duration}) {
    if (duration != null && duration > 0) {
      _videoDuration = duration;
    }
    _segments
      ..clear()
      ..add(
        RoutineSegment(
          id: 'seg_0',
          startSec: 0,
          endSec: _defaultEnd(_videoDuration),
        ),
      );
    _selectedIndex = 0;
    _idSeed = 1;
    notifyListeners();
  }

  /// Apply cached practice sections (e.g. from `cached_videos`).
  void applyCachedSections(List<RoutineSegment> sections, {double? duration}) {
    if (duration != null && duration > 0) {
      _videoDuration = duration;
    }
    if (sections.isEmpty) {
      resetToDefaultSections(duration: duration);
      return;
    }
    _segments
      ..clear()
      ..addAll(
        sections.map(
          (s) => _clampSegment(
            RoutineSegment(
              id: s.id,
              startSec: s.startSec,
              endSec: s.endSec,
              speed: s.speed,
              loopCount: s.loopCount,
              delaySec: s.delaySec,
              isHighlight: s.isHighlight,
            ),
          ),
        ),
      );
    _selectedIndex = 0;
    _idSeed = _segments.length + 1;
    notifyListeners();
  }

  void setSourceType(
    SourceType type, {
    String? localFilePath,
    String? fileName,
    List<int>? localDataBytes,
  }) {
    _sourceType = type;
    _localFilePath = localFilePath;
    _fileName = fileName;
    _localDataBytes = localDataBytes;
    notifyListeners();
  }

  void selectSegment(int index) {
    if (index < 0 || index >= _segments.length) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void addSegment() {
    final last = _segments.last;
    final span = (last.endSec - last.startSec).clamp(minGap, _videoDuration);
    var start = last.endSec;
    if (start + minGap > _videoDuration) {
      start = (_videoDuration - span).clamp(0.0, _videoDuration);
    }
    var end = (start + span).clamp(0.0, _videoDuration);
    if (end - start < minGap) {
      end = _videoDuration;
      start = (end - minGap).clamp(0.0, _videoDuration);
    }
    _segments.add(
      RoutineSegment(
        id: 'seg_${_idSeed++}',
        startSec: start,
        endSec: end,
        speed: last.speed,
        loopCount: last.loopCount,
        delaySec: last.delaySec,
      ),
    );
    _selectedIndex = _segments.length - 1;
    notifyListeners();
  }

  void removeSegment(int index) {
    if (_segments.length <= 1) return;
    if (index < 0 || index >= _segments.length) return;
    _segments.removeAt(index);
    if (_selectedIndex >= _segments.length) {
      _selectedIndex = _segments.length - 1;
    }
    notifyListeners();
  }

  void updateActiveRange(RangeValues values) {
    updateRangeAt(_selectedIndex, values);
  }

  void updateRangeAt(int index, RangeValues values) {
    if (index < 0 || index >= _segments.length) return;
    var start = values.start.clamp(0.0, _videoDuration);
    var end = values.end.clamp(0.0, _videoDuration);
    if (end - start < minGap) {
      if ((start - _segments[index].startSec).abs() >= (end - _segments[index].endSec).abs()) {
        start = (end - minGap).clamp(0.0, _videoDuration);
      } else {
        end = (start + minGap).clamp(0.0, _videoDuration);
      }
    }
    _segments[index] = _segments[index].copyWith(startSec: start, endSec: end);
    notifyListeners();
  }

  bool applyManualTime({
    required int index,
    required bool isStart,
    required String text,
  }) {
    final parsed = parseTimeInput(text);
    if (parsed == null) {
      notifyListeners();
      return false;
    }
    final segment = _segments[index];
    if (isStart) {
      updateRangeAt(index, RangeValues(parsed, segment.endSec));
    } else {
      updateRangeAt(index, RangeValues(segment.startSec, parsed));
    }
    return true;
  }

  void setSpeed(int index, double speed) {
    _segments[index] = _segments[index].copyWith(speed: speed);
    notifyListeners();
  }

  void setLoopCount(int index, int loopCount) {
    _segments[index] = _segments[index].copyWith(loopCount: loopCount);
    notifyListeners();
  }

  void setDelaySec(int index, int delaySec) {
    _segments[index] = _segments[index].copyWith(delaySec: delaySec);
    notifyListeners();
  }

  /// Marks [index] as the routine chorus. Only one interval can be highlighted.
  void toggleHighlight(int index) {
    if (index < 0 || index >= _segments.length) return;
    final turningOn = !_segments[index].isHighlight;
    for (var i = 0; i < _segments.length; i++) {
      _segments[i] = _segments[i].copyWith(isHighlight: turningOn && i == index);
    }
    notifyListeners();
  }

  void beginTest({int startIndex = 0}) {
    isTesting = true;
    testSegmentIndex = startIndex.clamp(0, _segments.length - 1);
    final count = _segments[testSegmentIndex].loopCount;
    playsRemaining = count == kInfiniteLoop ? kInfiniteLoop : (count <= 0 ? 1 : count);
    notifyListeners();
  }

  void stopTest() {
    isTesting = false;
    testSegmentIndex = 0;
    playsRemaining = 1;
    notifyListeners();
  }

  RoutineSegment get testSegment => _segments[testSegmentIndex];

  LoopHitResult onLoopHit() {
    final segment = _segments[testSegmentIndex];
    final targetLoops = segment.loopCount == kInfiniteLoop
        ? kInfiniteLoop
        : (segment.loopCount <= 0 ? 1 : segment.loopCount);
    if (targetLoops == kInfiniteLoop) {
      return LoopHitResult.seekToStart;
    }
    // playsRemaining starts at targetLoops; each hit consumes one completed play.
    playsRemaining -= 1;
    if (playsRemaining > 0) {
      return LoopHitResult.seekToStart;
    }
    if (testSegmentIndex + 1 < _segments.length) {
      testSegmentIndex += 1;
      final next = _segments[testSegmentIndex].loopCount;
      playsRemaining = next == kInfiniteLoop ? kInfiniteLoop : (next <= 0 ? 1 : next);
      notifyListeners();
      return LoopHitResult.nextSegment;
    }
    return LoopHitResult.finished;
  }

  SavedRoutine toSavedRoutine({
    required String name,
    required String videoUrl,
    required String videoId,
    String? id,
    DateTime? createdAt,
    bool isFavorite = false,
    String authorId = 'me',
    String authorName = '나',
    String category = RoutineCategory.dance,
    bool isMirrored = false,
  }) {
    return SavedRoutine(
      id: id ?? 'rtn_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      videoUrl: videoUrl,
      videoId: videoId,
      segments: List<RoutineSegment>.unmodifiable(
        _segments.map(
          (s) => RoutineSegment(
            id: s.id,
            startSec: s.startSec,
            endSec: s.endSec,
            speed: s.speed,
            loopCount: s.loopCount,
            delaySec: s.delaySec,
            isHighlight: s.isHighlight,
          ),
        ),
      ),
      createdAt: createdAt ?? DateTime.now(),
      sourceType: _sourceType,
      localFilePath: _localFilePath,
      fileName: _fileName,
      localDataBytes: _localDataBytes,
      isFavorite: isFavorite,
      authorId: authorId,
      authorName: authorName,
      category: category,
      isMirrored: isMirrored,
    );
  }

  void loadFromRoutine(SavedRoutine routine) {
    _segments
      ..clear()
      ..addAll(
        routine.segments.map(
          (s) => RoutineSegment(
            id: s.id,
            startSec: s.startSec,
            endSec: s.endSec,
            speed: s.speed,
            loopCount: s.loopCount,
            delaySec: s.delaySec,
            isHighlight: s.isHighlight,
          ),
        ),
      );
    if (_segments.isEmpty) {
      _segments.add(
        RoutineSegment(
          id: 'seg_0',
          startSec: 0,
          endSec: _defaultEnd(_videoDuration),
        ),
      );
    }
    _selectedIndex = 0;
    _idSeed = _segments.length + 1;
    _sourceType = routine.sourceType;
    _localFilePath = routine.localFilePath;
    _fileName = routine.fileName;
    _localDataBytes = routine.localDataBytes;
    final maxEnd = _segments.map((s) => s.endSec).fold<double>(0, (a, b) => a > b ? a : b);
    if (maxEnd > _videoDuration) {
      _videoDuration = maxEnd;
    }
    notifyListeners();
  }

  RoutineSegment _clampSegment(RoutineSegment segment) {
    var start = segment.startSec.clamp(0.0, _videoDuration);
    var end = segment.endSec.clamp(0.0, _videoDuration);
    if (end - start < minGap) {
      end = (start + minGap).clamp(0.0, _videoDuration);
      if (end - start < minGap) {
        start = (end - minGap).clamp(0.0, _videoDuration);
      }
    }
    return segment.copyWith(startSec: start, endSec: end);
  }
}
