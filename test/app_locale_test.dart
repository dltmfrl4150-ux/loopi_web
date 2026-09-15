import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/utils/app_locale.dart';

void main() {
  test('resolveAppLocale prefers supported language codes', () {
    expect(resolveAppLocale(const Locale('ko', 'KR')), const Locale('ko'));
    expect(resolveAppLocale(const Locale('en', 'US')), const Locale('en'));
  });

  test('resolveAppLocale falls back to English for unsupported', () {
    expect(resolveAppLocale(const Locale('fr')), const Locale('en'));
    expect(resolveAppLocale(const Locale('es', 'ES')), const Locale('en'));
    expect(resolveAppLocale(null), const Locale('en'));
  });
}