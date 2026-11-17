// Generated from android/app/google-services.json (project project-attendance-app).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Optic is set up for Android only.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAwo82eDOdSE2YPBAPGjRfu28HxUf1KRoE',
    appId: '1:282213766426:android:b75bdac2b6baaf3c4848a3',
    messagingSenderId: '282213766426',
    projectId: 'project-attendance-app',
    storageBucket: 'project-attendance-app.firebasestorage.app',
  );
}
