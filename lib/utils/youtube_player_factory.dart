import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'youtube_id.dart';

bool _youtubeInteropGuardInstalled = false;

/// Marks known youtube_player_iframe JS-interop TypeErrors as handled so they
/// cannot kill Dart microtasks (engine poll / stopRecording Completers).
void installYoutubeInteropErrorGuard() {
  if (_youtubeInteropGuardInstalled) return;
  _youtubeInteropGuardInstalled = true;
  final previous = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final msg = error.toString();
    final isYtInterop = msg.contains('youtube_player_iframe') ||
        msg.contains("type 'int' is not a subtype of type 'Map<String, dynamic>'") ||
        msg.contains("type 'double' is not a subtype of type 'Map<String, dynamic>'") ||
        (msg.contains('TypeError') && msg.contains('Map<String, dynamic>'));
    if (isYtInterop) {
      debugPrint('Ignored YouTube interop error to keep listener alive: $error');
      return true;
    }
    return previous?.call(error, stack) ?? false;
  };
}

/// Player params for embedded playback.
///
/// [YoutubePlayerParams.origin] is also used as the YT.Player `host`, which
/// becomes the iframe src (`{host}/embed/{videoId}`). It must stay on YouTube,
/// never the Flutter web origin (e.g. `http://localhost:xxxxx`).
///
/// On web, the package still injects `Uri.base.origin` into playerVars for the
/// IFrame API origin check.
///
/// Home keeps Studio in an [IndexedStack], so the same controller (and iframe
/// cache) survives tab switches. Use [loopiYoutubePlayer] (`keepAlive: true`)
/// for players that may go offstage inside a scrollable or tab view.
YoutubePlayerParams loopiYoutubeParams({bool showControls = true}) {
  return YoutubePlayerParams(
    mute: false,
    showControls: showControls,
    showFullscreenButton: true,
    loop: false,
    origin: 'https://www.youtube.com',
    playsInline: true,
    enableJavaScript: true,
    enableKeyboard: true,
  );
}

String? resolveYoutubeVideoId({String? videoId, String? videoUrl}) {
  return extractYoutubeVideoId(videoId ?? '') ?? extractYoutubeVideoId(videoUrl ?? '');
}

/// Canonical embed URL: `https://www.youtube.com/embed/{VIDEO_ID}`.
String youtubeEmbedUrl(String videoId, {double? startSeconds}) {
  final id = extractYoutubeVideoId(videoId);
  if (id == null) {
    throw ArgumentError.value(videoId, 'videoId', 'Not a valid YouTube id or URL');
  }
  final start = startSeconds;
  return Uri.https('www.youtube.com', '/embed/$id', {
    'enablejsapi': '1',
    if (start != null && start >= 0) 'start': '${start.round()}',
  }).toString();
}

Widget loopiYoutubePlayer({
  required YoutubePlayerController controller,
  double aspectRatio = 16 / 9,
}) {
  return YoutubePlayer(
    controller: controller,
    aspectRatio: aspectRatio,
    keepAlive: true,
  );
}

/// Creates a YouTube controller cued at [startSeconds] (section start), not 0.
///
/// `youtube_player_iframe` has no `YoutubePlayerParams.startAt` — the start
/// offset must be passed to [YoutubePlayerController.fromVideoId] /
/// `cueVideoById` as [startSeconds].
YoutubePlayerController createLoopiYoutubeController({
  required String videoId,
  bool autoPlay = false,
  double? startSeconds,
  double? endSeconds,
}) {
  installYoutubeInteropErrorGuard();
  final clean = extractYoutubeVideoId(videoId);
  if (clean == null) {
    throw ArgumentError.value(videoId, 'videoId', 'Not a valid YouTube id or URL');
  }
  final start = startSeconds != null && startSeconds.isFinite && startSeconds >= 0
      ? startSeconds
      : null;
  final end = endSeconds != null && endSeconds.isFinite && start != null && endSeconds > start
      ? endSeconds
      : null;
  return YoutubePlayerController.fromVideoId(
    videoId: clean,
    autoPlay: autoPlay,
    startSeconds: start,
    endSeconds: end,
    params: loopiYoutubeParams(),
  );
}

/// Guards iframe calls. On Flutter web the controller throws if the player
/// is not ready, was disposed, or the widget unmounted mid-await.
/// Also swallows JS-interop TypeErrors (e.g. int vs Map) so callers stay alive.
Future<T?> safeYoutubePlayerCall<T>(
  Future<T> Function() action, {
  bool Function()? isAlive,
}) async {
  if (isAlive != null && !isAlive()) return null;
  try {
    return await action();
  } catch (error, stack) {
    debugPrint('Ignored YouTube interop error to keep listener alive: $error');
    assert(() {
      debugPrint('$stack');
      return true;
    }());
    return null;
  }
}

StreamSubscription<T> listenYoutubeStream<T>(
  Stream<T> stream,
  void Function(T event) onData, {
  bool Function()? isAlive,
}) {
  return stream.listen(
    (event) {
      if (isAlive != null && !isAlive()) return;
      try {
        onData(event);
      } catch (error) {
        debugPrint('YouTube stream handler ignored: $error');
      }
    },
    onError: (Object error, StackTrace stack) {
      debugPrint('YouTube stream error ignored: $error');
    },
    cancelOnError: false,
  );
}

Future<T?> safeYoutubePlayerCallOn<T>(
  YoutubePlayerController? controller,
  Future<T> Function(YoutubePlayerController player) action, {
  bool Function()? isAlive,
}) {
  if (controller == null) return Future<T?>.value(null);
  return safeYoutubePlayerCall(() => action(controller), isAlive: isAlive);
}

/// Pauses and closes the iframe. Must be awaited (or [unawaited] with this
/// helper) because [YoutubePlayerController.close] is async and otherwise
/// surfaces as an unhandled exception on Flutter web.
Future<void> closeYoutubePlayerSafely(YoutubePlayerController? controller) async {
  if (controller == null) return;
  await safeYoutubePlayerCall(controller.pauseVideo);
  await safeYoutubePlayerCall(controller.close);
}
