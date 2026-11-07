import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_runtime_config.dart';
import 'cafe_workspace_gate.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'email_verification_gate.dart';

class AuthGate extends StatelessWidget {
  const AuthGate(
      {super.key, this.sessions, this.signedInBuilder, this.signedOutBuilder});
  final Stream<User?>? sessions;
  final Widget Function(BuildContext, User)? signedInBuilder;
  final WidgetBuilder? signedOutBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: sessions ?? BrewVerseFirebaseConfig.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          final custom = signedInBuilder;
          if (custom != null) {
            return SessionNavigationBoundary(
                key: ValueKey(snapshot.data!.uid),
                child: custom(context, snapshot.data!));
          }
          if (BrewVerseFirebaseConfig.tenantMode) {
            return SessionNavigationBoundary(
                key: ValueKey(snapshot.data!.uid),
                child: VerifiedSessionGate(
                    user: snapshot.data!,
                    child: BrewVerseFirebaseConfig.useEmulators
                        ? CafeWorkspaceGate(
                            key: ValueKey(snapshot.data!.uid),
                            uid: snapshot.data!.uid,
                          )
                        : EmailVerificationGate(
                            user: snapshot.data!,
                            child: CafeWorkspaceGate(
                              key: ValueKey(snapshot.data!.uid),
                              uid: snapshot.data!.uid,
                            ),
                          )));
          }
          return SessionNavigationBoundary(
              key: ValueKey(snapshot.data!.uid), child: const HomeScreen());
        }

        return SessionNavigationBoundary(
            key: const ValueKey('signed-out'),
            child: signedOutBuilder?.call(context) ?? const LoginScreen());
      },
    );
  }
}

/// Discards the entire private route stack when the identity changes. Dialogs
/// accidentally opened on the root navigator are removed on that transition too.
class SessionNavigationBoundary extends StatefulWidget {
  const SessionNavigationBoundary({required this.child, super.key});
  final Widget child;
  @override
  State<SessionNavigationBoundary> createState() =>
      _SessionNavigationBoundaryState();
}

class _SessionNavigationBoundaryState extends State<SessionNavigationBoundary> {
  NavigatorState? _root;
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _root = Navigator.maybeOf(context, rootNavigator: true);
  }

  @override
  void dispose() {
    final root = _root;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (root?.mounted ?? false) root!.popUntil((route) => route.isFirst);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
      onPopWithResult: (_) => _navigatorKey.currentState!.maybePop(),
      child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => widget.child)));
}

// Validate persisted credentials before opening a tenant workspace. A restarted
// Auth emulator can invalidate a cached refresh token without clearing the user.
class VerifiedSessionGate extends StatefulWidget {
  const VerifiedSessionGate(
      {required this.user, required this.child, super.key});
  final User user;
  final Widget child;

  @override
  State<VerifiedSessionGate> createState() => _VerifiedSessionState();
}

class _VerifiedSessionState extends State<VerifiedSessionGate> {
  late Future<String?> _token = widget.user.getIdToken(true);

  @override
  void didUpdateWidget(covariant VerifiedSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _token = widget.user.getIdToken(true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _token,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          // Network loss may use the already-persisted identity for cached
          // reads. The app-wide connection guard labels cache and blocks writes.
          final error = snapshot.error;
          final offline = error is FirebaseAuthException &&
              const {'network-request-failed', 'unavailable'}
                  .contains(error.code);
          if (offline) return widget.child;
          if (snapshot.hasError || snapshot.data == null) {
            return Scaffold(
                body: Center(
                    child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Could not verify your session. Check your connection, '
                    'or sign out and sign in again if your session has expired.'),
                TextButton(
                    onPressed: () => setState(() {
                          _token = widget.user.getIdToken(true);
                        }),
                    child: const Text('Retry connection')),
                TextButton(
                    onPressed: () async {
                      await BrewVerseFirebaseConfig.auth.signOut();
                    },
                    child: const Text('Sign out and sign in again')),
              ]),
            )));
          }
          return widget.child;
        },
      );
}
