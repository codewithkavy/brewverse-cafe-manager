import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cafe_workspace_gate.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          if (const bool.fromEnvironment('BREWVERSE_TENANT_MODE')) {
            const useEmulators =
                bool.fromEnvironment('BREWVERSE_USE_FIREBASE_EMULATORS');
            const allowLiveTenantMode =
                bool.fromEnvironment('BREWVERSE_ALLOW_LIVE_TENANT_MODE');
            if (!useEmulators && !allowLiveTenantMode) {
              return const _TenantModeSafetyScreen();
            }
            return CafeWorkspaceGate(uid: snapshot.data!.uid);
          }
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

class _TenantModeSafetyScreen extends StatelessWidget {
  const _TenantModeSafetyScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Tenant mode is restricted to local Firebase emulators until '
              'the backend and migration have been reviewed. Start the '
              'isolated BrewVerse emulator suite and enable '
              'BREWVERSE_USE_FIREBASE_EMULATORS to preview it.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
