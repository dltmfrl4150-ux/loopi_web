import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loopi_web/main.dart';
import 'package:loopi_web/models/community_models.dart';
import 'package:loopi_web/models/routine_category.dart';
import 'package:loopi_web/models/routine_models.dart';
import 'package:loopi_web/screens/home_dashboard_screen.dart';
import 'package:loopi_web/state/routine_library.dart';
import 'package:loopi_web/state/user_state.dart';
import 'package:loopi_web/widgets/app_logo.dart';
import 'package:loopi_web/widgets/save_routine_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Social login is the initial screen', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('ko'),
        child: const LoopiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppLogo), findsWidgets);
    expect(find.text('유튜브 구간 반복 학습 루틴'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('구글로 시작하기'), findsOneWidget);
    expect(find.text('애플로 시작하기'), findsOneWidget);
    expect(find.text('게스트로 둘러보기'), findsOneWidget);

    await tester.ensureVisible(find.text('게스트로 둘러보기'));
    await tester.tap(find.text('게스트로 둘러보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('새 루틴 만들기'), findsOneWidget);
    expect(find.text('최근 연습한 루틴'), findsOneWidget);
  });

  testWidgets('Save Routine dialog clears default name on first focus', (WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: const MaterialApp(
          home: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final future = showSaveRoutineDialog(tester.element(find.byType(Scaffold)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('studio.save_dialog_title'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, defaultRoutineName());

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.controller!.text, isEmpty);

    await tester.enterText(find.byType(TextField), 'Hip Hop Routine');
    await tester.tap(find.widgetWithText(FilledButton, 'studio.save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final result = await future;
    expect(result, isNotNull);
    expect(result!.name, 'Hip Hop Routine');
    expect(result.overwrite, isFalse);
    expect(result.category, 'dance');
  });

  test('Routine category normalize supports other', () {
    expect(RoutineCategory.normalize('other'), 'other');
    expect(RoutineCategory.normalize('기타'), 'other');
    expect(RoutineCategory.queryValue('other'), 'other');
    expect(RoutineCategory.matches('other', 'other'), isTrue);
    expect(RoutineCategory.matches('dance', 'other'), isFalse);
  });

  test('Routine segment highlight serializes for Firestore and defaults to false', () {
    final legacy = RoutineSegment.fromJson({
      'id': 's1',
      'startSec': 0,
      'endSec': 8,
    });
    expect(legacy.isHighlight, isFalse);

    final tagged = RoutineSegment(
      id: 's2',
      startSec: 12,
      endSec: 20,
      isHighlight: true,
    );
    final json = tagged.toJson();
    expect(json['isHighlight'], isTrue);
    expect(RoutineSegment.fromJson(json).isHighlight, isTrue);

    final routine = SavedRoutine(
      id: 'r-highlight',
      name: 'Chorus',
      videoUrl: '',
      videoId: '',
      segments: [legacy, tagged],
      createdAt: DateTime(2026, 1, 1),
    );
    expect(routine.hasHighlight, isTrue);
    expect(routine.highlightIndex, 1);
    expect(routine.toFirestoreJson()['segments'][1]['isHighlight'], isTrue);
  });

  test('Saved routine and showcase default missing category to dance', () {
    final routine = SavedRoutine.fromJson({
      'id': 'r1',
      'name': 'Old routine',
      'videoUrl': '',
      'videoId': '',
      'segments': const [],
      'createdAt': DateTime(2024, 1, 1).toIso8601String(),
    });
    expect(routine.category, 'dance');
    expect(routine.toJson()['category'], 'dance');
  });

  test('Practice result keeps the original loop range metadata on save and reload', () async {
    final result = PracticeResult(
      id: 'practice_1',
      name: 'Practice 1',
      routineId: 'routine_1',
      createdAt: DateTime(2024, 8, 31, 10, 0),
      startTime: 12.5,
      endTime: 18.75,
    );

    final json = result.toJson();
    final reloaded = PracticeResult.fromJson(json);

    expect(reloaded.startTime, 12.5);
    expect(reloaded.endTime, 18.75);
    expect(reloaded.intervalMarkers, isEmpty);
    expect(reloaded.isAudioRecording, isFalse);
  });

  test('Practice result infers audio recordings from path and flag', () {
    final audio = PracticeResult(
      id: 'a1',
      name: 'Voice',
      routineId: 'r1',
      createdAt: DateTime(2026, 1, 1),
      recordedPath: 'blob:audio.m4a',
      isAudioRecording: true,
    );
    expect(audio.toJson()['isAudioRecording'], isTrue);
    expect(PracticeResult.fromJson(audio.toJson()).isAudioRecording, isTrue);
    expect(
      PracticeResult.fromJson({
        'id': 'a2',
        'name': 'Voice',
        'routineId': 'r1',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'recordedPath': 'clip.wav',
      }).isAudioRecording,
      isTrue,
    );
  });

  test('Showcase playableUrl prefers remote videoUrl and treats blob paths as unplayable', () {
    final blobOnly = CommunityShowcaseItem(
      id: 's1',
      title: 'Audio',
      authorId: 'u1',
      authorName: 'Loopi',
      createdAt: DateTime(2026, 1, 1),
      mediaKind: ShowcaseMediaKind.audio,
      likesCount: 0,
      likedBy: const [],
      recordedPath: 'blob:https://localhost/abc',
    );
    expect(blobOnly.playableUrl, isNull);
    expect(isRemotePlayableUrl(blobOnly.recordedPath), isFalse);

    final uploaded = CommunityShowcaseItem.fromJson({
      'id': 's2',
      'title': 'Audio',
      'authorId': 'u1',
      'authorName': 'Loopi',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'mediaKind': 'audio',
      'likesCount': 0,
      'likedBy': const [],
      'videoUrl': 'https://firebasestorage.googleapis.com/v0/b/app/o/a.wav',
      'recordedPath': 'https://firebasestorage.googleapis.com/v0/b/app/o/a.wav',
    });
    expect(uploaded.playableUrl, contains('firebasestorage.googleapis.com'));
    expect(uploaded.videoUrl, uploaded.recordedPath);
    expect(
      inferMediaKindFromPath('blob:https://app/uuid', audioHint: true),
      ShowcaseMediaKind.audio,
    );
    expect(
      inferMediaKindFromPath('blob:https://app/uuid', fallback: ShowcaseMediaKind.audio),
      ShowcaseMediaKind.audio,
    );
  });

  testWidgets('Home dashboard View All switches to the library tab', (WidgetTester tester) async {
    final library = RoutineLibrary();
    await library.load();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('ko'),
        child: MaterialApp(
          home: HomeDashboardScreen(library: library, userState: UserSubscriptionState()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 0);

    await tester.tap(find.widgetWithText(TextButton, '전체 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final updatedNav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(updatedNav.selectedIndex, 4);
  });

  test('Routine library creates and persists groups with ordered routine ids', () async {
    final library = RoutineLibrary();
    await library.load();

    final r1 = SavedRoutine(
      id: 'r1',
      name: 'Warm Up',
      videoUrl: 'https://youtube.com/watch?v=aaa',
      videoId: 'aaa',
      segments: const [
        RoutineSegment(
          id: 's1',
          startSec: 0,
          endSec: 10,
          speed: 1,
          loopCount: 1,
          delaySec: 1,
        ),
      ],
      createdAt: DateTime.now(),
    );
    final r2 = SavedRoutine(
      id: 'r2',
      name: 'Stretch',
      videoUrl: 'https://youtube.com/watch?v=bbb',
      videoId: 'bbb',
      segments: const [
        RoutineSegment(
          id: 's2',
          startSec: 0,
          endSec: 15,
          speed: 1,
          loopCount: 1,
          delaySec: 2,
        ),
      ],
      createdAt: DateTime.now(),
    );

    await library.save(r1);
    await library.save(r2);
    await library.createGroup(name: 'Mobility', routineIds: [r1.id, r2.id]);

    expect(library.groups, hasLength(1));
    expect(library.groups.first.title, 'Mobility');
    expect(library.groups.first.routineIds, [r1.id, r2.id]);
    expect(library.routinesForGroup(library.groups.first), hasLength(2));

    final reloaded = RoutineLibrary();
    await reloaded.load();
    expect(reloaded.groups, hasLength(1));
    expect(reloaded.groups.first.title, 'Mobility');
    expect(reloaded.routinesForGroup(reloaded.groups.first).map((e) => e.id), [r1.id, r2.id]);
  });
}
