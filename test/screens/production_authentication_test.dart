import 'package:brewverse_cafe_manager/screens/account_security_screen.dart';
import 'package:brewverse_cafe_manager/screens/auth_gate.dart';
import 'package:brewverse_cafe_manager/screens/email_verification_gate.dart';
import 'package:brewverse_cafe_manager/screens/login_screen.dart';
import 'package:brewverse_cafe_manager/services/authentication_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'authentication_test.dart' show TestAuth;

class _Provider extends Fake implements UserInfo {
  _Provider(this.providerId);
  @override
  final String providerId;
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}

class _User extends Fake implements User {
  _User(
      {this.uid = 'owner', this.verified = false, this.provider = 'password'});
  @override
  final String uid;
  bool verified;
  final String provider;
  Object? tokenError, linkError;
  int links = 0, reauths = 0, tokenRefreshes = 0;
  @override
  bool get emailVerified => verified;
  @override
  String? get email => provider == 'password' ? 'owner@example.test' : null;
  @override
  String? get phoneNumber => null;
  @override
  List<UserInfo> get providerData => [_Provider(provider)];
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    tokenRefreshes++;
    if (tokenError != null) throw tokenError!;
    return 'test-token';
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
      AuthCredential credential) async {
    reauths++;
    return _Credential(this);
  }

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    links++;
    if (linkError != null) throw linkError!;
    return _Credential(this);
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  User? currentUser;
  int signIns = 0;
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signIns++;
    throw StateError('Linking must never sign in to another user');
  }
}

class _Security implements AccountSecurityService {
  _Security(this.currentUser);
  @override
  User? currentUser;
  int sends = 0, reauths = 0, links = 0;
  Object? error;
  bool verifyOnReload = false;
  @override
  Future<User?> reloadUser() async {
    if (verifyOnReload) (currentUser! as _User).verified = true;
    return currentUser;
  }

  @override
  Future<void> sendEmailVerification() async {
    sends++;
  }

  @override
  Future<void> reauthenticateEmail(String password) async {
    reauths++;
  }

  @override
  Future<void> linkPhoneCredential(PhoneAuthCredential credential,
      {required String expectedUid}) async {
    links++;
    if (error != null) throw error!;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }
}

void main() {
  test('verification applies only to unverified password identities', () {
    expect(requiresEmailVerification(_User()), isTrue);
    expect(requiresEmailVerification(_User(verified: true)), isFalse);
    expect(requiresEmailVerification(_User(provider: 'phone')), isFalse);
  });
  test(
      'phone linking requires verified email, recent password ownership and same UID',
      () async {
    final user = _User();
    final auth = _Auth(user);
    final service = FirebaseAccountSecurityService(auth: auth);
    final otp =
        PhoneAuthProvider.credential(verificationId: 'test', smsCode: '123456');
    await expectLater(
        service.linkPhoneCredential(otp, expectedUid: user.uid),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'email-not-verified')));
    user.verified = true;
    await expectLater(
        service.linkPhoneCredential(otp, expectedUid: user.uid),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'requires-recent-login')));
    await service.reauthenticateEmail('local-test-password');
    await service.linkPhoneCredential(otp, expectedUid: user.uid);
    expect(user.links, 1);
    expect(user.reauths, 1);
    expect(auth.signIns, 0);
    expect(auth.currentUser!.uid, user.uid);
    await expectLater(service.linkPhoneCredential(otp, expectedUid: user.uid),
        throwsA(isA<FirebaseAuthException>()));
    auth.currentUser = _User(uid: 'other', verified: true);
    await expectLater(
        service.linkPhoneCredential(otp, expectedUid: user.uid),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'session-changed')));
  });
  test('existing phone credential conflict never signs in or merges an account',
      () async {
    final user = _User(verified: true)
      ..linkError = FirebaseAuthException(code: 'credential-already-in-use');
    final auth = _Auth(user);
    final service = FirebaseAccountSecurityService(auth: auth);
    await service.reauthenticateEmail('local-test-password');
    await expectLater(
        service.linkPhoneCredential(
            PhoneAuthProvider.credential(
                verificationId: 'test', smsCode: '123456'),
            expectedUid: user.uid),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'credential-already-in-use')));
    expect(user.links, 1);
    expect(auth.signIns, 0);
    expect(auth.currentUser!.uid, 'owner');
    expect(authenticationError(user.linkError!),
        contains('No accounts were merged'));
  });
  testWidgets(
      'cloud email gate resends once then opens verified session after refresh',
      (tester) async {
    final user = _User(), security = _Security(_User());
    security.currentUser = user;
    await tester.pumpWidget(MaterialApp(
        home: EmailVerificationGate(
            user: user,
            security: security,
            child: const Text('Café workspace'))));
    expect(find.text('Café workspace'), findsNothing);
    await tester.tap(find.text('Resend verification email'));
    await tester.pump();
    expect(security.sends, 1);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Wait 30 seconds to resend'))
            .onPressed,
        isNull);
    security.verifyOnReload = true;
    await tester.tap(find.text('I verified my email'));
    await tester.pumpAndSettle();
    expect(find.text('Café workspace'), findsOneWidget);
    expect(user.tokenRefreshes, 1);
    await tester.pumpWidget(const SizedBox());
  });
  for (final code in [
    'network-request-failed',
    'unavailable',
    'user-disabled',
    'user-token-expired'
  ]) {
    testWidgets('cached session fallback is limited to network failure: $code',
        (tester) async {
      final user = _User()..tokenError = FirebaseAuthException(code: code);
      await tester.pumpWidget(MaterialApp(
          home: VerifiedSessionGate(
              user: user, child: const Text('Cached workspace'))));
      await tester.pumpAndSettle();
      expect(
          find.text('Cached workspace'),
          ['network-request-failed', 'unavailable'].contains(code)
              ? findsOneWidget
              : findsNothing);
    });
  }
  testWidgets(
      'phone linking UI accepts OTP only through link operation and reports conflict',
      (tester) async {
    final auth = TestAuth(), security = _Security(_User(verified: true));
    security.error = FirebaseAuthException(code: 'credential-already-in-use');
    await tester.pumpWidget(MaterialApp(
        home: AccountSecurityScreen(security: security, authentication: auth)));
    await tester.enterText(
        find.widgetWithText(TextField, 'Current email password'),
        'local-test-password');
    await tester.ensureVisible(find.text('Verify and link phone'));
    await tester.tap(find.text('Verify and link phone'));
    await tester.pumpAndSettle();
    expect(security.reauths, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'), '+919876543210');
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    auth.sent!('test', 1);
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, '6-digit SMS code'), '123456');
    await tester.ensureVisible(find.text('Verify and link phone'));
    await tester.tap(find.text('Verify and link phone'));
    await tester.pump();
    expect(security.links, 1);
    expect(auth.verifies, 0);
    expect(find.textContaining('No accounts were merged'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
