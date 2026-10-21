/// Path segment used for community routine share links: `/r/{postId}`.
const String kCommunityRoutineSharePrefix = 'r';

/// Builds an absolute share URL for a community routine post.
///
/// [postId] is the Firestore `community_routines` document id, not the nested
/// library `SavedRoutine.id`.
String communityRoutineShareUrl(String postId, {Uri? base}) {
  final id = postId.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(postId, 'postId', 'Share URL requires a community post id');
  }
  return '${_shareOrigin(base ?? Uri.base)}/$kCommunityRoutineSharePrefix/${Uri.encodeComponent(id)}';
}

String _shareOrigin(Uri uri) {
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    try {
      return uri.origin;
    } catch (_) {
      // Fall through when origin cannot be read.
    }
  }
  if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }
  // Widget tests and some embeds use a non-http base; keep a stable public host.
  return 'https://loopi-app-6fdfe.web.app';
}

/// Path only, e.g. `/r/cpost_123`.
String communityRoutineSharePath(String postId) {
  final id = postId.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(postId, 'postId', 'Share path requires a community post id');
  }
  return '/$kCommunityRoutineSharePrefix/${Uri.encodeComponent(id)}';
}

/// Reads a community post id from a browser [uri] path (`/r/{id}`) or hash
/// (`#/r/{id}`). Returns null when the URI is not a routine share link.
String? parseCommunityRoutineShareId(Uri uri) {
  final fromPath = _idFromSegments(uri.pathSegments);
  if (fromPath != null) return fromPath;

  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) return null;
  final hashUri = fragment.startsWith('/')
      ? Uri.parse('https://share.invalid$fragment')
      : Uri.parse('https://share.invalid/$fragment');
  return _idFromSegments(hashUri.pathSegments);
}

String? _idFromSegments(List<String> rawSegments) {
  final segments = rawSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.length != 2) return null;
  if (segments[0] != kCommunityRoutineSharePrefix) return null;
  final id = Uri.decodeComponent(segments[1]).trim();
  return id.isEmpty ? null : id;
}
