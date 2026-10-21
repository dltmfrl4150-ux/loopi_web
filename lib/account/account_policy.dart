/// Account deletion and age-gate decisions that do not touch Firebase.
///
/// Guardian identity verification is not represented here. A value of
/// [ageDeclarationAdult] is a self-declaration, not proof of age.
class PrivateAccountState {
  const PrivateAccountState({
    this.exists = false,
    this.status,
    this.ageDeclaration,
    this.purgeAfter,
    this.purgeStarted = false,
    this.readFailed = false,
  });

  final bool exists;
  final String? status;
  final String? ageDeclaration;
  final DateTime? purgeAfter;
  final bool purgeStarted;
  final bool readFailed;

  bool get isPurgeStarted =>
      purgeStarted || status == AccountPolicy.purgeStarted;

  bool get isPendingDeletion =>
      status == AccountPolicy.pendingDeletion && !isPurgeStarted;

  bool get hasAdultDeclaration =>
      ageDeclaration == AccountPolicy.ageDeclarationAdult;

  /// Home access after auth. Age self-declaration is not a login gate.
  bool get allowsAppUse =>
      !readFailed && !isPendingDeletion && !isPurgeStarted;
}

/// Login no longer shows the age self-declaration screen for guests or members.
/// [ageDeclaration] may still exist on private/account for other account flows.
bool requiresAgeDeclaration({
  required bool isAnonymous,
  required bool hasAdultDeclaration,
}) {
  return false;
}

enum DeletionRequestDecision {
  create,
  alreadyPending,
  purgeStarted,
  notEligible,
}

enum RestoreDecision { allow, purgeStarted, notPending }

class AccountPolicy {
  AccountPolicy._();

  static const String active = 'active';
  static const String pendingDeletion = 'pending_deletion';
  static const String purgeStarted = 'purge_started';
  static const String ageDeclarationAdult = 'at_least_14';
  static const String withdrawnAuthorLabel = '탈퇴한 회원';
  static const Duration purgeDelay = Duration(days: 30);

  /// Server rules accept a client [purgeAfter] only inside this skew of
  /// request time plus [purgeDelay]. The value is not a client-chosen deadline.
  static const Duration purgeAfterSkew = Duration(minutes: 5);

  static DeletionRequestDecision deletionRequest(PrivateAccountState account) {
    if (account.isPurgeStarted) return DeletionRequestDecision.purgeStarted;
    if (account.isPendingDeletion) return DeletionRequestDecision.alreadyPending;
    if (!account.hasAdultDeclaration) return DeletionRequestDecision.notEligible;
    if (account.status != null && account.status != active) {
      return DeletionRequestDecision.notEligible;
    }
    return DeletionRequestDecision.create;
  }

  /// Restore stays available until a server job records that purge has started.
  /// The 30-day check belongs to that job. A client clock must not be the lock.
  static RestoreDecision restore(PrivateAccountState account) {
    if (account.isPurgeStarted) return RestoreDecision.purgeStarted;
    if (!account.isPendingDeletion) return RestoreDecision.notPending;
    return RestoreDecision.allow;
  }

  /// True only when a server clock is at or past [PrivateAccountState.purgeAfter].
  static bool isPurgeDue(PrivateAccountState account, DateTime serverNow) {
    if (account.status != pendingDeletion || account.isPurgeStarted) return false;
    final due = account.purgeAfter;
    if (due == null) return false;
    return !serverNow.isBefore(due);
  }

  static Map<String, Object?> anonymizedAuthorFields(String withdrawnId) {
    return {
      'authorId': withdrawnId,
      'authorName': withdrawnAuthorLabel,
      'authorNickname': withdrawnAuthorLabel,
      'authorPhotoUrl': null,
      'routine.authorId': withdrawnId,
      'routine.authorName': withdrawnAuthorLabel,
    };
  }
}

/// Storage object path for a showcase file owned by [ownerUid], or null.
String? ownedShowcaseStoragePath({
  required String ownerUid,
  String? storagePath,
  String? downloadUrl,
}) {
  if (ownerUid.isEmpty) return null;
  final direct = _cleanOwnedPath(storagePath, ownerUid);
  if (direct != null) return direct;
  return _cleanOwnedPath(_pathFromDownloadUrl(downloadUrl), ownerUid);
}

String? _cleanOwnedPath(String? raw, String ownerUid) {
  if (raw == null) return null;
  final path = raw.trim();
  if (path.isEmpty || path.contains('..') || path.contains('://')) return null;
  final prefix = 'showcase/$ownerUid/';
  if (!path.startsWith(prefix)) return null;
  if (path.length <= prefix.length) return null;
  return path;
}

String? _pathFromDownloadUrl(String? downloadUrl) {
  if (downloadUrl == null) return null;
  final value = downloadUrl.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final marker = segments.indexOf('o');
  if (marker < 0 || marker + 1 >= segments.length) return null;
  return Uri.decodeComponent(segments[marker + 1]);
}
