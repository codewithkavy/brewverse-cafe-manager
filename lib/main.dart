import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'firebase_runtime_config.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';
import 'widgets/firebase_connection_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const useEmulators = BrewVerseFirebaseConfig.useEmulators;
  final options = useEmulators
      ? DefaultFirebaseOptions.currentPlatform.copyWith(
          projectId: BrewVerseFirebaseConfig.emulatorProjectId,
        )
      : DefaultFirebaseOptions.currentPlatform;
  BrewVerseFirebaseConfig.validateOptions(options);
  await Firebase.initializeApp(
    name: useEmulators ? BrewVerseFirebaseConfig.localAppName : null,
    options: options,
  );

  if (useEmulators) {
    // Physical Android devices reach the laptop through USB adb reverse.
    // Android virtual devices can explicitly select 10.0.2.2 instead.
    const host = String.fromEnvironment(
      'BREWVERSE_FIREBASE_EMULATOR_HOST',
      defaultValue: '127.0.0.1',
    );
    const autoMap = false;

    await BrewVerseFirebaseConfig.auth.useAuthEmulator(
      host,
      9099,
      automaticHostMapping: autoMap,
    );
    BrewVerseFirebaseConfig.firestore.useFirestoreEmulator(
      host,
      8085,
      automaticHostMapping: autoMap,
    );
    BrewVerseFirebaseConfig.functions.useFunctionsEmulator(
      host,
      5001,
      automaticHostMapping: autoMap,
    );
    await BrewVerseFirebaseConfig.storage.useStorageEmulator(
      host,
      9199,
      automaticHostMapping: autoMap,
    );
  }

  runApp(const BrewVerseApp());
}

class BrewVerseApp extends StatelessWidget {
  const BrewVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewVerse Cafe Manager',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      builder: (context, child) => FirebaseConnectionScope(child: child!),
      darkTheme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}
