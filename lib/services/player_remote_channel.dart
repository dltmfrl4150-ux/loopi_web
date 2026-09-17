/// Optional MethodChannel bridge for Wear / native remote commands.
///
/// Safe on all platforms: when the channel is unavailable (web, missing
/// native plugin), [startListening] is a no-op.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_remote_control.dart';

const String kPlayerRemoteChannelName = 'com.loopi.player_remote';

/// Listens for `player_remote` method calls and forwards them to
/// [PlayerRemoteControl]. Does not require a Wear SDK dependency yet —
/// the Android companion can invoke the same channel name later.
class PlayerRemoteChannelBridge {
  PlayerRemoteChannelBridge._();

  static const MethodChannel _channel = MethodChannel(kPlayerRemoteChannelName);
  static bool _listening = false;

  static void startListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') {
        debugPrint('[LOOPI] PlayerRemoteChannel unknown method ${call.method}');
        return false;
      }
      final raw = call.arguments is String
          ? call.arguments as String
          : call.arguments?.toString();
      final command = PlayerRemoteControl.parseCommand(raw);
      if (command == null) {
        debugPrint('[LOOPI] PlayerRemoteChannel bad payload: $raw');
        return false;
      }
      return PlayerRemoteControl.instance.dispatch(command);
    });
    debugPrint('[LOOPI] PlayerRemoteChannel listening on $kPlayerRemoteChannelName');
  }
}
