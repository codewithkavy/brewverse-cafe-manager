import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Local development must never silently fall back to the production project.
/// Release behavior remains controlled by the existing compile-time flags.
abstract final class BrewVerseFirebaseConfig {
  static const productionProjectId = 'brewverse-593dc';
  static const emulatorProjectId = 'brewverse-security-tests';
  static const localAppName = 'brewverse-local';
  static const functionsRegion = 'us-central1';
  static const useEmulators = !kReleaseMode &&
      bool.fromEnvironment('BREWVERSE_USE_FIREBASE_EMULATORS',
          defaultValue: true);
  // Tenant authorization must never fall back to the unscoped legacy workspace.
  static const tenantMode = true;

  static void validateOptions(FirebaseOptions options) {
    final expected = useEmulators ? emulatorProjectId : productionProjectId;
    if (options.projectId != expected) {
      throw StateError(
          'Firebase project does not match the selected environment.');
    }
  }

  // Android auto-creates [DEFAULT] from google-services.json. FlutterFire can
  // reuse it even when initializeApp receives a different projectId. A named
  // local app prevents that production registration from choosing RPC routes.
  static FirebaseApp get app =>
      useEmulators ? Firebase.app(localAppName) : Firebase.app();
  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  static FirebaseFirestore get firestore =>
      FirebaseFirestore.instanceFor(app: app);
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(app: app, region: functionsRegion);
  static FirebaseStorage get storage => FirebaseStorage.instanceFor(app: app);
}
