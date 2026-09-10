import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/cached_video.dart';
import '../models/community_models.dart';
import '../models/routine_category.dart';
import '../models/routine_models.dart';
import '../utils/youtube_id.dart';
import 'auth_service.dart';
import 'storage_service.dart';

class ShowcasePage {
  const ShowcasePage({
    required this.items,
    required this.hasMore,
    this.newestCursor,
  });

  final List<CommunityShowcaseItem> items;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? newestCursor;
}

class RoutinesPage {
  const RoutinesPage({
    required this.posts,
    required this.hasMore,
    this.cursor,
  });

  final List<CommunityRoutinePost> posts;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
}

/// Latest home-screen notice from the `announcements` collection.
class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    this.link,
  });

  final String id;
  final String title;
  final String? link;

  static String? _pickLocalized(Map<String, dynamic> data, String locale, List<String> keys) {
    final lang = locale.toLowerCase().startsWith('ko') ? 'ko' : 'en';
    for (final key in keys) {
      final map = data[key];
      if (map is Map) {
        final localized = map[lang] ?? map['en'];
        if (localized != null && '$localized'.trim().isNotEmpty) {
          return '$localized'.trim();
        }
      }
      final langFlat = data['${key}_$lang'] ?? (lang == 'ko' ? data['${key}Ko'] : data['${key}En']);
      if (langFlat != null && '$langFlat'.trim().isNotEmpty) {
        return '$langFlat'.trim();
      }
    }
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  factory AppAnnouncement.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    String locale = 'en',
  }) {
    final title = _pickLocalized(data, locale, const ['title', 'content']) ?? '';
    final rawLink = data['link'] ?? data['url'];
    final link = rawLink == null ? null : '$rawLink'.trim();
    return AppAnnouncement(
      id: id,
      title: title,
      link: (link == null || link.isEmpty) ? null : link,
    );
  }
}

