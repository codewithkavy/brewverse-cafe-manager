import 'dart:async';

import 'package:flutter/material.dart';

import 'backend.dart';
import 'dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await BrewVerseFirebaseConfig.initialize();
    runApp(const AdminApp());
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Dashboard unavailable: ${errorText(e)}')),
        ),
      ),
    );
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BrewVerse · Super Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff165c50)),
      scaffoldBackgroundColor: const Color(0xfff4f6f3),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(elevation: 0),
    ),
    home: StreamBuilder(
      stream: BrewVerseFirebaseConfig.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null
            ? const LoginScreen()
            : AuthorizationGate(api: FirebaseAdminApi());
      },
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await BrewVerseFirebaseConfig.auth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.coffee_rounded,
                    size: 44,
                    color: Color(0xff165c50),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BrewVerse',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'Super Admin · local development',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Admin email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) {
                      if (!busy) login();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  FilledButton(
                    onPressed: busy ? null : login,
                    child: Text(busy ? 'Signing in…' : 'Sign in'),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Authorized administrators only. Accounts and platform access are provisioned by trusted operators. No public admin registration.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthorizationGate extends StatefulWidget {
  const AuthorizationGate({required this.api, super.key});
  final AdminApi api;
  @override
  State<AuthorizationGate> createState() => _AuthorizationGateState();
}

class _AuthorizationGateState extends State<AuthorizationGate> {
  late Future<Map<String, dynamic>> check;
  @override
  void initState() {
    super.initState();
    check = widget.api.call('adminSession');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: check,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 44),
                  const Text('Administrator access could not be verified.'),
                  Text(errorText(snapshot.error!)),
                  FilledButton(
                    onPressed: () =>
                        setState(() => check = widget.api.call('adminSession')),
                    child: const Text('Retry authorization'),
                  ),
                  TextButton(
                    onPressed: () => BrewVerseFirebaseConfig.auth.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Dashboard(
        api: widget.api,
        onSignOut: () => BrewVerseFirebaseConfig.auth.signOut(),
      );
    },
  );
}
