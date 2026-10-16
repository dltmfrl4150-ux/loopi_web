import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/routine_play_gate.dart';

void main() {
  test('iframe play before the user starts the routine is held', () {
    final decision = decideIframePlaying(
      entryApplied: false,
      applyingSection: false,
      holdingForDelay: false,
    );
    expect(decision.action, IframePlayingAction.pauseUntilReady);
  });

  test('iframe play during the section delay is held', () {
    final decision = decideIframePlaying(
      entryApplied: true,
      applyingSection: false,
      holdingForDelay: true,
    );
    expect(decision.action, IframePlayingAction.pauseUntilReady);
  });

  test('play events from our own start do not start the procedure again', () {
    final decision = decideIframePlaying(
      entryApplied: false,
      applyingSection: true,
      holdingForDelay: false,
    );
    expect(decision.action, IframePlayingAction.ignore);
  });

  test('resume after the section is armed does not restart the countdown', () {
    final decision = decideIframePlaying(
      entryApplied: true,
      applyingSection: false,
      holdingForDelay: false,
    );
    expect(decision.action, IframePlayingAction.syncPlayback);
    expect(ignoreIframePause(applyingSection: true), isTrue);
    expect(ignoreIframePause(applyingSection: false), isFalse);
  });

  test('a zero delay does not add a YouTube state poll', () {
    expect(sectionPlaybackDelaySeconds(0), 0);
    expect(kYoutubeStatePollBudget, Duration.zero);
  });

  test('the play-button wait is the section delaySec', () {
    expect(sectionPlaybackDelaySeconds(0), 0);
    expect(sectionPlaybackDelaySeconds(3), 3);
    expect(sectionPlaybackDelaySeconds(10), 10);
    expect(sectionPlaybackDelaySeconds(-1), 0);
  });

  test('unsupported routine speeds snap to a YouTube rate', () {
    expect(nearestYoutubePlaybackRate(0.8), 0.75);
    expect(nearestYoutubePlaybackRate(0.9), 1.0);
    expect(nearestYoutubePlaybackRate(1.5), 1.5);
    expect(nearestYoutubePlaybackRate(0), 1.0);
  });
}
