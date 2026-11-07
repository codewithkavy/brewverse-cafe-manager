import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/screens/login_screen.dart';
import 'package:brewverse_cafe_manager/screens/auth_gate.dart';
import 'package:brewverse_cafe_manager/services/authentication_service.dart';
import 'package:brewverse_cafe_manager/widgets/sign_out_button.dart';

class TestAuth implements AuthenticationService {
  int resets = 0, emails = 0, requests = 0, verifies = 0;
  Completer<void>? pending;
  Object? error;
  PhoneCodeSent? sent;
  PhoneVerificationCompleted? completed;
  PhoneVerificationFailed? failed;
  Future<void> result() async {
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> emailSignIn(String email, String password,
      {bool register = false}) async {
    emails++;
    await result();
  }

  @override
  Future<void> resetPassword(String email) async {
    resets++;
    await result();
  }

  @override
  Future<void> signOut() => result();
  @override
  Future<void> sendPhoneCode(
      {required String phone,
      int? resendToken,
      required PhoneVerificationCompleted completed,
      required PhoneVerificationFailed failed,
      required PhoneCodeSent sent,
      required PhoneCodeAutoRetrievalTimeout timeout}) async {
    requests++;
    this.sent = sent;
    this.completed = completed;
    this.failed = failed;
  }

  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async {
    verifies++;
    await result();
  }

  @override
  Future<void> signInWithPhoneCredential(PhoneAuthCredential credential) async {
    verifies++;
    await result();
  }
}

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
}

Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
}

Future<void> login(WidgetTester t, TestAuth auth) async {
  await t.pumpWidget(MaterialApp(home: LoginScreen(authentication: auth)));
}

