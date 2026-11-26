// Axis Optic (axis-optic-ce4f2), Console's own Firebase project.
// setup_console.command rewrites this from android/app/google-services.json
// after registering Console's Android app there. Run it once.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Console is set up for Android only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBRTTfb9zAAwVT02v-Dk4tV0EbU_iLNTFo',
    appId: '1:139844049918:android:8688b3ba424b1590033eaf',
    messagingSenderId: '139844049918',
    projectId: 'axis-optic-ce4f2',
    storageBucket: 'axis-optic-ce4f2.firebasestorage.app',
  );
}
