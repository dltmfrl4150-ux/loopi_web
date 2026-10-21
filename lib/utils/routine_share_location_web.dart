import 'package:web/web.dart' as web;

import 'routine_share_url.dart';

void setCommunityRoutineSharePath(String postId) {
  web.window.history.replaceState(null, '', communityRoutineSharePath(postId));
}

void clearCommunityRoutineSharePath() {
  web.window.history.replaceState(null, '', '/');
}

/// Reads the live address bar. [Uri.base] on Flutter web can omit `/r/...`.
String? readCommunityRoutineShareIdFromBrowser() {
  final href = web.window.location.href;
  return parseCommunityRoutineShareId(Uri.parse(href));
}
