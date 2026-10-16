import 'package:flutter/foundation.dart';

/// Rates the YouTube IFrame API can actually apply.
const List<double> kYoutubePlaybackRates = <double>[
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

/// Snaps [speed] to the closest rate YouTube will accept.
double nearestYoutubePlaybackRate(double speed) {
  final target = speed <= 0 || !speed.isFinite ? 1.0 : speed;
  var best = kYoutubePlaybackRates.first;
  var bestDiff = (best - target).abs();
  for (final rate in kYoutubePlaybackRates) {
    final diff = (rate - target).abs();
    if (diff < bestDiff) {
      best = rate;
      bestDiff = diff;
    }
  }
  return best;
}

/// What to do when the iframe reports [PlayerState.playing].
enum IframePlayingAction {
  /// The user has not finished the section delay, or has not started the routine.
  /// Stop native play so entry cannot start on its own.
  pauseUntilReady,

  /// Our own seek/play command is still running. Do not start another one.
  ignore,

  /// Routine is already running or paused-and-resumed. Sync UI and rate only.
  syncPlayback,
}

/// The play button must not poll YouTube [PlayerState] before seek/play.
///
/// `unknown` is the controller's default. The old loop treated it as
/// not-ready, waited 8 seconds, then issued play anyway.
const Duration kYoutubeStatePollBudget = Duration.zero;

/// Seconds to count down after the user presses play.
///
/// This is the section's saved `delaySec` (0, 1, 2, 3, 5, 10, 30, 60).
/// A negative value is treated as no wait.
int sectionPlaybackDelaySeconds(int delaySec) => delaySec < 0 ? 0 : delaySec;

@immutable
class IframePlayingDecision {
  const IframePlayingDecision(this.action);

  final IframePlayingAction action;
}

/// Decides how a YouTube "playing" event maps onto the routine.
///
/// Opening the screen does not start playback. Until [entryApplied] is true,
/// or while [holdingForDelay] is true, a playing event is paused.
/// Events while [applyingSection] are ignored so our own `playVideo()` does
/// not start a second run.
IframePlayingDecision decideIframePlaying({
  required bool entryApplied,
  required bool applyingSection,
  required bool holdingForDelay,
}) {
  if (applyingSection) {
    return const IframePlayingDecision(IframePlayingAction.ignore);
  }
  if (holdingForDelay || !entryApplied) {
    return const IframePlayingDecision(IframePlayingAction.pauseUntilReady);
  }
  return const IframePlayingDecision(IframePlayingAction.syncPlayback);
}

/// A paused event that arrives while we are seeking or calling playVideo
/// must not flip the Loopi button back to "play".
bool ignoreIframePause({required bool applyingSection}) => applyingSection;
