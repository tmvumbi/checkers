import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Hand-written Firebase config (project checkers-club) so no gradle
/// plugin or flutterfire CLI step is needed; values mirror
/// android/app/google-services.json and ios/Runner/GoogleService-Info.plist.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is configured for Android/iOS only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB03Hhi3ooOCdslihg1UcYk23fcsK2h9Sk',
    appId: '1:558217605941:android:a02ded512d0b9c455dd27c',
    messagingSenderId: '558217605941',
    projectId: 'checkers-club',
    storageBucket: 'checkers-club.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBv8qWns-Fj7rfOgRjw0qL4fvd3yjFbYgc',
    appId: '1:558217605941:ios:e5bce26a48359bcc5dd27c',
    messagingSenderId: '558217605941',
    projectId: 'checkers-club',
    storageBucket: 'checkers-club.firebasestorage.app',
    iosBundleId: 'club.contribution.checkers',
  );
}
