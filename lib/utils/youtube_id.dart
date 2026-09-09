final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

bool _isYoutubeVideoId(String value) => _youtubeIdPattern.hasMatch(value);

/// Extracts an 11-character YouTube video id from a URL or raw id.
/// Query parameters (`?si=`, `&t=`) are always stripped.
String? extractYoutubeVideoId(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final withoutQuery = value.split('?').first.split('&').first.trim();
  if (_isYoutubeVideoId(withoutQuery)) {
    return withoutQuery;
  }

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
    final id = uri.pathSegments.first;
    return _isYoutubeVideoId(id) ? id : null;
  }

  final queryId = uri.queryParameters['v'];
  if (queryId != null && _isYoutubeVideoId(queryId)) {
    return queryId;
  }

  for (final marker in const ['embed', 'shorts', 'live']) {
    final markerIndex = uri.pathSegments.indexOf(marker);
    if (markerIndex != -1 && markerIndex + 1 < uri.pathSegments.length) {
      final id = uri.pathSegments[markerIndex + 1];
      if (_isYoutubeVideoId(id)) return id;
    }
  }

  return null;
}

/// Public YouTube poster image for a video id or watch URL.
String? youtubeThumbnailUrl(String? videoIdOrUrl) {
  final id = extractYoutubeVideoId(videoIdOrUrl ?? '');
  if (id == null) return null;
  return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}
