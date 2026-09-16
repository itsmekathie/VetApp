// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDsZTS0IjKV5CYF8dSC9HCPM5aWM3WhkxE',
    appId: '1:1062974005434:android:5d1f26e5ea797541e82283',
    messagingSenderId: '1062974005434',
    projectId: 'my-petcare-app-2e4fe',
    storageBucket: 'my-petcare-app-2e4fe.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDsZTS0IjKV5CYF8dSC9HCPM5aWM3WhkxE',
    appId: '1:1062974005434:android:5d1f26e5ea797541e82283',
    messagingSenderId: '1062974005434',
    projectId: 'my-petcare-app-2e4fe',
    storageBucket: 'my-petcare-app-2e4fe.firebasestorage.app',
    databaseURL: 'https://my-petcare-app-2e4fe-default-rtdb.firebaseio.com',
  );
}
