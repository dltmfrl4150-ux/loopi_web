import 'package:flutter/foundation.dart';

import 'routine_category.dart';
import 'routine_models.dart';

enum ShowcaseMediaKind { video, audio }

@immutable
class CommunityShowcaseItem {
  const CommunityShowcaseItem({
    required this.id,
    required this.title,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    required this.mediaKind,
    required this.likesCount,
    required this.likedBy,
    this.practiceResultId,
    this.routineId,
    this.recordedPath,
    this.videoUrl,
    this.thumbnailHint,
    this.thumbnailUrl,
    this.displayOrder = 0,
    this.category = RoutineCategory.dance,
  });

  final String id;
  final String title;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final ShowcaseMediaKind mediaKind;
  final int likesCount;
  final List<String> likedBy;
  final String? practiceResultId;
  final String? routineId;
  final String? recordedPath;
  final String? videoUrl;
  final String? thumbnailHint;
  final String? thumbnailUrl;
  final int displayOrder;
  final String category;

  bool isLikedBy(String? uid) => uid != null && likedBy.contains(uid);

  /// Remote Storage (or other https) URL that the Showcase player can open.
  String? get playableUrl {
    for (final candidate in [videoUrl, recordedPath]) {
      if (isRemotePlayableUrl(candidate)) return candidate!.trim();
    }
    return null;
  }

  String get shortTitle {
    final t = title.trim();
    if (t.length <= 10) return t;
    return '${t.substring(0, 10)}…';
  }

