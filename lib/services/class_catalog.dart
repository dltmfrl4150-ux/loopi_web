import 'package:flutter/foundation.dart';

import '../models/class_models.dart';
import '../models/routine_category.dart';
import '../models/routine_models.dart';

/// Local/demo catalog for LOOPI Classes.
///
/// Keeps class data out of existing routine Firestore schemas until a dedicated
/// backend collection is introduced.
class ClassCatalog extends ChangeNotifier {
  ClassCatalog._() {
    _courses
      ..clear()
      ..addAll(_seedCourses());
  }

  static final ClassCatalog instance = ClassCatalog._();

  final List<ClassCourse> _courses = [];
  final Set<String> _enrolledIds = {};

  List<ClassCourse> get courses => List.unmodifiable(_courses);

  bool isEnrolled(String courseId) => _enrolledIds.contains(courseId);

  ClassCourse? byId(String id) {
    for (final course in _courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  List<ClassCourse> listAll({String category = RoutineCategory.all}) {
    if (category == RoutineCategory.all) return courses;
    return _courses.where((c) => c.category == category).toList();
  }

  List<ClassCourse> listForInstructor(
    String instructorId, {
    ClassSortOrder sort = ClassSortOrder.latest,
  }) {
    final list = _courses.where((c) => c.instructorId == instructorId).toList();
    switch (sort) {
      case ClassSortOrder.latest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ClassSortOrder.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case ClassSortOrder.popular:
        list.sort((a, b) {
          final byStudents = b.studentCount.compareTo(a.studentCount);
          if (byStudents != 0) return byStudents;
          return b.rating.compareTo(a.rating);
        });
    }
    return list;
  }

  void enroll(String courseId) {
    if (!_enrolledIds.add(courseId)) return;
    final index = _courses.indexWhere((c) => c.id == courseId);
    if (index >= 0) {
      final course = _courses[index];
      _courses[index] = course.copyWith(studentCount: course.studentCount + 1);
    }
    notifyListeners();
  }

  void upsert(ClassCourse course) {
    final index = _courses.indexWhere((c) => c.id == course.id);
    if (index >= 0) {
      _courses[index] = course;
    } else {
      _courses.insert(0, course);
    }
    notifyListeners();
  }

  void delete(String courseId) {
    _courses.removeWhere((c) => c.id == courseId);
    _enrolledIds.remove(courseId);
    notifyListeners();
  }

  static List<ClassCourse> _seedCourses() {
    final now = DateTime.now();
    final demoRoutine = SavedRoutine(
      id: 'demo_rtn_kpop_basics',
      name: 'K-Pop Basic Groove',
      videoUrl: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      videoId: 'M7lc1UVf-VE',
      createdAt: now.subtract(const Duration(days: 3)),
      category: RoutineCategory.dance,
      authorId: 'instructor_loopi',
      authorName: 'LOOPI Coach',
      isMirrored: true,
      segments: const [
        RoutineSegment(id: 'seg_a', startSec: 0, endSec: 8, speed: 0.5, loopCount: 2),
        RoutineSegment(id: 'seg_b', startSec: 8, endSec: 16, speed: 0.7, loopCount: 2),
        RoutineSegment(id: 'seg_c', startSec: 16, endSec: 24, speed: 1.0, loopCount: 1),
      ],
    );

    final unit1 = ClassLessonUnit(
      id: 'unit_1',
      courseId: 'cls_kpop_101',
      unitTitle: '1강 · 그루브 기본',
      lessonVideoUrl: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
      routineId: demoRoutine.id,
      embeddedRoutine: demoRoutine,
    );

    final hipHopRoutine = SavedRoutine(
      id: 'demo_rtn_hiphop_footwork',
      name: 'Hip-Hop Footwork Intro',
      videoUrl: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
      videoId: 'jNQXAC9IVRw',
      createdAt: now.subtract(const Duration(days: 10)),
      category: RoutineCategory.dance,
      authorId: 'instructor_mira',
      authorName: 'Mira',
      isMirrored: true,
      segments: const [
        RoutineSegment(id: 'seg_a', startSec: 0, endSec: 6, speed: 0.6, loopCount: 3),
        RoutineSegment(id: 'seg_b', startSec: 6, endSec: 12, speed: 0.8, loopCount: 2),
      ],
    );

    return [
      ClassCourse(
        id: 'cls_kpop_101',
        title: 'K-Pop 안무 입문 클래스',
        instructorId: 'instructor_loopi',
        instructorName: 'LOOPI Coach',
        description: '기초 그루브부터 포인트 구간까지, 강의 영상과 루틴 반복을 한 화면에서 연습하세요.',
        thumbnailUrl: 'https://img.youtube.com/vi/M7lc1UVf-VE/hqdefault.jpg',
        category: RoutineCategory.dance,
        price: 0,
        createdAt: now.subtract(const Duration(days: 2)),
        studentCount: 128,
        rating: 4.8,
        units: [unit1],
      ),
      ClassCourse(
        id: 'cls_hiphop_foot',
        title: '힙합 풋워크 집중반',
        instructorId: 'instructor_mira',
        instructorName: 'Mira',
        description: '발 움직임과 무게 이동을 천천히 익힌 뒤 원속으로 연결합니다.',
        thumbnailUrl: 'https://img.youtube.com/vi/jNQXAC9IVRw/hqdefault.jpg',
        category: RoutineCategory.dance,
        price: 9900,
        createdAt: now.subtract(const Duration(days: 8)),
        studentCount: 64,
        rating: 4.6,
        units: [
          ClassLessonUnit(
            id: 'unit_hh_1',
            courseId: 'cls_hiphop_foot',
            unitTitle: '1강 · 풋워크 기초',
            lessonVideoUrl: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
            routineId: hipHopRoutine.id,
            embeddedRoutine: hipHopRoutine,
          ),
        ],
      ),
      ClassCourse(
        id: 'cls_lang_shadow',
        title: '영어 섀도잉 스피킹 클래스',
        instructorId: 'instructor_loopi',
        instructorName: 'LOOPI Coach',
        description: '짧은 문장을 구간별로 듣고 따라 말하며 리듬을 익히는 어학 클래스입니다.',
        thumbnailUrl: 'https://img.youtube.com/vi/M7lc1UVf-VE/mqdefault.jpg',
        category: RoutineCategory.language,
        price: 0,
        createdAt: now.subtract(const Duration(days: 1)),
        studentCount: 42,
        rating: 4.5,
        units: [
          ClassLessonUnit(
            id: 'unit_lang_1',
            courseId: 'cls_lang_shadow',
            unitTitle: '1강 · 리듬 따라 말하기',
            lessonVideoUrl: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
            embeddedRoutine: SavedRoutine(
              id: 'demo_rtn_lang',
              name: 'Shadowing Drill',
              videoUrl: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
              videoId: 'M7lc1UVf-VE',
              createdAt: now,
              category: RoutineCategory.language,
              authorId: 'instructor_loopi',
              authorName: 'LOOPI Coach',
              segments: const [
                RoutineSegment(id: 'seg_a', startSec: 0, endSec: 5, speed: 0.8, loopCount: 2),
                RoutineSegment(id: 'seg_b', startSec: 5, endSec: 10, speed: 1.0, loopCount: 2),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}
