import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_runtime_config.dart';

abstract interface class AuthenticationService {
  Future<void> emailSignIn(String email, String password,
      {bool register = false});
  Future<void> resetPassword(String email);
  Future<void> signOut();
  Future<void> sendPhoneCode(
      {required String phone,
      int? resendToken,
      required PhoneVerificationCompleted completed,
      required PhoneVerificationFailed failed,
      required PhoneCodeSent sent,
      required PhoneCodeAutoRetrievalTimeout timeout});
  Future<void> verifyPhoneCode(String verificationId, String code);
  Future<void> signInWithPhoneCredential(PhoneAuthCredential credential);
}

class FirebaseAuthenticationService implements AuthenticationService {
  FirebaseAuth get _auth => BrewVerseFirebaseConfig.auth;
  @override
  Future<void> emailSignIn(String email, String password,
      {bool register = false}) async {
    if (register) {
      final result = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      // The account is created once. Verification failures remain retryable
      // from the signed-in verification screen without creating another user.
      if (!BrewVerseFirebaseConfig.useEmulators) {
        try {
          await result.user?.sendEmailVerification();
        } on FirebaseAuthException {
          // The verification gate exposes resend and its exact error.
        }
      }
    } else {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
    }
  }

  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> signOut() => _auth.signOut();
  @override
  Future<void> sendPhoneCode(
          {required String phone,
          int? resendToken,
          required PhoneVerificationCompleted completed,
          required PhoneVerificationFailed failed,
          required PhoneCodeSent sent,
          required PhoneCodeAutoRetrievalTimeout timeout}) =>
      _auth.verifyPhoneNumber(
          phoneNumber: phone,
          forceResendingToken: resendToken,
          verificationCompleted: completed,
          verificationFailed: failed,
          codeSent: sent,
          codeAutoRetrievalTimeout: timeout);
  @override
  Future<void> verifyPhoneCode(String verificationId, String code) =>
      signInWithPhoneCredential(PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: code));
  @override
  Future<void> signInWithPhoneCredential(PhoneAuthCredential credential) async {
    await _auth.signInWithCredential(credential);
  }
}

String authenticationError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'The email or password is incorrect.',
      'email-already-in-use' =>
        'This email is already registered. Sign in or reset your password.',
      'weak-password' =>
        'Choose a stronger password that meets the displayed requirements.',
      'requires-recent-login' =>
        'Sign in again before changing account security.',
      'credential-already-in-use' ||
      'account-exists-with-different-credential' =>
        'This phone number already belongs to another account. No accounts were merged. Sign in to that account or contact your café owner.',
      'provider-already-linked' =>
        'A phone number is already linked to this account.',
      'email-not-verified' =>
        'Verify your email before linking a phone number.',
      'session-changed' =>
        'Your signed-in account changed. Reopen account settings and try again.',
      'network-request-failed' =>
        'Cannot reach sign-in services. Check your connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait before trying again.',
      'invalid-phone-number' =>
        'Enter your phone number with its country code.',
      'invalid-verification-code' =>
        'The SMS code is incorrect. Check the six digits and try again.',
      'session-expired' ||
      'invalid-verification-id' =>
        'This SMS code has expired. Request a new code.',
      'user-disabled' =>
        'This account is disabled. Contact your cafe administrator.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled. Contact your administrator.',
      _ => 'Authentication could not be completed. Please try again.',
    };
  }
  return 'Could not connect. Please try again.';
}

/// A password provider must prove email ownership before cloud café access.
/// Phone-only accounts already prove ownership using their SMS credential.
bool requiresEmailVerification(User user) =>
    !user.emailVerified &&
    user.providerData.any((provider) => provider.providerId == 'password');

abstract interface class AccountSecurityService {
  User? get currentUser;
  Future<User?> reloadUser();
  Future<void> sendEmailVerification();
  Future<void> reauthenticateEmail(String password);
  Future<void> linkPhoneCredential(PhoneAuthCredential credential,
      {required String expectedUid});
  Future<void> signOut();
}

class FirebaseAccountSecurityService implements AccountSecurityService {
  FirebaseAccountSecurityService({FirebaseAuth? auth}) : _providedAuth = auth;
  final FirebaseAuth? _providedAuth;
  String? _reauthenticatedUid;
  DateTime? _reauthenticatedAt;
  FirebaseAuth get _auth => _providedAuth ?? BrewVerseFirebaseConfig.auth;
  @override
  User? get currentUser => _auth.currentUser;

  User _requireUser() {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'unauthenticated');
    return user;
  }

  @override
  Future<User?> reloadUser() async {
    final user = _requireUser();
    await user.reload();
    final refreshed = currentUser;
    if (refreshed?.uid != user.uid) {
      throw FirebaseAuthException(code: 'session-changed');
    }
    return refreshed;
  }

  @override
  Future<void> sendEmailVerification() =>
      _requireUser().sendEmailVerification();

  @override
  Future<void> reauthenticateEmail(String password) async {
    final user = _requireUser();
    if (!user.emailVerified || user.email == null) {
      throw FirebaseAuthException(code: 'email-not-verified');
    }
    if (!user.providerData
        .any((provider) => provider.providerId == 'password')) {
      throw FirebaseAuthException(code: 'operation-not-allowed');
    }
    await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password));
    if (currentUser?.uid != user.uid) {
      throw FirebaseAuthException(code: 'session-changed');
    }
    _reauthenticatedUid = user.uid;
    _reauthenticatedAt = DateTime.now();
  }

  @override
  Future<void> linkPhoneCredential(PhoneAuthCredential credential,
      {required String expectedUid}) async {
    final user = _requireUser();
    if (user.uid != expectedUid) {
      throw FirebaseAuthException(code: 'session-changed');
    }
    if (!user.emailVerified) {
      throw FirebaseAuthException(code: 'email-not-verified');
    }
    if (_reauthenticatedUid != expectedUid ||
        _reauthenticatedAt == null ||
        DateTime.now().difference(_reauthenticatedAt!) >
            const Duration(minutes: 5)) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    // Firebase verifies the SMS credential and rejects an already-owned number.
    // Never fall back to signInWithCredential, unlink, merge, or createUser.
    final result = await user.linkWithCredential(credential);
    _reauthenticatedUid = null;
    _reauthenticatedAt = null;
    if (result.user?.uid != expectedUid || currentUser?.uid != expectedUid) {
      throw FirebaseAuthException(code: 'session-changed');
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
