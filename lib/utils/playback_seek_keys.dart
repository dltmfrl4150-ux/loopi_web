import 'package:flutter/services.dart';

/// Keyboard result for a 5-second routine seek.
///
/// [delta] is `-5` or `5` for a real key press. Key repeat is [handled] so the
/// page does not scroll, but [delta] stays null so holding the key does not
/// seek again.
class PlaybackSeekKeyResult {
  const PlaybackSeekKeyResult({required this.handled, this.delta});

  final bool handled;
  final double? delta;
}

PlaybackSeekKeyResult playbackSeekKeyResult({
  required KeyEvent event,
  required bool routeIsCurrent,
  required bool textInputFocused,
}) {
  if (!routeIsCurrent || textInputFocused) {
    return const PlaybackSeekKeyResult(handled: false);
  }
  final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
  final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;
  if (!isLeft && !isRight) {
    return const PlaybackSeekKeyResult(handled: false);
  }
  if (event is KeyRepeatEvent) {
    return const PlaybackSeekKeyResult(handled: true);
  }
  if (event is! KeyDownEvent) {
    return const PlaybackSeekKeyResult(handled: false);
  }
  return PlaybackSeekKeyResult(handled: true, delta: isLeft ? -5 : 5);
}
