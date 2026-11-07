import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

abstract final class BrewVerseFirebaseConfig {
  static late FirebaseApp app;
  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(app: app, region: 'us-central1');
  static Future<void> initialize() async {
    if (!{'127.0.0.1', 'localhost'}.contains(Uri.base.host)) {
      throw StateError('Development dashboard requires loopback.');
    }
    app = await Firebase.initializeApp(
      name: 'brewverse-local',
      options: const FirebaseOptions(
        apiKey: 'local-emulator-only-key',
        appId: '1:123456789:web:brewverseadmin',
        messagingSenderId: '123456789',
        projectId: 'brewverse-security-tests',
      ),
    );
    await auth.useAuthEmulator('127.0.0.1', 13198, automaticHostMapping: false);
    functions.useFunctionsEmulator(
      '127.0.0.1',
      13101,
      automaticHostMapping: false,
    );
    await auth.setPersistence(Persistence.SESSION);
  }
}

abstract interface class AdminApi {
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]);
}

class FirebaseAdminApi implements AdminApi {
  @override
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final result = await BrewVerseFirebaseConfig.functions
        .httpsCallable(name)
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }
}

String money(dynamic value) =>
    '₹${((value as num? ?? 0) / 100).toStringAsFixed(2)}';
String dateLabel(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? 'Not activated'
      : '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String errorText(Object e) => e is FirebaseFunctionsException
    ? e.message ?? e.code
    : e is FirebaseAuthException
    ? e.message ?? e.code
    : '$e';