void main() {
  testWidgets('login remains usable on a narrow phone with enlarged text',
      (t) async {
    t.view.physicalSize = const Size(278, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: LoginScreen(authentication: TestAuth())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await tap(t, 'Phone OTP');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'password reset validates, prevents duplicate submits and confirms neutrally',
      (t) async {
    final a = TestAuth();
    await login(t, a);
    await tap(t, 'Forgot password?');
    expect(a.resets, 0);
    await t.enterText(find.byType(TextField).first, 'owner@example.test');
    a.pending = Completer<void>();
    await tap(t, 'Forgot password?');
    await tap(t, 'Forgot password?');
    expect(a.resets, 1);
    a.pending!.complete();
    await t.pumpAndSettle();
    expect(
        find.textContaining('If an account uses this email'), findsOneWidget);
  });
  testWidgets(
      'email authentication validates and displays network and credential errors',
      (t) async {
    final a = TestAuth();
    await login(t, a);
    await tap(t, 'Sign in');
    expect(a.emails, 0);
    await t.enterText(find.byType(TextField).first, 'owner@example.test');
    await t.enterText(find.byType(TextField).at(1), 'password');
    a.error = FirebaseAuthException(code: 'invalid-credential');
    await tap(t, 'Sign in');
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    a.error = FirebaseAuthException(code: 'network-request-failed');
    await tap(t, 'Forgot password?');
    expect(find.textContaining('Check your connection'), findsOneWidget);
    a.error = null;
    await tap(t, 'Sign in');
    expect(a.emails, 2);
  });
  testWidgets(
      'OTP validates number/code, throttles resend and catches expired codes',
      (t) async {
    final a = TestAuth();
    await login(t, a);
    await tap(t, 'Phone OTP');
    await tap(t, 'Send OTP');
    expect(a.requests, 0);
    await t.enterText(find.byType(TextField).first, '+919876543210');
    await tap(t, 'Send OTP');
    a.sent!('original', 1);
    await t.pump();
    await tap(t, 'Wait 30 seconds to resend');
    expect(a.requests, 1);
    await tap(t, 'Verify and sign in');
    expect(a.verifies, 0);
    await t.enterText(find.byType(TextField).last, '123456');
    a.error = FirebaseAuthException(code: 'session-expired');
    await tap(t, 'Verify and sign in');
    expect(find.textContaining('has expired'), findsOneWidget);
    a.error = null;
    await tap(t, 'Verify and sign in');
    expect(a.verifies, 2);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'late OTP callback after cancellation cannot sign in; request timeout recovers',
      (t) async {
    final a = TestAuth();
    await login(t, a);
    await tap(t, 'Phone OTP');
    await t.enterText(find.byType(TextField).first, '+919876543210');
    await tap(t, 'Send OTP');
    final stale = a.completed!;
    await tap(t, 'Cancel code request');
    stale(PhoneAuthProvider.credential(
        verificationId: 'late', smsCode: '123456'));
    await t.pump();
    expect(a.verifies, 0);
    await tap(t, 'Send OTP');
    await t.pump(const Duration(seconds: 61));
    expect(find.textContaining('SMS verification timed out'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'automatic OTP and manual verification cannot submit concurrently',
      (t) async {
    final a = TestAuth();
    await login(t, a);
    await tap(t, 'Phone OTP');
    await t.enterText(find.byType(TextField).first, '+919876543210');
    await tap(t, 'Send OTP');
    a.pending = Completer<void>();
    final credential =
        PhoneAuthProvider.credential(verificationId: 'id', smsCode: '123456');
    a.completed!(credential);
    a.completed!(credential);
    await t.pump();
    expect(a.verifies, 1);
    a.error = FirebaseAuthException(code: 'invalid-verification-code');
    a.pending!.complete();
    await t.pump();
    expect(find.textContaining('SMS code is incorrect'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'sign-out deduplicates submission and reports failure without leaving page',
      (t) async {
    int calls = 0;
    final done = Completer<void>();
    await t
        .pumpWidget(MaterialApp(home: Scaffold(body: SignOutButton(signOut: () {
      calls++;
      return done.future;
    }))));
    await tap(t, 'Sign out');
    await tap(t, 'Signing out…');
    expect(calls, 1);
    done.completeError(FirebaseAuthException(code: 'network-request-failed'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not sign out'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
  testWidgets('identity changes discard private routes and root dialogs',
      (t) async {
    final sessions = StreamController<User?>();
    await t.pumpWidget(MaterialApp(
        home: AuthGate(
            sessions: sessions.stream,
            signedOutBuilder: (_) => const Scaffold(body: Text('Public login')),
            signedInBuilder: (context, user) => Scaffold(
                body: Builder(
                    builder: (c) => Column(children: [
                          Text('Private ${user.uid}'),
                          TextButton(
                              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                      body: Builder(
                                          builder: (d) => TextButton(
                                              onPressed: () => showDialog<void>(
                                                  context: d,
                                                  builder: (_) =>
                                                      const AlertDialog(
                                                          title: Text(
                                                              'Private dialog'))),
                                              child: const Text(
                                                  'Private detail')))))),
                              child: const Text('Open detail')),
                        ]))))));
    sessions.add(TestUser('A'));
    await t.pumpAndSettle();
    await tap(t, 'Open detail');
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Private A'), findsOneWidget);
    expect(find.text('Private detail'), findsNothing);
    await tap(t, 'Open detail');
    await t.pumpAndSettle();
    await tap(t, 'Private detail');
    await t.pumpAndSettle();
    expect(find.text('Private dialog'), findsOneWidget);
    sessions.add(null);
    await t.pumpAndSettle();
    expect(find.text('Public login'), findsOneWidget);
    expect(find.text('Private dialog'), findsNothing);
    expect(find.text('Private detail'), findsNothing);
    sessions.add(TestUser('B'));
    await t.pumpAndSettle();
    expect(find.text('Private B'), findsOneWidget);
    expect(find.text('Private A'), findsNothing);
    await t.pumpWidget(const SizedBox());
    unawaited(sessions.close());
  });
}
