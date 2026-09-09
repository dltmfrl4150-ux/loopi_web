import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/time_format.dart';

void main() {
  test('digit strings parse as MMSS not raw seconds', () {
    expect(parseTimeInput('0100'), 60);
    expect(formatMmSs(parseTimeInput('0100')!), '01:00');
    expect(parseTimeInput('0219'), 139);
    expect(formatMmSs(parseTimeInput('0219')!), '02:19');
    expect(parseTimeInput('45'), 45);
    expect(parseTimeInput('130'), 90);
  });

  test('colon strings and seconds rollover', () {
    expect(parseTimeInput('1:00'), 60);
    expect(parseTimeInput('01:00'), 60);
    expect(parseTimeInput('2:19'), 139);
    expect(parseTimeInput('1:70'), 130);
    expect(formatMmSs(parseTimeInput('1:70')!), '02:10');
  });
}
