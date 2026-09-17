import 'package:flutter/foundation.dart';

import 'routine_category.dart';
import 'routine_models.dart';

/// Sort options for instructor class lists (UI only).
enum ClassSortOrder {
  latest,
  oldest,
  popular,
}

/// A LOOPI Class course created by an instructor.
///
/// Additive model — does not alter [SavedRoutine] or existing Firestore schemas.
@immutable
class ClassCourse {
  const ClassCourse({
    required this.id,
    required this.title,
    required this.instructorId,
    required this.instructorName,
    required this.description,
    required this.createdAt,
    this.instructorAvatarUrl,
    this.thumbnailUrl,
    this.category = RoutineCategory.dance,
    this.price = 0,
    this.studentCount = 0,
    this.rating = 0,
    this.units = const [],
  });

  final String id;
  final String title;
  final String instructorId;
  final String instructorName;
  final String? instructorAvatarUrl;
  final String description;
  final String? thumbnailUrl;
  final String category;
  /// Price in KRW. `0` means free.
  final int price;
  final DateTime createdAt;
  final int studentCount;
  final double rating;
  final List<ClassLessonUnit> units;

  bool get isFree => price <= 0;

  int get sectionCount {
    var n = 0;
    for (final unit in units) {
      n += unit.practiceSegmentCount;
    }
    return n;
  }

  int get lessonCount => units.length;

  factory ClassCourse.fromJson(Map<String, dynamic> json) {
    DateTime parseCreatedAt(Object? raw) {
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    return ClassCourse(
      id: json['id']?.toString() ?? 'cls_${DateTime.now().microsecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Untitled Class',
      instructorId: json['instructorId'] as String? ?? '',
      instructorName: json['instructorName'] as String? ?? 'Instructor',
      instructorAvatarUrl: json['instructorAvatarUrl'] as String?,
      description: json['description'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      category: json['category'] as String? ?? RoutineCategory.dance,
      price: (json['price'] as num?)?.toInt() ?? 0,
      createdAt: parseCreatedAt(json['createdAt']),
      studentCount: (json['studentCount'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      units: (json['units'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => ClassLessonUnit.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'instructorId': instructorId,
        'instructorName': instructorName,
        'instructorAvatarUrl': instructorAvatarUrl,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
        'category': category,
        'price': price,
        'createdAt': createdAt.toIso8601String(),
        'studentCount': studentCount,
        'rating': rating,
        'units': units.map((u) => u.toJson()).toList(),
      };

  ClassCourse copyWith({
    String? title,
    String? description,
    String? thumbnailUrl,
    String? category,
    int? price,
    int? studentCount,
    double? rating,
    List<ClassLessonUnit>? units,
  }) {
    return ClassCourse(
      id: id,
      title: title ?? this.title,
      instructorId: instructorId,
      instructorName: instructorName,
      instructorAvatarUrl: instructorAvatarUrl,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      category: category ?? this.category,
      price: price ?? this.price,
      createdAt: createdAt,
      studentCount: studentCount ?? this.studentCount,
      rating: rating ?? this.rating,
      units: units ?? this.units,
    );
  }
}

/// One lesson inside a [ClassCourse].
///
/// Prefer [routineId] for library-linked practice, or [embeddedRoutine] for
/// self-contained demos without mutating existing routine storage.
@immutable
class ClassLessonUnit {
  const ClassLessonUnit({
    required this.id,
    required this.courseId,
    required this.unitTitle,
    required this.lessonVideoUrl,
    this.routineId,
    this.embeddedRoutine,
  });

  final String id;
  final String courseId;
  final String unitTitle;

  /// Instructor explanation clip (YouTube URL/id or network video URL).
  final String lessonVideoUrl;

  /// Optional pointer into the user's / community routine library.
  final String? routineId;

  /// Optional snapshot of a practice routine (sections A/B/C with speed/loop).
  final SavedRoutine? embeddedRoutine;

  SavedRoutine? get practiceRoutine => embeddedRoutine;

  int get practiceSegmentCount => embeddedRoutine?.segments.length ?? 0;

  factory ClassLessonUnit.fromJson(Map<String, dynamic> json) {
    SavedRoutine? embedded;
    final raw = json['embeddedRoutine'];
    if (raw is Map) {
      embedded = SavedRoutine.fromJson(Map<String, dynamic>.from(raw));
    }
    return ClassLessonUnit(
      id: json['id']?.toString() ?? 'unit_${DateTime.now().microsecondsSinceEpoch}',
      courseId: json['courseId']?.toString() ?? '',
      unitTitle: json['unitTitle'] as String? ?? 'Lesson',
      lessonVideoUrl: json['lessonVideoUrl'] as String? ?? '',
      routineId: json['routineId'] as String?,
      embeddedRoutine: embedded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'unitTitle': unitTitle,
        'lessonVideoUrl': lessonVideoUrl,
        'routineId': routineId,
        if (embeddedRoutine != null) 'embeddedRoutine': embeddedRoutine!.toJson(),
      };
}
