import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/routine_share_pending.dart';
import 'package:loopi_web/utils/routine_share_url.dart';

void main() {
  setUp(RoutineSharePending.clear);

  test('pending id survives until cleared and prefers first capture', () {
    RoutineSharePending.capture('cpost_first');
    RoutineSharePending.capture('cpost_second');
    expect(RoutineSharePending.postId, 'cpost_first');
    expect(RoutineSharePending.resolve(), 'cpost_first');
    RoutineSharePending.clear();
    expect(RoutineSharePending.postId, isNull);
  });

  test('share origin follows the current http host', () {
    expect(
      communityRoutineShareUrl(
        'cpost_1',
        base: Uri.parse('http://localhost:62001/'),
      ),
      'http://localhost:62001/r/cpost_1',
    );
    expect(
      communityRoutineShareUrl(
        'cpost_1',
        base: Uri.parse('https://loopi-app-6fdfe.web.app/'),
      ),
      'https://loopi-app-6fdfe.web.app/r/cpost_1',
    );
  });

  test('parser still reads /r ids used by deep links', () {
    expect(
      parseCommunityRoutineShareId(
        Uri.parse('http://localhost:62001/r/cpost_1792549778938000'),
      ),
      'cpost_1792549778938000',
    );
  });
}
