// Placeholder Firebase options.
// Replace this file by running: dart pub global run flutterfire_cli:flutterfire configure
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDV2uSOB32CsdiPIFRTFL5vXO9SMPnLV-g',
    appId: '1:733409684438:web:9b107ad542d58686fb1277',
    messagingSenderId: '733409684438',
    projectId: 'loopi-app-6fdfe',
    authDomain: 'loopi-app-6fdfe.firebaseapp.com',
    storageBucket: 'loopi-app-6fdfe.firebasestorage.app',
  );

  static const FirebaseOptions android = web;
  static const FirebaseOptions ios = web;
}
