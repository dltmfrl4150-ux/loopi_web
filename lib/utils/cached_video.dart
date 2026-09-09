import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Network video that reuses the browser / OS HTTP cache.
///
/// Custom request headers are omitted on web so we do not trigger a CORS
/// preflight that would bypass the normal disk cache.
VideoPlayerController createCachedNetworkVideo(Uri uri) {
  final isEphemeral = uri.scheme == 'blob' || uri.scheme == 'data';
  if (kIsWeb || isEphemeral) {
    return VideoPlayerController.networkUrl(uri);
  }
  return VideoPlayerController.networkUrl(
    uri,
    httpHeaders: const {'Cache-Control': 'max-age=86400'},
  );
}
