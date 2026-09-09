/// Practice-goal tags stored on routines and showcase posts.
abstract final class RoutineCategory {
  static const all = 'all';
  static const dance = 'dance';
  static const language = 'language';
  static const other = 'other';

  static const values = <String>[dance, language, other];

  /// Missing or unknown values fall back to dance for backwards compatibility.
  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == language || value == '어학' || value == 'shadowing') {
      return language;
    }
    if (value == other || value == '기타' || value == 'etc') {
      return other;
    }
    return dance;
  }

  /// `null` means "All" — do not add a Firestore `where` clause.
  static String? queryValue(String? selected) {
    if (selected == null || selected.isEmpty || selected == all) return null;
    return normalize(selected);
  }

  static bool matches(String? itemCategory, String? selected) {
    final filter = queryValue(selected);
    if (filter == null) return true;
    return normalize(itemCategory) == filter;
  }

  static String labelKey(String id) {
    switch (id) {
      case all:
        return 'category.all';
      case language:
        return 'category.language';
      case other:
        return 'category.other';
      case dance:
      default:
        return 'category.dance';
    }
  }
}
