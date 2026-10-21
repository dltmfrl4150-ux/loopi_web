import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/routine_share_url.dart';

void main() {
  test('share URLs are unique per community post id', () {
    final base = Uri.parse('https://loopi-app-6fdfe.web.app/');
    expect(
      communityRoutineShareUrl('cpost_aaa', base: base),
      'https://loopi-app-6fdfe.web.app/r/cpost_aaa',
    );
    expect(
      communityRoutineShareUrl('cpost_bbb', base: base),
      'https://loopi-app-6fdfe.web.app/r/cpost_bbb',
    );
    expect(
      communityRoutineShareUrl('cpost_aaa', base: base),
      isNot(communityRoutineShareUrl('cpost_bbb', base: base)),
    );
  });

  test('parser reads path and hash share links', () {
    expect(
      parseCommunityRoutineShareId(Uri.parse('https://loopi-app-6fdfe.web.app/r/cpost_1')),
      'cpost_1',
    );
    expect(
      parseCommunityRoutineShareId(Uri.parse('https://loopi-app-6fdfe.web.app/#/r/cpost_2')),
      'cpost_2',
    );
    expect(
      parseCommunityRoutineShareId(Uri.parse('https://loopi-app-6fdfe.web.app/')),
      isNull,
    );
    expect(
      parseCommunityRoutineShareId(Uri.parse('https://loopi-app-6fdfe.web.app/home')),
      isNull,
    );
  });
}
