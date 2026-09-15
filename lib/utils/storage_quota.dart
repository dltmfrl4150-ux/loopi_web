/// Thrown when local SharedPreferences / browser storage cannot accept more data.
class StorageQuotaExceededException implements Exception {
  const StorageQuotaExceededException([this.cause]);

  final Object? cause;

  static bool matches(Object error) {
    if (error is StorageQuotaExceededException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('quotaexceeded') ||
        text.contains('quota_exceeded') ||
        text.contains('quota exceeded') ||
        text.contains('storagequota') ||
        text.contains('ns_error_dom_quota') ||
        text.contains('the quota has been exceeded');
  }

  @override
  String toString() =>
      'StorageQuotaExceededException(${cause ?? 'local storage full'})';
}

/// Friendly Korean nudge shown when local storage is full.
const String kStorageQuotaNudgeMessage =
    '저장 공간이 꽉 찼어요! 내 댄스 보관함에서 예전 연습 기록을 조금 정리해 볼까요?';