class _AuthorSnapshot {
  const _AuthorSnapshot({
    required this.docs,
    this.scannedFallback = false,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool scannedFallback;
}

class DatabaseService {
  DatabaseService({this._firestore});

  final FirebaseFirestore? _firestore;

  static const int showcaseTopLikedCount = 12;
  static const int defaultPageSize = 12;
  static const int authorFeedPageSize = 50;
  static const int routinesFetchWindow = 12;
  static const int _authorRewritePageSize = 200;
  static const int _authorRewriteMaxDocs = 2000;
  static const int _batchChunkSize = 400;
  static const Duration _queryTimeout = Duration(seconds: 8);

  /// In-memory nickname cache — never N+1 profile reads for feed cards.
  final Map<String, String> userProfileCache = {};

  /// Local fallback when Firebase is unavailable (dev / guest without init).
  final List<CommunityShowcaseItem> _localShowcase = [];
  final List<CommunityRoutinePost> _localRoutines = [];
  final Map<String, List<DateTime>> _localFavoriteEvents = {};

  FirebaseFirestore? get _db {
    if (!FirebaseBootstrap.initialized) return null;
    return _firestore ?? FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>>? get _announcementsCol {
    final db = _db;
    if (db == null) return null;
    return db.collection('announcements');
  }

  /// Newest announcement for the Home banner (`timestamp` desc, limit 1).
  Future<AppAnnouncement?> fetchLatestAnnouncement({String locale = 'en'}) async {
    final col = _announcementsCol;
    if (col == null) return null;
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await col.orderBy('timestamp', descending: true).limit(1).get().timeout(_queryTimeout);
      } catch (error) {
        _logQueryError('announcements orderBy(timestamp)', error);
        // Fallback: createdAt, then unordered + in-memory pick.
        try {
          snap = await col.orderBy('createdAt', descending: true).limit(1).get().timeout(_queryTimeout);
        } catch (_) {
          snap = await col.limit(20).get().timeout(_queryTimeout);
        }
      }
      if (snap.docs.isEmpty) return null;
      final docs = [...snap.docs];
      docs.sort((a, b) {
        DateTime? parse(DocumentSnapshot<Map<String, dynamic>> doc) {
          final data = doc.data();
          if (data == null) return null;
          final raw = data['timestamp'] ?? data['createdAt'] ?? data['updatedAt'];
          if (raw is Timestamp) return raw.toDate();
          if (raw is DateTime) return raw;
          if (raw is String) return DateTime.tryParse(raw);
          return null;
        }
        final aAt = parse(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = parse(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });
      final doc = docs.first;
      final data = doc.data();
      final announcement = AppAnnouncement.fromFirestore(doc.id, data, locale: locale);
      if (announcement.title.isEmpty) return null;
      return announcement;
    } catch (error, stack) {
      _logQueryError('fetchLatestAnnouncement', error, stack);
      return null;
    }
  }

  /// Local fallback when Firestore is unavailable.
  final Map<String, CachedVideo> _localCachedVideos = {};

  CollectionReference<Map<String, dynamic>>? get _cachedVideosCol {
    final db = _db;
    if (db == null) return null;
    return db.collection('cached_videos');
  }

  /// Returns cached YouTube metadata/sections for [videoId], or null if missing.
  /// Prefer this over any YouTube Data API call when the document exists.
  Future<CachedVideo?> getCachedVideo(String videoId) async {
    final id = extractYoutubeVideoId(videoId) ?? videoId.trim();
    if (id.isEmpty) return null;

    final col = _cachedVideosCol;
    if (col == null) {
      return _localCachedVideos[id];
    }
    try {
      final snap = await col.doc(id).get().timeout(_queryTimeout);
      if (!snap.exists || snap.data() == null) {
        return _localCachedVideos[id];
      }
      final cached = CachedVideo.fromFirestore(id, snap.data()!);
      _localCachedVideos[id] = cached;
      return cached;
    } catch (error, stack) {
      _logQueryError('getCachedVideo($id)', error, stack);
      return _localCachedVideos[id];
    }
  }

  /// Upserts `cached_videos/{videoId}` with title, duration, thumbnail, sections.
  Future<void> upsertCachedVideo({
    required String videoId,
    required String title,
    required double duration,
    required String thumbnailUrl,
    required List<RoutineSegment> sections,
  }) async {
    final id = extractYoutubeVideoId(videoId) ?? videoId.trim();
    if (id.isEmpty) return;

    final cached = CachedVideo(
      videoId: id,
      title: title.trim().isEmpty ? id : title.trim(),
      duration: duration > 0 ? duration : 0,
      thumbnailUrl: thumbnailUrl.trim().isNotEmpty
          ? thumbnailUrl.trim()
          : (youtubeThumbnailUrl(id) ?? ''),
      sections: List<RoutineSegment>.from(sections),
      updatedAt: DateTime.now(),
    );
    _localCachedVideos[id] = cached;

    final col = _cachedVideosCol;
    if (col == null) return;
    try {
      await col.doc(id).set(cached.toFirestore(), SetOptions(merge: true)).timeout(_queryTimeout);
      debugPrint('[LOOPI] cached_videos upserted $id sections=${sections.length}');
    } catch (error, stack) {
      _logQueryError('upsertCachedVideo($id)', error, stack);
    }
  }

  DocumentReference<Map<String, dynamic>>? _userProfileRef(String uid) {
    final db = _db;
    if (db == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>>? _libraryRef(String uid) {
    final db = _db;
    if (db == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid).collection('data').doc('library');
  }

  CollectionReference<Map<String, dynamic>>? get _showcaseCol {
    final db = _db;
    if (db == null) return null;
    return db.collection('community_showcase');
  }

  void _logQueryError(String name, Object error, [StackTrace? stack]) {
    _logProfileSync('$name error', error, stack);
  }

  void _logProfileSync(String message, [Object? error, StackTrace? stack]) {
    final text = error == null ? message : '$message | $error';
    debugPrint('[LOOPI] $text');
    developer.log(
      text,
      name: 'DatabaseService',
      error: error,
      stackTrace: stack,
    );
    if (error == null) return;
    final errorText = '$error';
    if (errorText.contains('permission-denied') || errorText.contains('PERMISSION_DENIED')) {
      debugPrint('[LOOPI] Firestore permission-denied. Check firestore.rules for community_routines / community_showcase author updates.');
    }
    final match = RegExp(r'https://console\.firebase\.google\.com[^\s]+').firstMatch(errorText);
    if (match != null) {
      debugPrint('[LOOPI] Create the required Firestore composite index: ${match.group(0)}');
    }
  }

  String _docAuthorId(Map<String, dynamic> data) {
    final top = data['authorId']?.toString().trim() ?? '';
    if (top.isNotEmpty && top != 'me') return top;
    final routine = data['routine'];
    if (routine is Map) {
      final nested = routine['authorId']?.toString().trim() ?? '';
      if (nested.isNotEmpty && nested != 'me') return nested;
    }
    return top;
  }

  Map<String, dynamic> _authorProfilePatch({
    String? name,
    String? photo,
    required bool includeNestedRoutine,
    Map<String, dynamic>? existing,
    String? uid,
  }) {
    final patch = <String, dynamic>{};
    if (name != null && name.isNotEmpty) {
      patch['authorName'] = name;
      patch['authorNickname'] = name;
      if (includeNestedRoutine) {
        patch['routine.authorName'] = name;
      }
    }
    if (photo != null && photo.isNotEmpty) {
      patch['authorPhotoUrl'] = photo;
    }
    if (uid != null && uid.isNotEmpty && existing != null) {
      final current = existing['authorId']?.toString().trim() ?? '';
      if (current != uid) {
        patch['authorId'] = uid;
        if (includeNestedRoutine) {
          patch['routine.authorId'] = uid;
        }
      }
    }
    return patch;
  }

  Query<Map<String, dynamic>> _applyCategoryFilter(
    Query<Map<String, dynamic>> query,
    String? category,
  ) {
    final value = RoutineCategory.queryValue(category);
    if (value == null) return query;
    return query.where('category', isEqualTo: value);
  }

  CollectionReference<Map<String, dynamic>>? get _routinesCol {
    final db = _db;
    if (db == null) return null;
    return db.collection('community_routines');
  }

  /// Resolves a display nickname without network fan-out.
  /// Prefers the denormalized [fallback] (authorName on the post), then cache.
  String authorNickname({
    required String authorId,
    required String fallback,
  }) {
    final cached = userProfileCache[authorId];
    if (cached != null && cached.isNotEmpty) return cached;
    final name = fallback.trim().isEmpty ? 'Anonymous' : fallback.trim();
    if (authorId.isNotEmpty) userProfileCache[authorId] = name;
    return name;
  }

  Future<String> ensureUserProfile({
    required String uid,
    String? email,
    String? preferredNickname,
    String? authDisplayName,
  }) async {
    final fallback = (preferredNickname != null && preferredNickname.trim().isNotEmpty)
        ? preferredNickname.trim()
        : (authDisplayName != null && authDisplayName.trim().isNotEmpty)
            ? authDisplayName.trim()
            : '루피 유저';
    final ref = _userProfileRef(uid);
    if (ref == null) return fallback;
    try {
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data() ?? {};
        final existing = (data['nickname'] as String?)?.trim();
        if (existing != null && existing.isNotEmpty) {
          userProfileCache[uid] = existing;
          final photo = (data['photoUrl'] as String?)?.trim();
          if (photo != null && photo.isNotEmpty) userPhotoCache[uid] = photo;
          return existing;
        }
        await ref.set({
          'nickname': fallback,
          if (email != null) 'email': email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        userProfileCache[uid] = fallback;
        return fallback;
      }
      await ref.set({
        'nickname': fallback,
        'email': email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      userProfileCache[uid] = fallback;
      return fallback;
    } catch (error) {
      debugPrint('ensureUserProfile error: $error');
      return fallback;
    }
  }

  Future<String?> fetchUserNickname(String uid) async {
    final ref = _userProfileRef(uid);
    if (ref == null) return null;
    try {
      final snap = await ref.get();
      final nickname = (snap.data()?['nickname'] as String?)?.trim();
      if (nickname == null || nickname.isEmpty) return null;
      return nickname;
    } catch (error) {
      debugPrint('fetchUserNickname error: $error');
      return null;
    }
  }

  Future<bool> updateUserNickname({
    required String uid,
    required String nickname,
  }) async {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty || uid.isEmpty) return false;
    final ref = _userProfileRef(uid);
    if (ref == null) return false;
    try {
      await ref.set({
        'nickname': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      userProfileCache[uid] = trimmed;
      final rewritten = await rewriteAuthorProfile(uid: uid, nickname: trimmed);
      _logProfileSync('updateUserNickname rewriteAuthorProfile updated $rewritten community docs for uid=$uid');
      return true;
    } catch (error, stack) {
      _logProfileSync('updateUserNickname error', error, stack);
      return false;
    }
  }

  Future<bool> updateUserPhotoUrl({
    required String uid,
    required String photoUrl,
  }) async {
    final trimmed = photoUrl.trim();
    if (trimmed.isEmpty || uid.isEmpty) return false;
    final ref = _userProfileRef(uid);
    if (ref == null) return false;
    try {
      await ref.set({
        'photoUrl': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      userPhotoCache[uid] = trimmed;
      final rewritten = await rewriteAuthorProfile(uid: uid, photoUrl: trimmed);
      _logProfileSync('updateUserPhotoUrl rewriteAuthorProfile updated $rewritten community docs for uid=$uid');
      return true;
    } catch (error, stack) {
      _logProfileSync('updateUserPhotoUrl error', error, stack);
      return false;
    }
  }

  final Map<String, String> userPhotoCache = {};

  Future<String?> fetchUserPhotoUrl(String uid) async {
    final cached = userPhotoCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;
    final ref = _userProfileRef(uid);
    if (ref == null) return null;
    try {
      final snap = await ref.get();
      final url = (snap.data()?['photoUrl'] as String?)?.trim();
      if (url == null || url.isEmpty) return null;
      userPhotoCache[uid] = url;
      return url;
    } catch (error) {
      debugPrint('fetchUserPhotoUrl error: $error');
      return null;
    }
  }

  /// Rewrites denormalized author fields on past community posts.
  /// Returns the number of Firestore documents successfully updated.
  Future<int> rewriteAuthorProfile({
    required String uid,
    String? nickname,
    String? photoUrl,
  }) async {
    final db = _db;
    final name = nickname?.trim();
    final photo = photoUrl?.trim();
    if (uid.isEmpty) return 0;
    if ((name == null || name.isEmpty) && (photo == null || photo.isEmpty)) return 0;

    _logProfileSync('rewriteAuthorProfile start uid=$uid nickname=$name photoUrl=${photo == null || photo.isEmpty ? '(unchanged)' : '(set)'}');

    if (db == null) {
      _rewriteLocalAuthorProfile(uid: uid, name: name, photo: photo);
      _logProfileSync('rewriteAuthorProfile skipped Firestore (not initialized); updated local cache only');
      return 0;
    }

    try {
      final writes = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
      final routinesCol = _routinesCol;
      if (routinesCol != null) {
        final docs = await _queryAllByAuthor(
          col: routinesCol,
          authorId: uid,
          includeNestedRoutineAuthor: true,
        );
        _logProfileSync('rewriteAuthorProfile community_routines matched=${docs.length}');
        for (final doc in docs) {
          final patch = _authorProfilePatch(
            name: name,
            photo: photo,
            includeNestedRoutine: true,
            existing: doc.data(),
            uid: uid,
          );
          if (patch.isNotEmpty) writes[doc.reference] = patch;
        }
      }
      final showcaseCol = _showcaseCol;
      if (showcaseCol != null) {
        final docs = await _queryAllByAuthor(
          col: showcaseCol,
          authorId: uid,
        );
        _logProfileSync('rewriteAuthorProfile community_showcase matched=${docs.length}');
        for (final doc in docs) {
          final patch = _authorProfilePatch(
            name: name,
            photo: photo,
            includeNestedRoutine: false,
            existing: doc.data(),
            uid: uid,
          );
          if (patch.isNotEmpty) writes[doc.reference] = patch;
        }
      }

      _rewriteLocalAuthorProfile(uid: uid, name: name, photo: photo);

      if (writes.isEmpty) {
        _logProfileSync('rewriteAuthorProfile found 0 matching docs for uid=$uid (check authorId field / security rules / indexes)');
        return 0;
      }

      final updated = await _commitAuthorPatches(db, writes);
      _logProfileSync('rewriteAuthorProfile finished uid=$uid updated=$updated / ${writes.length}');
      return updated;
    } catch (error, stack) {
      _logProfileSync(
        'rewriteAuthorProfile FAILED uid=$uid (permission-denied, missing index, or batch commit error)',
        error,
        stack,
      );
      return 0;
    }
  }

  void _rewriteLocalAuthorProfile({
    required String uid,
    String? name,
    String? photo,
  }) {
    for (final post in _localRoutines.where((e) => e.authorId == uid).toList()) {
      final index = _localRoutines.indexOf(post);
      if (index < 0) continue;
      _localRoutines[index] = CommunityRoutinePost.fromJson({
        ...post.toJson(),
        if (name != null && name.isNotEmpty) 'authorName': name,
        if (name != null && name.isNotEmpty) 'authorNickname': name,
        if (photo != null && photo.isNotEmpty) 'authorPhotoUrl': photo,
      });
    }
    for (final item in _localShowcase.where((e) => e.authorId == uid).toList()) {
      final index = _localShowcase.indexOf(item);
      if (index < 0) continue;
      _localShowcase[index] = CommunityShowcaseItem.fromJson({
        ...item.toJson(),
        if (name != null && name.isNotEmpty) 'authorName': name,
        if (name != null && name.isNotEmpty) 'authorNickname': name,
        if (photo != null && photo.isNotEmpty) 'authorPhotoUrl': photo,
      });
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryAllByAuthor({
    required CollectionReference<Map<String, dynamic>> col,
    required String authorId,
    bool includeNestedRoutineAuthor = false,
  }) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> collect(String field) async {
      try {
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        var pages = 0;
        final maxPages = (_authorRewriteMaxDocs / _authorRewritePageSize).ceil();
        while (pages < maxPages) {
          Query<Map<String, dynamic>> query =
              col.where(field, isEqualTo: authorId).limit(_authorRewritePageSize);
          if (cursor != null) {
            query = query.startAfterDocument(cursor);
          }
          final snap = await query.get().timeout(_queryTimeout);
          _logProfileSync(
            'query ${col.path} $field==$authorId page=$pages docs=${snap.docs.length}',
          );
          if (snap.docs.isEmpty) break;
          for (final doc in snap.docs) {
            byId[doc.id] = doc;
          }
          cursor = snap.docs.last;
          pages++;
          if (snap.docs.length < _authorRewritePageSize) break;
        }
      } catch (error, stack) {
        _logProfileSync(
          'FAILED query ${col.path} where $field == $authorId (permission-denied or missing index?)',
          error,
          stack,
        );
      }
    }

    await collect('authorId');
    if (includeNestedRoutineAuthor) {
      await collect('routine.authorId');
    }
    return byId.values.toList();
  }

  Future<int> _commitAuthorPatches(
    FirebaseFirestore db,
    Map<DocumentReference<Map<String, dynamic>>, Map<String, dynamic>> writes,
  ) async {
    final entries = writes.entries.toList();
    var updated = 0;
    for (var offset = 0; offset < entries.length; offset += _batchChunkSize) {
      final slice = entries.skip(offset).take(_batchChunkSize).toList();
      final batch = db.batch();
      for (final entry in slice) {
        batch.update(entry.key, entry.value);
      }
      try {
        await batch.commit();
        updated += slice.length;
        _logProfileSync('WriteBatch commit ok count=${slice.length} offset=$offset');
      } catch (error, stack) {
        _logProfileSync(
          'WriteBatch commit FAILED at offset=$offset count=${slice.length} (permission-denied?). Falling back to sequential updates.',
          error,
          stack,
        );
        for (final entry in slice) {
          try {
            await entry.key.update(entry.value);
            updated++;
          } catch (itemError, itemStack) {
            _logProfileSync('sequential update failed ${entry.key.path}', itemError, itemStack);
          }
        }
      }
    }
    return updated;
  }

  Future<List<CommunityRoutinePost>> fetchRoutinesByAuthor(String authorId, {int limit = defaultPageSize}) async {
    final page = await fetchRoutinesByAuthorPage(authorId: authorId, pageSize: limit);
    return page.posts;
  }

  Future<RoutinesPage> fetchRoutinesByAuthorPage({
    required String authorId,
    int pageSize = authorFeedPageSize,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    if (authorId.isEmpty) return const RoutinesPage(posts: [], hasMore: false);
    final col = _routinesCol;
    if (col == null) {
      final items = _localRoutines.where((e) => e.authorId == authorId || e.routine.authorId == authorId).toList()
        ..sort((a, b) => _compareByDisplayOrder(a.displayOrder, a.createdAt, b.displayOrder, b.createdAt));
      final start = cursor == null ? 0 : items.indexWhere((e) => e.id == cursor.id) + 1;
      final offset = start < 0 ? 0 : start;
      final slice = items.skip(offset).take(pageSize).toList();
      return RoutinesPage(posts: slice, hasMore: offset + slice.length < items.length);
    }
    try {
      final snap = await _getAuthorSnapshot(
        col: col,
        authorId: authorId,
        pageSize: pageSize,
        cursor: cursor,
        nestedAuthorField: 'routine.authorId',
      );
      final posts = <CommunityRoutinePost>[];
      for (final doc in snap.docs) {
        final post = _tryParseRoutinePost(doc);
        if (post == null) continue;
        if (post.authorId != authorId && post.routine.authorId != authorId) continue;
        posts.add(post);
      }
      posts.sort((a, b) => _compareByDisplayOrder(a.displayOrder, a.createdAt, b.displayOrder, b.createdAt));
      _logProfileSync(
        'fetchRoutinesByAuthorPage authorId=$authorId docs=${snap.docs.length} parsed=${posts.length} fallback=${snap.scannedFallback}',
      );
      return RoutinesPage(
        posts: posts,
        hasMore: !snap.scannedFallback && snap.docs.length >= pageSize,
        cursor: snap.scannedFallback || snap.docs.isEmpty ? null : snap.docs.last,
      );
    } catch (error, stack) {
      _logQueryError('fetchRoutinesByAuthorPage', error, stack);
      return const RoutinesPage(posts: [], hasMore: false);
    }
  }

  Future<List<CommunityShowcaseItem>> fetchShowcaseByAuthor(String authorId, {int limit = defaultPageSize}) async {
    final page = await fetchShowcaseByAuthorPage(authorId: authorId, pageSize: limit);
    return page.items;
  }

  Future<ShowcasePage> fetchShowcaseByAuthorPage({
    required String authorId,
    int pageSize = authorFeedPageSize,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    if (authorId.isEmpty) return const ShowcasePage(items: [], hasMore: false);
    final col = _showcaseCol;
    if (col == null) {
      final items = _localShowcase.where((e) => e.authorId == authorId).toList()
        ..sort((a, b) => _compareByDisplayOrder(a.displayOrder, a.createdAt, b.displayOrder, b.createdAt));
      final start = cursor == null ? 0 : items.indexWhere((e) => e.id == cursor.id) + 1;
      final offset = start < 0 ? 0 : start;
      final slice = items.skip(offset).take(pageSize).toList();
      return ShowcasePage(items: slice, hasMore: offset + slice.length < items.length);
    }
    try {
      final snap = await _getAuthorSnapshot(
        col: col,
        authorId: authorId,
        pageSize: pageSize,
        cursor: cursor,
      );
      final items = <CommunityShowcaseItem>[];
      for (final doc in snap.docs) {
        final item = _tryParseShowcaseItem(doc);
        if (item == null) continue;
        if (item.authorId != authorId) continue;
        items.add(item);
      }
      items.sort((a, b) => _compareByDisplayOrder(a.displayOrder, a.createdAt, b.displayOrder, b.createdAt));
      _logProfileSync(
        'fetchShowcaseByAuthorPage authorId=$authorId docs=${snap.docs.length} parsed=${items.length} fallback=${snap.scannedFallback}',
      );
      return ShowcasePage(
        items: items,
        hasMore: !snap.scannedFallback && snap.docs.length >= pageSize,
        newestCursor: snap.scannedFallback || snap.docs.isEmpty ? null : snap.docs.last,
      );
    } catch (error, stack) {
      _logQueryError('fetchShowcaseByAuthorPage', error, stack);
      return const ShowcasePage(items: [], hasMore: false);
    }
  }

  Future<_AuthorSnapshot> _getAuthorSnapshot({
    required CollectionReference<Map<String, dynamic>> col,
    required String authorId,
    required int pageSize,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    String? nestedAuthorField,
  }) async {
    Future<QuerySnapshot<Map<String, dynamic>>> run({
      required String field,
      required bool orderByCreatedAt,
    }) {
      Query<Map<String, dynamic>> query = col.where(field, isEqualTo: authorId);
      if (orderByCreatedAt) {
        query = query.orderBy('createdAt', descending: true);
      }
      query = query.limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      return query.get().timeout(_queryTimeout);
    }

    QuerySnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await run(field: 'authorId', orderByCreatedAt: true);
    } catch (error, stack) {
      _logProfileSync(
        'author query ${col.path} authorId+orderBy(createdAt) failed; retrying without orderBy',
        error,
        stack,
      );
      try {
        snap = await run(field: 'authorId', orderByCreatedAt: false);
      } catch (error2, stack2) {
        _logProfileSync(
          'author query ${col.path} authorId without orderBy also failed',
          error2,
          stack2,
        );
      }
    }

    if ((snap == null || snap.docs.isEmpty) && cursor == null && nestedAuthorField != null) {
      try {
        snap = await run(field: nestedAuthorField, orderByCreatedAt: false);
        _logProfileSync('author query ${col.path} fallback $nestedAuthorField docs=${snap.docs.length}');
      } catch (error, stack) {
        _logProfileSync('author query ${col.path} fallback $nestedAuthorField failed', error, stack);
      }
    }

    if ((snap == null || snap.docs.isEmpty) && cursor == null) {
      try {
        final recent = await col.orderBy('createdAt', descending: true).limit(80).get().timeout(_queryTimeout);
        final matched = recent.docs.where((doc) => _docAuthorId(doc.data()) == authorId).toList();
        _logProfileSync(
          'author query ${col.path} scanned recent=${recent.docs.length} matched=$authorId count=${matched.length}',
        );
        return _AuthorSnapshot(docs: matched, scannedFallback: true);
      } catch (error, stack) {
        _logProfileSync('author query ${col.path} recent-scan fallback failed', error, stack);
      }
    }

    return _AuthorSnapshot(
      docs: snap?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    );
  }

  CommunityRoutinePost? _tryParseRoutinePost(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final resolved = _docAuthorId(data);
      if (resolved.isNotEmpty) data['authorId'] = resolved;
      return CommunityRoutinePost.fromJson(data);
    } catch (error, stack) {
      _logProfileSync('skip unreadable community_routines/${doc.id}', error, stack);
      return null;
    }
  }

  CommunityShowcaseItem? _tryParseShowcaseItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final resolved = _docAuthorId(data);
      if (resolved.isNotEmpty) data['authorId'] = resolved;
      return CommunityShowcaseItem.fromJson(data);
    } catch (error, stack) {
      _logProfileSync('skip unreadable community_showcase/${doc.id}', error, stack);
      return null;
    }
  }

  int _compareByDisplayOrder(int aOrder, DateTime aCreated, int bOrder, DateTime bCreated) {
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);
    return bCreated.compareTo(aCreated);
  }

  Future<void> saveLibrary({
    required String uid,
    required List<SavedRoutine> routines,
    required List<RoutineGroup> groups,
    required List<PracticeResult> practiceResults,
  }) async {
    final ref = _libraryRef(uid);
    if (ref == null) return;
    try {
      await ref.set({
        'routines': routines.map((routine) => routine.toFirestoreJson()).toList(),
        'groups': groups.map((group) => group.toJson()).toList(),
        'practiceResults': const <Map<String, dynamic>>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('saveLibrary error: $error');
    }
  }

  Future<void> upsertRoutine(String uid, SavedRoutine routine) async {
    if (_libraryRef(uid) == null) return;
    try {
      final current = await fetchLibrary(uid);
      final routines = [
        for (final item in current.routines)
          if (item.id != routine.id) item,
        routine,
      ];
      await saveLibrary(
        uid: uid,
        routines: routines,
        groups: current.groups,
        practiceResults: current.practiceResults,
      );
    } catch (error) {
      debugPrint('upsertRoutine error: $error');
    }
  }

  /// Replaces an existing routine document (by id) inside the user library snapshot.
  Future<void> updateRoutine(String uid, SavedRoutine routine) async {
    if (_libraryRef(uid) == null) return;
    try {
      final current = await fetchLibrary(uid);
      final index = current.routines.indexWhere((item) => item.id == routine.id);
      final routines = [...current.routines];
      if (index < 0) {
        routines.insert(0, routine);
      } else {
        routines[index] = routine;
      }
      await saveLibrary(
        uid: uid,
        routines: routines,
        groups: current.groups,
        practiceResults: current.practiceResults,
      );
    } catch (error) {
      debugPrint('updateRoutine error: $error');
    }
  }

  Future<({List<SavedRoutine> routines, List<RoutineGroup> groups, List<PracticeResult> practiceResults})>
      fetchLibrary(String uid) async {
    final ref = _libraryRef(uid);
    if (ref == null) {
      return (
        routines: <SavedRoutine>[],
        groups: <RoutineGroup>[],
        practiceResults: <PracticeResult>[],
      );
    }
    try {
      final snapshot = await ref.get();
      final data = snapshot.data();
      if (data == null) {
        return (
          routines: <SavedRoutine>[],
          groups: <RoutineGroup>[],
          practiceResults: <PracticeResult>[],
        );
      }
      return (
        routines: _maps(data['routines']).map(SavedRoutine.fromJson).toList(),
        groups: _maps(data['groups']).map(RoutineGroup.fromJson).toList(),
        practiceResults: _maps(data['practiceResults']).map(PracticeResult.fromJson).toList(),
      );
    } catch (error) {
      debugPrint('fetchLibrary error: $error');
      return (
        routines: <SavedRoutine>[],
        groups: <RoutineGroup>[],
        practiceResults: <PracticeResult>[],
      );
    }
  }

  Future<CommunityShowcaseItem> sharePracticeToShowcase({
    required PracticeResult result,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    ShowcaseMediaKind? mediaKind,
    String? category,
    SavedRoutine? routine,
  }) async {
    final kind = mediaKind ??
        inferMediaKindFromPath(
          result.recordedPath,
          fallback: result.isAudioRecording ? ShowcaseMediaKind.audio : ShowcaseMediaKind.video,
          audioHint: result.isAudioRecording,
        );
    _logProfileSync(
      'sharePracticeToShowcase start result=${result.id} kind=$kind audioFlag=${result.isAudioRecording} path=${result.recordedPath} bytes=${result.recordedDataBytes?.length ?? 0}',
    );
    final uploadedUrl = await StorageService.uploadPracticeRecording(
      userId: authorId,
      resultId: result.id,
      path: result.recordedPath,
      bytes: result.recordedDataBytes,
      audio: kind == ShowcaseMediaKind.audio,
    );
    if (!isRemotePlayableUrl(uploadedUrl)) {
      _logProfileSync(
        'sharePracticeToShowcase aborted: missing Storage downloadURL (permission, blob read, or Firebase init). path=${result.recordedPath} uploaded=$uploadedUrl',
      );
      throw StateError(
        'Showcase upload failed: no downloadURL for ${result.id} (path=${result.recordedPath})',
      );
    }
    final recordedUrl = uploadedUrl!.trim();
    final authorPhoto = authorPhotoUrl?.trim();
    final thumbnailUrl = youtubeThumbnailUrl(routine?.videoId) ??
        youtubeThumbnailUrl(routine?.videoUrl) ??
        (isRemotePlayableUrl(authorPhoto) ? authorPhoto : null);
    final item = CommunityShowcaseItem(
      id: 'show_${DateTime.now().microsecondsSinceEpoch}',
      title: result.name,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhoto,
      createdAt: DateTime.now(),
      mediaKind: kind,
      likesCount: 0,
      likedBy: const [],
      practiceResultId: result.id,
      routineId: result.routineId,
      recordedPath: recordedUrl,
      videoUrl: recordedUrl,
      thumbnailHint: thumbnailUrl,
      thumbnailUrl: thumbnailUrl,
      category: RoutineCategory.normalize(category ?? result.category),
    );

    final col = _showcaseCol;
    if (col == null) {
      _localShowcase.insert(0, item);
      return item;
    }
    try {
      await col.doc(item.id).set({
        ...item.toJson(),
        'authorId': authorId,
        'authorName': authorName,
        'authorNickname': authorName,
        'videoUrl': recordedUrl,
        'recordedPath': recordedUrl,
        if (authorPhoto != null && authorPhoto.isNotEmpty) 'authorPhotoUrl': authorPhoto,
      });
      userProfileCache[authorId] = authorName;
      _logProfileSync('sharePracticeToShowcase saved ${item.id} videoUrl=$recordedUrl kind=$kind');
      return item;
    } catch (error, stack) {
      _logProfileSync('sharePracticeToShowcase error', error, stack);
      rethrow;
    }
  }

  Future<CommunityRoutinePost> shareRoutineToCommunity({
    required SavedRoutine routine,
    required String description,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
  }) async {
    final tagged = routine.copyWith(authorId: authorId, authorName: authorName);
    final post = CommunityRoutinePost(
      id: 'cpost_${DateTime.now().microsecondsSinceEpoch}',
      routine: tagged,
      description: description,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: DateTime.now(),
      favoriteCount: 0,
      trendingFavorites7d: 0,
      favoritedBy: const [],
      category: tagged.category,
    );
    final col = _routinesCol;
    if (col == null) {
      _localRoutines.insert(0, post);
      return post;
    }
    try {
      await col.doc(post.id).set({
        ...post.toJson(),
        'authorId': authorId,
        'authorName': authorName,
        'authorNickname': authorName,
        if (authorPhotoUrl != null && authorPhotoUrl.trim().isNotEmpty) 'authorPhotoUrl': authorPhotoUrl.trim(),
      });
      userProfileCache[authorId] = authorName;
      return post;
    } catch (error, stack) {
      _logProfileSync('shareRoutineToCommunity error', error, stack);
      _localRoutines.insert(0, post);
      return post;
    }
  }

  /// Newest public showcase items by default (createdAt desc). Search only filters.
  Future<ShowcasePage> fetchShowcaseFirstPage({
    int pageSize = defaultPageSize,
    String searchQuery = '',
    String? category,
  }) async {
    final col = _showcaseCol;
    if (col == null) {
      final sorted = [..._localShowcase]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final filtered = _filterSearch(sorted, searchQuery)
          .where((e) => RoutineCategory.matches(e.category, category))
          .toList();
      return ShowcasePage(
        items: filtered.take(pageSize).toList(),
        hasMore: filtered.length > pageSize,
      );
    }

    try {
      final snap = await _applyCategoryFilter(col, category)
          .orderBy('createdAt', descending: true)
          .limit(pageSize)
          .get()
          .timeout(_queryTimeout);
      final items = snap.docs
          .map((d) => CommunityShowcaseItem.fromJson({...d.data(), 'id': d.id}))
          .where((e) => _matchesSearch(e.title, e.authorName, searchQuery))
          .where((e) => RoutineCategory.matches(e.category, category))
          .toList();

      return ShowcasePage(
        items: items,
        hasMore: snap.docs.length >= pageSize,
        newestCursor: snap.docs.isEmpty ? null : snap.docs.last,
      );
    } catch (error) {
      _logQueryError('fetchShowcaseFirstPage', error);
      debugPrint('fetchShowcaseFirstPage fallback to newest page');
      return _fetchShowcaseNewest(
        pageSize: pageSize,
        excludeIds: const {},
        searchQuery: searchQuery,
        category: category,
      );
    }
  }

  Future<ShowcasePage> fetchShowcaseNextPage({
    required DocumentSnapshot<Map<String, dynamic>>? cursor,
    required Set<String> excludeIds,
    int pageSize = defaultPageSize,
    String searchQuery = '',
    String? category,
  }) {
    return _fetchShowcaseNewest(
      pageSize: pageSize,
      excludeIds: excludeIds,
      cursor: cursor,
      searchQuery: searchQuery,
      category: category,
    );
  }

  Future<List<CommunityShowcaseItem>> fetchTopLikedShowcase({int limit = showcaseTopLikedCount}) async {
    final col = _showcaseCol;
    if (col == null) {
      final sorted = [..._localShowcase]..sort((a, b) => b.likesCount.compareTo(a.likesCount));
      return sorted.take(limit).toList();
    }
    try {
      // Prefer recent window + in-memory likes sort (no likesCount index required).
      final snap = await col
          .orderBy('createdAt', descending: true)
          .limit(routinesFetchWindow)
          .get()
          .timeout(_queryTimeout);
      final items = snap.docs
          .map((d) => CommunityShowcaseItem.fromJson({...d.data(), 'id': d.id}))
          .toList()
        ..sort((a, b) => b.likesCount.compareTo(a.likesCount));
      return items.take(limit).toList();
    } catch (error) {
      debugPrint('fetchTopLikedShowcase error: $error');
      return const [];
    }
  }

  Future<ShowcasePage> _fetchShowcaseNewest({
    required int pageSize,
    required Set<String> excludeIds,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    String searchQuery = '',
    String? category,
  }) async {
    final col = _showcaseCol;
    if (col == null) {
      final sorted = [..._localShowcase]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final filtered = _filterSearch(
        sorted.where((e) => !excludeIds.contains(e.id)).toList(),
        searchQuery,
      ).where((e) => RoutineCategory.matches(e.category, category)).toList();
      return ShowcasePage(items: filtered.take(pageSize).toList(), hasMore: filtered.length > pageSize);
    }
    try {
      Query<Map<String, dynamic>> query = _applyCategoryFilter(col, category)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snap = await query.get().timeout(_queryTimeout);
      final items = <CommunityShowcaseItem>[];
      DocumentSnapshot<Map<String, dynamic>>? last;
      for (final doc in snap.docs) {
        last = doc;
        if (excludeIds.contains(doc.id)) continue;
        final item = CommunityShowcaseItem.fromJson({...doc.data(), 'id': doc.id});
        if (!_matchesSearch(item.title, item.authorName, searchQuery)) continue;
        if (!RoutineCategory.matches(item.category, category)) continue;
        items.add(item);
      }
      return ShowcasePage(
        items: items,
        hasMore: snap.docs.length >= pageSize,
        newestCursor: last,
      );
    } catch (error) {
      _logQueryError('fetchShowcaseNewest', error);
      return const ShowcasePage(items: [], hasMore: false);
    }
  }

  Future<CommunityShowcaseItem?> toggleShowcaseLike({
    required String itemId,
    required String uid,
  }) async {
    if (uid.isEmpty) return null;
    final col = _showcaseCol;
    if (col == null) {
      final index = _localShowcase.indexWhere((e) => e.id == itemId);
      if (index < 0) return null;
      final item = _localShowcase[index];
      final liked = [...item.likedBy];
      if (liked.contains(uid)) {
        liked.remove(uid);
      } else {
        liked.add(uid);
      }
      final updated = item.copyWith(likesCount: liked.length, likedBy: liked);
      _localShowcase[index] = updated;
      return updated;
    }
    try {
      final ref = col.doc(itemId);
      return await _db!.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return null;
        final data = snap.data()!;
        final likedBy = (data['likedBy'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        if (likedBy.contains(uid)) {
          likedBy.remove(uid);
        } else {
          likedBy.add(uid);
        }
        tx.update(ref, {
          'likedBy': likedBy,
          'likesCount': likedBy.length,
        });
        return CommunityShowcaseItem.fromJson({...data, 'id': itemId, 'likedBy': likedBy, 'likesCount': likedBy.length});
      });
    } catch (error) {
      debugPrint('toggleShowcaseLike error: $error');
      return null;
    }
  }

  Future<RoutinesPage> fetchRoutinesFirstPage({
    String searchQuery = '',
    int pageSize = defaultPageSize,
    String? category,
  }) {
    return _fetchRoutinesPage(
      pageSize: pageSize,
      searchQuery: searchQuery,
      category: category,
    );
  }

  Future<RoutinesPage> fetchRoutinesNextPage({
    required DocumentSnapshot<Map<String, dynamic>>? cursor,
    required Set<String> excludeIds,
    String searchQuery = '',
    int pageSize = defaultPageSize,
    String? category,
  }) {
    return _fetchRoutinesPage(
      pageSize: pageSize,
      searchQuery: searchQuery,
      category: category,
      cursor: cursor,
      excludeIds: excludeIds,
    );
  }

  Future<RoutinesPage> _fetchRoutinesPage({
    required int pageSize,
    String searchQuery = '',
    String? category,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    Set<String> excludeIds = const {},
  }) async {
    final col = _routinesCol;
    if (col == null) {
      final sorted = [..._localRoutines]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final filtered = _filterRoutineSearch(sorted, searchQuery)
          .where((e) => RoutineCategory.matches(e.category, category))
          .where((e) => !excludeIds.contains(e.id))
          .toList();
      return RoutinesPage(
        posts: filtered.take(pageSize).toList(),
        hasMore: filtered.length > pageSize,
      );
    }
    try {
      Query<Map<String, dynamic>> query = _applyCategoryFilter(col, category)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snap = await query.get().timeout(_queryTimeout);
      final posts = <CommunityRoutinePost>[];
      for (final doc in snap.docs) {
        if (excludeIds.contains(doc.id)) continue;
        final post = CommunityRoutinePost.fromJson({...doc.data(), 'id': doc.id});
        if (!RoutineCategory.matches(post.category, category)) continue;
        if (searchQuery.trim().isNotEmpty &&
            !_filterRoutineSearch([post], searchQuery).isNotEmpty) {
          continue;
        }
        posts.add(post);
      }
      return RoutinesPage(
        posts: posts,
        hasMore: snap.docs.length >= pageSize,
        cursor: snap.docs.isEmpty ? null : snap.docs.last,
      );
    } catch (error) {
      _logQueryError('fetchRoutinesPage', error);
      return const RoutinesPage(posts: [], hasMore: false);
    }
  }

  Future<List<CommunityRoutinePost>> fetchTrendingRoutines({
    String searchQuery = '',
    int limit = defaultPageSize,
    int fetchWindow = routinesFetchWindow,
    String? category,
  }) async {
    final page = await fetchRoutinesFirstPage(
      searchQuery: searchQuery,
      pageSize: limit,
      category: category,
    );
    return page.posts;
  }

  Future<bool> deleteCommunityRoutine({
    required String postId,
    required String requesterId,
  }) async {
    if (postId.isEmpty || requesterId.isEmpty) return false;
    final col = _routinesCol;
    if (col == null) {
      final index = _localRoutines.indexWhere((e) => e.id == postId);
      if (index < 0) return false;
      if (_localRoutines[index].authorId != requesterId) return false;
      _localRoutines.removeAt(index);
      return true;
    }
    try {
      final ref = col.doc(postId);
      final snap = await ref.get().timeout(_queryTimeout);
      if (!snap.exists) return false;
      final authorId = _docAuthorId(snap.data() ?? {});
      if (authorId != requesterId) return false;
      await ref.delete();
      return true;
    } catch (error, stack) {
      _logProfileSync('deleteCommunityRoutine error', error, stack);
      return false;
    }
  }

  Future<bool> deleteShowcaseItem({
    required String itemId,
    required String requesterId,
  }) async {
    if (itemId.isEmpty || requesterId.isEmpty) return false;
    final col = _showcaseCol;
    if (col == null) {
      final index = _localShowcase.indexWhere((e) => e.id == itemId);
      if (index < 0) return false;
      if (_localShowcase[index].authorId != requesterId) return false;
      _localShowcase.removeAt(index);
      return true;
    }
    try {
      final ref = col.doc(itemId);
      final snap = await ref.get().timeout(_queryTimeout);
      if (!snap.exists) return false;
      final authorId = _docAuthorId(snap.data() ?? {});
      if (authorId != requesterId) return false;
      await ref.delete();
      return true;
    } catch (error, stack) {
      _logProfileSync('deleteShowcaseItem error', error, stack);
      return false;
    }
  }

  Future<int> deleteCommunityItemsBatch({
    required String requesterId,
    List<String> routineIds = const [],
    List<String> showcaseIds = const [],
  }) async {
    if (requesterId.isEmpty) return 0;
    var deleted = 0;
    for (final id in routineIds) {
      if (await deleteCommunityRoutine(postId: id, requesterId: requesterId)) {
        deleted++;
      }
    }
    for (final id in showcaseIds) {
      if (await deleteShowcaseItem(itemId: id, requesterId: requesterId)) {
        deleted++;
      }
    }
    return deleted;
  }

  Future<bool> updateRoutineDisplayOrder({
    required String requesterId,
    required List<String> orderedIds,
  }) {
    return _updateDisplayOrder(
      requesterId: requesterId,
      orderedIds: orderedIds,
      firestoreCol: _routinesCol,
      localItems: _localRoutines,
      applyLocal: (index, order) {
        _localRoutines[index] = _localRoutines[index].copyWith(displayOrder: order);
      },
    );
  }

  Future<bool> updateShowcaseDisplayOrder({
    required String requesterId,
    required List<String> orderedIds,
  }) {
    return _updateDisplayOrder(
      requesterId: requesterId,
      orderedIds: orderedIds,
      firestoreCol: _showcaseCol,
      localItems: _localShowcase,
      applyLocal: (index, order) {
        _localShowcase[index] = _localShowcase[index].copyWith(displayOrder: order);
      },
    );
  }

  Future<bool> _updateDisplayOrder({
    required String requesterId,
    required List<String> orderedIds,
    required CollectionReference<Map<String, dynamic>>? firestoreCol,
    required List<dynamic> localItems,
    required void Function(int index, int order) applyLocal,
  }) async {
    if (requesterId.isEmpty || orderedIds.isEmpty) return false;
    if (firestoreCol == null) {
      for (var i = 0; i < orderedIds.length; i++) {
        final index = localItems.indexWhere((e) => e.id == orderedIds[i] && e.authorId == requesterId);
        if (index >= 0) applyLocal(index, i);
      }
      return true;
    }
    final db = _db;
    if (db == null) return false;
    try {
      final batch = db.batch();
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(firestoreCol.doc(orderedIds[i]), {'displayOrder': i});
      }
      await batch.commit().timeout(_queryTimeout);
      return true;
    } catch (error) {
      debugPrint('updateDisplayOrder error: $error');
      return false;
    }
  }

  Future<CommunityRoutinePost?> toggleCommunityFavorite({
    required String postId,
    required String uid,
  }) async {
    if (uid.isEmpty) return null;
    final col = _routinesCol;
    if (col == null) {
      final index = _localRoutines.indexWhere((e) => e.id == postId);
      if (index < 0) return null;
      final post = _localRoutines[index];
      final favoritedBy = [...post.favoritedBy];
      final events = _localFavoriteEvents.putIfAbsent(postId, () => <DateTime>[]);
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      if (favoritedBy.contains(uid)) {
        favoritedBy.remove(uid);
        if (events.isNotEmpty) events.removeLast();
      } else {
        favoritedBy.add(uid);
        events.add(DateTime.now());
      }
      final trending = events.where((t) => t.isAfter(weekAgo)).length;
      final updated = post.copyWith(
        favoritedBy: favoritedBy,
        favoriteCount: favoritedBy.length,
        trendingFavorites7d: trending,
      );
      _localRoutines[index] = updated;
      return updated;
    }
    try {
      final ref = col.doc(postId);
      final eventRef = ref.collection('favoriteEvents').doc(uid);
      return await _db!.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return null;
        final data = snap.data()!;
        final favoritedBy = (data['favoritedBy'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final eventSnap = await tx.get(eventRef);
        var trending = (data['trendingFavorites7d'] as num?)?.toInt() ?? 0;
        if (favoritedBy.contains(uid)) {
          favoritedBy.remove(uid);
          if (eventSnap.exists) tx.delete(eventRef);
          trending = (trending - 1).clamp(0, 1 << 30);
        } else {
          favoritedBy.add(uid);
          tx.set(eventRef, {'uid': uid, 'favoritedAt': FieldValue.serverTimestamp()});
          trending += 1;
        }
        tx.update(ref, {
          'favoritedBy': favoritedBy,
          'favoriteCount': favoritedBy.length,
          'trendingFavorites7d': trending,
        });
        return CommunityRoutinePost.fromJson({
          ...data,
          'id': postId,
          'favoritedBy': favoritedBy,
          'favoriteCount': favoritedBy.length,
          'trendingFavorites7d': trending,
        });
      });
    } catch (error) {
      debugPrint('toggleCommunityFavorite error: $error');
      return null;
    }
  }

  List<Map<String, dynamic>> _maps(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  bool _matchesSearch(String a, String b, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return a.toLowerCase().contains(q) || b.toLowerCase().contains(q);
  }

  List<CommunityShowcaseItem> _filterSearch(List<CommunityShowcaseItem> items, String query) {
    return items.where((e) => _matchesSearch(e.title, e.authorName, query)).toList();
  }

  List<CommunityRoutinePost> _filterRoutineSearch(List<CommunityRoutinePost> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (e) =>
              e.routine.name.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q) ||
              e.authorName.toLowerCase().contains(q),
        )
        .toList();
  }
}