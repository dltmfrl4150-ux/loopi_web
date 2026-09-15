import 'dart:ui' show Locale, PlatformDispatcher;

/// Supported app languages. Keep in sync with EasyLocalization.supportedLocales.
const List<Locale> kSupportedAppLocales = [
  Locale('en'),
  Locale('ko'),
];

const Locale kFallbackAppLocale = Locale('en');

/// Picks the best app locale from a device/browser [locale].
///
/// Matches on [Locale.languageCode] only (e.g. `ko_KR` -> `ko`).
/// Unsupported languages fall back to English.
Locale resolveAppLocale(Locale? locale) {
  if (locale == null) return kFallbackAppLocale;
  final language = locale.languageCode.toLowerCase();
  for (final supported in kSupportedAppLocales) {
    if (supported.languageCode == language) {
      return supported;
    }
  }
  return kFallbackAppLocale;
}

/// Device/browser locale at startup (web-safe via [PlatformDispatcher]).
Locale detectSystemAppLocale() {
  return resolveAppLocale(PlatformDispatcher.instance.locale);
}
