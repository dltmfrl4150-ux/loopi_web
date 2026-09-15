import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:easy_localization/easy_localization.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'state/routine_library.dart';
import 'state/user_state.dart';
import 'theme/loopi_colors.dart';
import 'utils/app_locale.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseBootstrap.initialized = true;
  } catch (error) {
    debugPrint('Firebase initialization skipped: $error');
    FirebaseBootstrap.initialized = false;
  }
  runApp(
    EasyLocalization(
      supportedLocales: kSupportedAppLocales,
      path: 'assets/translations',
      fallbackLocale: kFallbackAppLocale,
      // Detect browser/OS language; unsupported codes fall back to English.
      startLocale: detectSystemAppLocale(),
      useOnlyLangCode: true,
      // Avoid persisting a forced locale so cold starts follow the system
      // language (clears the effect of a legacy SharedPreferences "en").
      saveLocale: false,
      child: const LoopiApp(),
    ),
  );
}

class LoopiApp extends StatefulWidget {
  const LoopiApp({super.key});

  @override
  State<LoopiApp> createState() => _LoopiAppState();
}

class _LoopiAppState extends State<LoopiApp> {
  final RoutineLibrary _library = RoutineLibrary();
  final UserSubscriptionState _userState = UserSubscriptionState();

  @override
  void initState() {
    super.initState();
    _library.load();
  }

  @override
  Widget build(BuildContext context) {
    final localization = EasyLocalization.of(context);
    final delegates = localization?.delegates ??
        const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ];
    final supportedLocales =
        localization?.supportedLocales ?? kSupportedAppLocales;
    final locale = localization?.locale ?? detectSystemAppLocale();

    return MaterialApp(
      title: 'LOOPI',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: delegates,
      supportedLocales: supportedLocales,
      locale: locale,
      localeResolutionCallback: (deviceLocale, supported) {
        return resolveAppLocale(deviceLocale);
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: LoopiColors.purple),
        useMaterial3: true,
        scaffoldBackgroundColor: LoopiColors.canvas,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: LoopiColors.purple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: LoopiColors.darkCanvas,
        canvasColor: LoopiColors.darkCanvas,
      ),
      themeMode: ThemeMode.system,
      home: AuthGate(library: _library, userState: _userState),
    );
  }
}