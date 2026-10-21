import 'routine_share_location.dart';
import 'routine_share_url.dart';

/// Survives AuthGate / HomeDashboard remounts during login.
///
/// Capture once at startup from the real browser location. Do not clear on a
/// failed lookup — only clear when the user leaves the shared routine or
/// dismisses the error.
class RoutineSharePending {
  RoutineSharePending._();

  static String? _postId;

  static String? get postId => _postId;

  static void capture(String? id) {
    final trimmed = id?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    _postId ??= trimmed;
  }

  static void captureFromBrowser() {
    capture(readCommunityRoutineShareIdFromBrowser());
  }

  /// Prefer an already captured id, then the live browser URL, then [Uri.base].
  static String? resolve() {
    if (_postId != null && _postId!.isNotEmpty) return _postId;
    capture(readCommunityRoutineShareIdFromBrowser());
    if (_postId != null) return _postId;
    capture(parseCommunityRoutineShareId(Uri.base));
    return _postId;
  }

  static void clear() {
    _postId = null;
  }
}
