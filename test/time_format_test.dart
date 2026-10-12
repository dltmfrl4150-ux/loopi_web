import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/time_format.dart';

void main() {
  test('1-2 digits are seconds', () {
    expect(parseTimeInput('5'), 5);
    expect(formatMmSs(parseTimeInput('5')!), '00:05');
    expect(parseTimeInput('20'), 20);
    expect(formatMmSs(parseTimeInput('20')!), '00:20');
    expect(parseTimeInput('45'), 45);
  });

  test('3+ digits parse minutes from the front, seconds from the rear', () {
    expect(parseTimeInput('120'), 80);
    expect(formatMmSs(parseTimeInput('120')!), '01:20');
    expect(parseTimeInput('130'), 90);
    expect(parseTimeInput('0100'), 60);
    expect(formatMmSs(parseTimeInput('0100')!), '01:00');
    expect(parseTimeInput('0219'), 139);
    expect(formatMmSs(parseTimeInput('0219')!), '02:19');
    expect(parseTimeInput('1144'), 704);
    expect(formatMmSs(parseTimeInput('1144')!), '11:44');
    expect(parseTimeInput('11144'), 6704);
    expect(formatMmSs(parseTimeInput('11144')!), '111:44');
  });

  test('colons are stripped before rear parsing', () {
    expect(parseTimeInput('1:00'), 60);
    expect(parseTimeInput('01:00'), 60);
    expect(parseTimeInput('2:19'), 139);
    expect(parseTimeInput('111:44'), 6704);
    expect(formatMmSs(parseTimeInput('111:44')!), '111:44');
    // "1:70" → digits "170" → 1*60+70 = 130 → display 02:10
    expect(parseTimeInput('1:70'), 130);
    expect(formatMmSs(parseTimeInput('1:70')!), '02:10');
  });

  test('durations over 99 minutes use uncapped MMM:SS', () {
    expect(formatMmSs(7497), '124:57');
    expect(parseTimeInput('124:57'), 7497);
    expect(formatMmSs(parseTimeInput('124:57')!), '124:57');
    expect(parseTimeInput('12457'), 7497);
    expect(formatMmSs(6000), '100:00');
  });
}
