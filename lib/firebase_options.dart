// Placeholder file for FirebaseOptions.
// Replace the values below with the generated Firebase configuration from the Firebase CLI.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not configured for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAaiIgneRqqv_XXfIGnQq5yUSFLUeR1DbA',
    appId: '1:653606651189:web:5dcef33ed641070d5f787c',
    messagingSenderId: '653606651189',
    projectId: 'horsens-freja-materialer',
    authDomain: 'horsens-freja-materialer.firebaseapp.com',
    storageBucket: 'horsens-freja-materialer.firebasestorage.app',
    measurementId: 'G-EX2DSKNJM4',
  );
}
