import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'package:loopi_web/widgets/youtube_safe_dialog.dart';

void main() {
  testWidgets('interceptor covers the screen and the dialog is painted after the scrim', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    final future = showYoutubeSafeDialog<bool>(
      context: tester.element(find.byType(Scaffold)),
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: const Text('저장하려면 회원가입이 필요합니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('회원가입하기'),
            ),
          ],
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final interceptor = find.byType(PointerInterceptor);
    expect(interceptor, findsOneWidget);

    final barrier = find.descendant(
      of: interceptor,
      matching: find.byType(ModalBarrier),
    );
    expect(barrier, findsOneWidget);
    expect(tester.widget<ModalBarrier>(barrier).dismissible, isFalse);

    final stack = tester.element(barrier).findAncestorWidgetOfExactType<Stack>()!;
    expect(stack.children.first, isA<ModalBarrier>());
    expect(stack.children.last, isA<SafeArea>());

    final button = find.widgetWithText(TextButton, '회원가입하기');
    expect(find.descendant(of: interceptor, matching: button), findsOneWidget);

    final interceptorRect = tester.getRect(interceptor);
    final buttonRect = tester.getRect(button);
    expect(interceptorRect, const Rect.fromLTRB(0, 0, 800, 600));
    expect(interceptorRect.width, greaterThan(buttonRect.width));
    expect(interceptorRect.height, greaterThan(buttonRect.height));
    expect(interceptorRect.contains(buttonRect.center), isTrue);
    expect(buttonRect.contains(const Offset(8, 8)), isFalse);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(find.text('회원가입하기'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(await future, isTrue);
  });

  testWidgets('outside tap closes only a dismissible dialog', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    final future = showYoutubeSafeDialog<bool>(
      context: tester.element(find.byType(Scaffold)),
      barrierDismissible: true,
      builder: (dialogContext) {
        return const AlertDialog(content: Text('저장된 루틴 불러오기'));
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final barrier = tester.widget<ModalBarrier>(
      find.descendant(
        of: find.byType(PointerInterceptor),
        matching: find.byType(ModalBarrier),
      ),
    );
    expect(barrier.dismissible, isTrue);

    final interceptorRect = tester.getRect(find.byType(PointerInterceptor));
    expect(interceptorRect, const Rect.fromLTRB(0, 0, 800, 600));
    expect(interceptorRect.contains(const Offset(8, 8)), isTrue);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('저장된 루틴 불러오기'), findsNothing);
    expect(await future, isNull);
  });
}