  factory CommunityShowcaseItem.fromJson(Map<String, dynamic> json) {
    final kindRaw = (json['mediaKind'] as String? ?? 'video').toLowerCase();
    return CommunityShowcaseItem(
      id: json['id'] as String? ?? 'show_${DateTime.now().microsecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Untitled',
      authorId: communityAuthorIdFromJson(json),
      authorName: (json['authorNickname'] as String?)?.trim().isNotEmpty == true
          ? (json['authorNickname'] as String).trim()
          : (json['authorName'] as String? ?? 'Anonymous'),
      authorPhotoUrl: (json['authorPhotoUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['authorPhotoUrl'] as String).trim()
          : null,
      createdAt: parseCommunityDate(json['createdAt']),
      mediaKind: kindRaw == 'audio' ? ShowcaseMediaKind.audio : ShowcaseMediaKind.video,
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      practiceResultId: json['practiceResultId'] as String?,
      routineId: json['routineId'] as String?,
      recordedPath: (json['recordedPath'] as String?) ?? (json['videoUrl'] as String?),
      videoUrl: (json['videoUrl'] as String?) ?? (json['recordedPath'] as String?),
      thumbnailHint: json['thumbnailHint'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? json['thumbnailHint'] as String?,
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
      category: RoutineCategory.normalize(json['category'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authorId': authorId,
        'authorName': authorName,
        'authorNickname': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'createdAt': createdAt.toIso8601String(),
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'mediaKind': mediaKind.name,
        'likesCount': likesCount,
        'likedBy': likedBy,
        'practiceResultId': practiceResultId,
        'routineId': routineId,
        'recordedPath': recordedPath,
        'videoUrl': videoUrl ?? recordedPath,
        'thumbnailHint': thumbnailHint ?? thumbnailUrl,
        'thumbnailUrl': thumbnailUrl ?? thumbnailHint,
        'displayOrder': displayOrder,
        'category': RoutineCategory.normalize(category),
      };

  CommunityShowcaseItem copyWith({
    int? likesCount,
    List<String>? likedBy,
    int? displayOrder,
    String? category,
  }) {
    return CommunityShowcaseItem(
      id: id,
      title: title,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: createdAt,
      mediaKind: mediaKind,
      likesCount: likesCount ?? this.likesCount,
      likedBy: likedBy ?? this.likedBy,
      practiceResultId: practiceResultId,
      routineId: routineId,
      recordedPath: recordedPath,
      videoUrl: videoUrl,
      thumbnailHint: thumbnailHint,
      thumbnailUrl: thumbnailUrl,
      displayOrder: displayOrder ?? this.displayOrder,
      category: RoutineCategory.normalize(category ?? this.category),
    );
  }
}

@immutable
class CommunityRoutinePost {
  const CommunityRoutinePost({
    required this.id,
    required this.routine,
    required this.description,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    required this.favoriteCount,
    required this.trendingFavorites7d,
    required this.favoritedBy,
    this.displayOrder = 0,
    this.category = RoutineCategory.dance,
  });

  final String id;
  final SavedRoutine routine;
  final String description;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final int favoriteCount;
  final int trendingFavorites7d;
  final List<String> favoritedBy;
  final int displayOrder;
  final String category;

  bool isFavoritedBy(String? uid) => uid != null && favoritedBy.contains(uid);

  factory CommunityRoutinePost.fromJson(Map<String, dynamic> json) {
    final routineRaw = json['routine'];
    final routineMap = routineRaw is Map
        ? Map<String, dynamic>.from(routineRaw)
        : <String, dynamic>{};
    final routine = SavedRoutine.fromJson(routineMap);
    return CommunityRoutinePost(
      id: json['id'] as String? ?? 'cpost_${DateTime.now().microsecondsSinceEpoch}',
      routine: routine,
      description: json['description'] as String? ?? '',
      authorId: communityAuthorIdFromJson(json, nestedRoutine: routineMap),
      authorName: (json['authorNickname'] as String?)?.trim().isNotEmpty == true
          ? (json['authorNickname'] as String).trim()
          : (json['authorName'] as String? ?? 'Anonymous'),
      authorPhotoUrl: (json['authorPhotoUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['authorPhotoUrl'] as String).trim()
          : null,
      createdAt: parseCommunityDate(json['createdAt']),
      favoriteCount: (json['favoriteCount'] as num?)?.toInt() ?? 0,
      trendingFavorites7d: (json['trendingFavorites7d'] as num?)?.toInt() ?? 0,
      favoritedBy: (json['favoritedBy'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
      category: RoutineCategory.normalize(json['category'] as String? ?? routine.category),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'routine': routine.toFirestoreJson(),
        'description': description,
        'authorId': authorId,
        'authorName': authorName,
        'authorNickname': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'createdAt': createdAt.toIso8601String(),
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'favoriteCount': favoriteCount,
        'trendingFavorites7d': trendingFavorites7d,
        'favoritedBy': favoritedBy,
        'displayOrder': displayOrder,
        'category': RoutineCategory.normalize(category),
      };

  CommunityRoutinePost copyWith({
    int? favoriteCount,
    int? trendingFavorites7d,
    List<String>? favoritedBy,
    int? displayOrder,
    String? category,
  }) {
    return CommunityRoutinePost(
      id: id,
      routine: routine,
      description: description,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: createdAt,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      trendingFavorites7d: trendingFavorites7d ?? this.trendingFavorites7d,
      favoritedBy: favoritedBy ?? this.favoritedBy,
      displayOrder: displayOrder ?? this.displayOrder,
      category: RoutineCategory.normalize(category ?? this.category),
    );
  }
}

bool isRemotePlayableUrl(String? value) {
  if (value == null) return false;
  final url = value.trim();
  if (url.isEmpty) return false;
  if (!(url.startsWith('https://') || url.startsWith('http://'))) return false;
  if (url.contains('localhost') || url.contains('127.0.0.1')) return false;
  if (url.startsWith('blob:') || url.startsWith('data:')) return false;
  return true;
}

ShowcaseMediaKind inferMediaKindFromPath(
  String? path, {
  ShowcaseMediaKind fallback = ShowcaseMediaKind.video,
  bool? audioHint,
}) {
  if (audioHint == true) return ShowcaseMediaKind.audio;
  if (path == null || path.isEmpty) return fallback;
  final lower = path.toLowerCase();
  const audioExt = ['.m4a', '.mp3', '.wav', '.aac', '.ogg', '.flac'];
  for (final ext in audioExt) {
    if (lower.contains(ext)) return ShowcaseMediaKind.audio;
  }
  if (lower.contains('audio/webm') || lower.contains('audio%2fwebm')) {
    return ShowcaseMediaKind.audio;
  }
  return fallback;
}

String communityAuthorIdFromJson(Map<String, dynamic> json, {Map<String, dynamic>? nestedRoutine}) {
  final top = json['authorId']?.toString().trim() ?? '';
  if (top.isNotEmpty && top != 'me') return top;
  final routine = nestedRoutine ?? (json['routine'] is Map ? Map<String, dynamic>.from(json['routine'] as Map) : null);
  final nested = routine?['authorId']?.toString().trim() ?? '';
  if (nested.isNotEmpty && nested != 'me') return nested;
  return top;
}

DateTime parseCommunityDate(Object? raw) {
  if (raw == null) return DateTime.now();
  if (raw is DateTime) return raw;
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  try {
    final dynamic value = raw;
    if (value is Map && value['seconds'] != null) {
      final seconds = (value['seconds'] as num).toInt();
      final nanos = (value['nanoseconds'] as num?)?.toInt() ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + nanos ~/ 1000000);
    }
    final maybeDate = value.toDate?.call();
    if (maybeDate is DateTime) return maybeDate;
  } catch (_) {}
  if (raw is String) {
    return DateTime.tryParse(raw) ?? DateTime.now();
  }
  return DateTime.now();
}
