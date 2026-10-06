/// Practice-goal tags stored on routines and showcase posts.
abstract final class RoutineCategory {
  static const all = 'all';
  static const kpop = 'kpop';
  static const choreo = 'choreo';
  static const hiphop = 'hiphop';
  static const zumba = 'zumba';
  static const other = 'other';

  /// Legacy stored values — [normalize] maps these onto the current set.
  static const dance = 'dance';
  static const language = 'language';

  /// Selectable genre tags (excludes [all]).
  static const values = <String>[kpop, choreo, hiphop, zumba, other];

  /// Filter bar order including "All".
  static const filterValues = <String>[all, kpop, choreo, hiphop, zumba, other];

  /// Missing or unknown values fall back to K-pop for backwards compatibility.
  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return kpop;

    if (value == kpop ||
        value == dance ||
        value == '댄스' ||
        value == 'k-pop' ||
        value == 'k pop') {
      return kpop;
    }
    if (value == choreo || value == '코레오' || value == 'choreography') {
      return choreo;
    }
    if (value == hiphop ||
        value == '힙합' ||
        value == 'hip-hop' ||
        value == 'hip hop') {
      return hiphop;
    }
    if (value == zumba || value == '줌바') {
      return zumba;
    }
    if (value == other || value == '기타' || value == 'etc') {
      return other;
    }
    // Removed "어학" / language — fold into Other.
    if (value == language || value == '어학' || value == 'shadowing') {
      return other;
    }
    return kpop;
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

  /// Genres that may still exist under legacy stored ids (`dance`, `language`).
  /// Prefer client-side [matches] instead of a strict Firestore equality filter.
  static bool hasLegacyAliases(String normalized) {
    return normalized == kpop || normalized == other;
  }

  static String labelKey(String id) {
    switch (id) {
      case all:
        return 'category.all';
      case choreo:
        return 'category.choreo';
      case hiphop:
        return 'category.hiphop';
      case zumba:
        return 'category.zumba';
      case other:
        return 'category.other';
      case kpop:
      case dance:
      default:
        return 'category.kpop';
    }
  }
}
