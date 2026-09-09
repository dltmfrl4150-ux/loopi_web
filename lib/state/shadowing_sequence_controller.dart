import '../models/routine_models.dart';

enum ShadowingPhase { idle, listening, speaking, done }

/// One listen or speak slot in the continuous shadowing timeline.
class ShadowingStep {
  const ShadowingStep({
    required this.segmentIndex,
    required this.loopIndex,
    required this.loopTotal,
    required this.phase,
    required this.duration,
    required this.segment,
  });

  final int segmentIndex;
  final int loopIndex;
  final int loopTotal;
  final ShadowingPhase phase;
  final Duration duration;
  final RoutineSegment segment;

  String get sectionLabel => sectionLabelForIndex(segmentIndex);

  String get phaseLabel => switch (phase) {
        ShadowingPhase.listening => 'Listening',
        ShadowingPhase.speaking => 'Speaking',
        ShadowingPhase.idle => 'Ready',
        ShadowingPhase.done => 'Done',
      };
}

/// Builds and drives the listen → speak sequence where each wait equals the
/// current interval's duration (end − start), scaled by playback speed.
class ShadowingSequenceController {
  ShadowingSequenceController(this.segments);

  final List<RoutineSegment> segments;

  List<ShadowingStep> buildSteps() {
    final steps = <ShadowingStep>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final loops = segment.loopCount == kInfiniteLoop ? 1 : segment.loopCount.clamp(1, 999);
      final duration = intervalDuration(segment);
      for (var loop = 0; loop < loops; loop++) {
        steps.add(
          ShadowingStep(
            segmentIndex: i,
            loopIndex: loop,
            loopTotal: loops,
            phase: ShadowingPhase.listening,
            duration: duration,
            segment: segment,
          ),
        );
        steps.add(
          ShadowingStep(
            segmentIndex: i,
            loopIndex: loop,
            loopTotal: loops,
            phase: ShadowingPhase.speaking,
            duration: duration,
            segment: segment,
          ),
        );
      }
    }
    return steps;
  }

  /// Media interval length; speaking wait uses the same value (not delaySec).
  static Duration intervalDuration(RoutineSegment segment) {
    final rawMs = ((segment.endSec - segment.startSec) * 1000).round();
    final speed = segment.speed <= 0 ? 1.0 : segment.speed;
    final ms = (rawMs / speed).round().clamp(100, 60 * 60 * 1000);
    return Duration(milliseconds: ms);
  }
}
