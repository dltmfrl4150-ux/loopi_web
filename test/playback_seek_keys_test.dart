import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/playback_seek_keys.dart';

KeyEvent _down(LogicalKeyboardKey key) {
  return KeyDownEvent(
    physicalKey: key == LogicalKeyboardKey.arrowLeft
        ? PhysicalKeyboardKey.arrowLeft
        : PhysicalKeyboardKey.arrowRight,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

KeyEvent _repeat(LogicalKeyboardKey key) {
  return KeyRepeatEvent(
    physicalKey: key == LogicalKeyboardKey.arrowLeft
        ? PhysicalKeyboardKey.arrowLeft
        : PhysicalKeyboardKey.arrowRight,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

void main() {
  test('left arrow seeks back 5 seconds once', () {
    final result = playbackSeekKeyResult(
      event: _down(LogicalKeyboardKey.arrowLeft),
      routeIsCurrent: true,
      textInputFocused: false,
    );
    expect(result.handled, isTrue);
    expect(result.delta, -5);
  });

  test('right arrow seeks forward 5 seconds once', () {
    final result = playbackSeekKeyResult(
      event: _down(LogicalKeyboardKey.arrowRight),
      routeIsCurrent: true,
      textInputFocused: false,
    );
    expect(result.handled, isTrue);
    expect(result.delta, 5);
  });

  test('holding an arrow does not seek again', () {
    final result = playbackSeekKeyResult(
      event: _repeat(LogicalKeyboardKey.arrowRight),
      routeIsCurrent: true,
      textInputFocused: false,
    );
    expect(result.handled, isTrue);
    expect(result.delta, isNull);
  });

  test('arrow keys are ignored while typing or off the player route', () {
    final typing = playbackSeekKeyResult(
      event: _down(LogicalKeyboardKey.arrowLeft),
      routeIsCurrent: true,
      textInputFocused: true,
    );
    final covered = playbackSeekKeyResult(
      event: _down(LogicalKeyboardKey.arrowRight),
      routeIsCurrent: false,
      textInputFocused: false,
    );
    expect(typing.handled, isFalse);
    expect(typing.delta, isNull);
    expect(covered.handled, isFalse);
    expect(covered.delta, isNull);
  });

  test('other keys are not captured', () {
    final result = playbackSeekKeyResult(
      event: const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      ),
      routeIsCurrent: true,
      textInputFocused: false,
    );
    expect(result.handled, isFalse);
    expect(result.delta, isNull);
  });
}
