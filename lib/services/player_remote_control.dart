import 'dart:async';

import 'package:flutter/foundation.dart';

/// Commands that a Wear OS companion (or any external channel) can send.
///
/// Keep this enum transport-agnostic: Wearable Data Layer, MethodChannel,
/// or an in-app debug panel should all map into these values.
enum PlayerRemoteCommand {
  play,
  pause,
  togglePlayPause,
  /// Seek back to the start of the current point section and resume.
  reloopSection,
  nextSection,
  previousSection,
}

/// Implemented by the active routine player (e.g. [PracticeModeScreenState]).
abstract class PlayerRemoteHandler {
  Future<void> handleRemoteCommand(PlayerRemoteCommand command);
}

/// Process-wide bus that routes remote control events to the active player.
///
/// Usage:
/// - Player screens call [attach] in `initState` and [detach] in `dispose`.
/// - Wear Data Layer / MethodChannel adapters call [dispatch].
///
/// Only one handler is active at a time (last attach wins). This matches the
/// product model of a single foreground routine player.
class PlayerRemoteControl {
  PlayerRemoteControl._();

  static final PlayerRemoteControl instance = PlayerRemoteControl._();

  PlayerRemoteHandler? _handler;
  final _commandController = StreamController<PlayerRemoteCommand>.broadcast();

  /// Optional listen-only stream for analytics / debug mirrors.
  Stream<PlayerRemoteCommand> get commands => _commandController.stream;

  bool get hasActiveHandler => _handler != null;

  void attach(PlayerRemoteHandler handler) {
    _handler = handler;
    debugPrint('[LOOPI] PlayerRemoteControl attached ${handler.runtimeType}');
  }

  void detach(PlayerRemoteHandler handler) {
    if (identical(_handler, handler)) {
      _handler = null;
      debugPrint('[LOOPI] PlayerRemoteControl detached');
    }
  }

  /// Entry point for Wearable Data Layer / background channel adapters.
  Future<bool> dispatch(PlayerRemoteCommand command) async {
    final handler = _handler;
    if (!_commandController.isClosed) {
      _commandController.add(command);
    }
    if (handler == null) {
      debugPrint('[LOOPI] PlayerRemoteControl drop $command (no handler)');
      return false;
    }
    try {
      await handler.handleRemoteCommand(command);
      return true;
    } catch (error, stack) {
      debugPrint('[LOOPI] PlayerRemoteControl $command failed: $error\n$stack');
      return false;
    }
  }

  /// Maps string payloads from Wear / MethodChannel into [PlayerRemoteCommand].
  static PlayerRemoteCommand? parseCommand(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'play':
        return PlayerRemoteCommand.play;
      case 'pause':
        return PlayerRemoteCommand.pause;
      case 'toggle':
      case 'toggle_play_pause':
      case 'play_pause':
        return PlayerRemoteCommand.togglePlayPause;
      case 'reloop':
      case 'reloop_section':
      case 'restart_section':
        return PlayerRemoteCommand.reloopSection;
      case 'next':
      case 'next_section':
        return PlayerRemoteCommand.nextSection;
      case 'prev':
      case 'previous':
      case 'previous_section':
        return PlayerRemoteCommand.previousSection;
      default:
        return null;
    }
  }
}
