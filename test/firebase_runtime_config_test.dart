import 'package:brewverse_cafe_manager/firebase_runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';

void main() {
  test('local builds always select tenant mode and Firebase emulators', () {
    expect(
        BrewVerseFirebaseConfig.useEmulators,
        const bool.fromEnvironment('BREWVERSE_USE_FIREBASE_EMULATORS',
            defaultValue: true));
    expect(BrewVerseFirebaseConfig.tenantMode, isTrue);
  });
  test('wrong-project Firebase options fail closed', () {
    expect(
        () => BrewVerseFirebaseConfig.validateOptions(const FirebaseOptions(
              apiKey: 'test',
              appId: 'test',
              messagingSenderId: 'test',
              projectId: 'wrong-project',
            )),
        throwsStateError);
  });
}
