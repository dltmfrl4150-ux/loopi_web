import 'routine_share_url.dart';

void setCommunityRoutineSharePath(String postId) {}

void clearCommunityRoutineSharePath() {}

String? readCommunityRoutineShareIdFromBrowser() {
  return parseCommunityRoutineShareId(Uri.base);
}
