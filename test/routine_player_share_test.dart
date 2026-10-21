import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:loopi_web/models/routine_models.dart';
import 'package:loopi_web/screens/routine_player_screen.dart';
import 'package:loopi_web/state/routine_library.dart';
import 'package:loopi_web/utils/routine_share_url.dart';

SavedRoutine _sampleRoutine({required String id, required String name}) {
  return SavedRoutine(
    id: id,
    name: name,
    videoUrl: 'https://www.youtube.com/watch?v=M7lc1UVf-VE',
    videoId: 'M7lc1UVf-VE',
    segments: const [
      RoutineSegment(id: 's1', startSec: 1, endSec: 5, speed: 0.75),
    ],
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('share button appears for community posts and copies unique URLs', (
    tester,
  ) async {
    final library = RoutineLibrary();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>;
          copied.add(args['text'] as String);
          return null;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('ko'),
        startLocale: const Locale('ko'),
        child: MaterialApp(
          home: RoutinePlayerScreen(
            routine: _sampleRoutine(id: 'rtn_1', name: '루틴 A'),
            library: library,
            communityPostId: 'cpost_aaa',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final shareButton = find.byIcon(Icons.link);
    expect(shareButton, findsOneWidget);
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);

    await tester.tap(shareButton);
    await tester.pump();
    expect(copied.single, communityRoutineShareUrl('cpost_aaa'));
    expect(copied.single, contains('/r/cpost_aaa'));
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('ko'),
        startLocale: const Locale('ko'),
        child: MaterialApp(
          home: RoutinePlayerScreen(
            routine: _sampleRoutine(id: 'rtn_2', name: '루틴 B'),
            library: library,
            communityPostId: 'cpost_bbb',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.link));
    await tester.pump();
    expect(copied.last, communityRoutineShareUrl('cpost_bbb'));
    expect(copied.last, contains('/r/cpost_bbb'));
    expect(copied.first, isNot(copied.last));
  });

  testWidgets('library player without community id hides share button', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ko')],
        path: 'assets/translations',
        fallbackLocale: const Locale('ko'),
        startLocale: const Locale('ko'),
        child: MaterialApp(
          home: RoutinePlayerScreen(
            routine: _sampleRoutine(id: 'rtn_local', name: '내 루틴'),
            library: RoutineLibrary(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.link), findsNothing);
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
  });

  test('share URL builder rejects empty ids', () {
    expect(() => communityRoutineShareUrl(''), throwsArgumentError);
  });
}
