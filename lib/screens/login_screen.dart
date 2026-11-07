import 'dart:async';
import '../services/authentication_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen(
      {super.key,
      this.authentication,
      this.linkAccountUid,
      this.accountSecurity});
  final AuthenticationService? authentication;
  final String? linkAccountUid;
  final AccountSecurityService? accountSecurity;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final auth = widget.authentication ?? FirebaseAuthenticationService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  bool usePhone = false;
  int _otpAttempts = 0;
  bool get _linkingPhone => widget.linkAccountUid != null;

  @override
  void initState() {
    super.initState();
    usePhone = _linkingPhone;
  }

  Future<void> _applyPhoneCredential(PhoneAuthCredential credential) {
    if (_linkingPhone) {
      return widget.accountSecurity!
          .linkPhoneCredential(credential, expectedUid: widget.linkAccountUid!);
    }
    return auth.signInWithPhoneCredential(credential);
  }

  bool createAccount = false;
  bool loading = false;
  String? verificationId;
  int? resendToken;
  String message = '';

  @override
  void dispose() {
    _phoneGeneration++;
    _requestTimer?.cancel();
    _resendTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  bool messageIsSuccess = false;
  int _phoneGeneration = 0;
  bool _phoneSigningIn = false;
  bool _resendReady = true;
  Timer? _requestTimer, _resendTimer;

  void _notice(String text, {bool success = false}) {
    if (mounted) {
      setState(() {
        message = text;
        messageIsSuccess = success;
      });
    }
  }

  bool _validEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  void _clearPhoneRequest() {
    _phoneGeneration++;
    _requestTimer?.cancel();
    _resendTimer?.cancel();
    verificationId = null;
    resendToken = null;
    _resendReady = true;
    otpController.clear();
  }

  Future<void> emailLogin() async {
    if (loading) return;
    final email = emailController.text.trim(),
        password = passwordController.text;
    if (!_validEmail(email) || password.isEmpty) {
      _notice('Enter a valid email and your password.');
      return;
    }
    if (createAccount && password.length < 8) {
      _notice('Use at least 8 characters for your password.');
      return;
    }
    setState(() {
      loading = true;
      message = '';
    });
    try {
      await auth.emailSignIn(email, password, register: createAccount);
    } catch (error) {
      _notice(authenticationError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (loading) return;
    final email = emailController.text.trim();
    if (!_validEmail(email)) {
      _notice('Enter a valid email address first.');
      return;
    }
    setState(() {
      loading = true;
      message = '';
    });
    try {
      await auth.resetPassword(email);
      _notice(
          'If an account uses this email, a password reset link has been sent. Check your inbox and spam folder.',
          success: true);
    } catch (error) {
      if (error is FirebaseAuthException && error.code == 'user-not-found') {
        _notice(
            'If an account uses this email, a password reset link has been sent. Check your inbox and spam folder.',
            success: true);
      } else {
        _notice(authenticationError(error));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _finishPhone(
      Future<void> Function() signIn, int generation) async {
    if (!mounted || generation != _phoneGeneration || _phoneSigningIn) return;
    _phoneSigningIn = true;
    _requestTimer?.cancel();
    setState(() {
      loading = true;
      message = '';
    });
    try {
      await signIn();
      if (mounted && generation == _phoneGeneration) {
        _clearPhoneRequest();
        if (_linkingPhone) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (generation == _phoneGeneration) _notice(authenticationError(error));
    } finally {
      _phoneSigningIn = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendOtp() async {
    if (kReleaseMode) {
      _notice('Phone OTP: Available in a future version');
      return;
    }
    if (loading || !_resendReady) return;
    final phone =
        phoneController.text.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      _notice('Enter your phone with country code, e.g. +91XXXXXXXXXX.');
      return;
    }
    final generation = ++_phoneGeneration;
    bool current() =>
        mounted &&
        usePhone &&
        generation == _phoneGeneration &&
        !_phoneSigningIn;
    setState(() {
      loading = true;
      message = '';
    });
    _requestTimer?.cancel();
    _requestTimer = Timer(const Duration(seconds: 60), () {
      if (!current()) return;
      _clearPhoneRequest();
      setState(() {
        loading = false;
        message =
            'SMS verification timed out. Check your connection and request a new code.';
        messageIsSuccess = false;
      });
    });
    try {
      await auth.sendPhoneCode(
        phone: phone,
        resendToken: resendToken,
        completed: (credential) {
          if (current()) {
            unawaited(_finishPhone(
                () => _applyPhoneCredential(credential), generation));
          }
        },
        failed: (error) {
          if (!current()) return;
          _clearPhoneRequest();
          setState(() => loading = false);
          _notice(authenticationError(error));
        },
        sent: (id, token) {
          if (!current()) return;
          _requestTimer?.cancel();
          setState(() {
            verificationId = id;
            _otpAttempts = 0;
            resendToken = token;
            loading = false;
            _resendReady = false;
          });
          _notice('OTP sent. Enter the six-digit SMS code.', success: true);
          _resendTimer?.cancel();
          _resendTimer = Timer(const Duration(seconds: 30), () {
            if (current()) setState(() => _resendReady = true);
          });
        },
        timeout: (id) {
          if (!current()) return;
          _requestTimer?.cancel();
          setState(() {
            verificationId = id;
            loading = false;
          });
        },
      );
    } catch (error) {
      if (current()) {
        _clearPhoneRequest();
        setState(() => loading = false);
        _notice(authenticationError(error));
      }
    }
  }

  Future<void> verifyOtp() async {
    if (loading) return;
    final id = verificationId, code = otpController.text.trim();
    if (id == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      _notice('Enter the 6-digit SMS code.');
      return;
    }
    if (_otpAttempts >= 5) {
      _clearPhoneRequest();
      _notice('Too many code attempts. Request a new SMS code.');
      return;
    }
    _otpAttempts++;
    await _finishPhone(
        () => _linkingPhone
            ? _applyPhoneCredential(
                PhoneAuthProvider.credential(verificationId: id, smsCode: code))
            : auth.verifyPhoneCode(id, code),
        _phoneGeneration);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.emeraldLight,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.forest, AppTheme.emerald],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Column(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.white12,
                            child: Icon(Icons.coffee_rounded,
                                size: 38, color: AppTheme.orange),
                          ),
                          SizedBox(height: 14),
                          Text('BrewVerse',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              )),
                          SizedBox(height: 4),
                          Text('CAFE MANAGER',
                              style: TextStyle(
                                color: AppTheme.softGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _linkingPhone
                                  ? 'Link your phone number'
                                  : createAccount
                                      ? 'Create your account'
                                      : 'Welcome back',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _linkingPhone
                                  ? 'Verify the phone you own. Your existing account and café access will be preserved.'
                                  : 'Sign in to manage your café',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 22),
                            if (!_linkingPhone && !kReleaseMode)
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Email'),
                                    icon: Icon(Icons.email_outlined),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Phone OTP'),
                                    icon: Icon(Icons.phone_android),
                                  ),
                                ],
                                selected: {usePhone},
                                onSelectionChanged: loading
                                    ? null
                                    : (values) {
                                        setState(() {
                                          _clearPhoneRequest();
                                          usePhone = values.first;
                                          message = '';
                                        });
                                      },
                              ),
                            if (kReleaseMode)
                              const Text(
                                'Phone OTP: Available in a future version',
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 20),
                            if (!usePhone) ...[
                              TextField(
                                controller: emailController,
                                enabled: !loading,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: passwordController,
                                enabled: !loading,
                                obscureText: true,
                                autofillHints: [
                                  createAccount
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password
                                ],
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: createAccount
                                      ? 'At least 8 characters. Use a unique password.'
                                      : null,
                                  helperMaxLines: 2,
                                  prefixIcon:
                                      const Icon(Icons.lock_outline_rounded),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: loading ? null : resetPassword,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              FilledButton(
                                onPressed: loading ? null : emailLogin,
                                child: Text(loading
                                    ? 'Please wait…'
                                    : createAccount
                                        ? 'Create account'
                                        : 'Sign in'),
                              ),
                              TextButton(
                                onPressed: loading
                                    ? null
                                    : () => setState(() {
                                          createAccount = !createAccount;
                                          message = '';
                                        }),
                                child: Text(loading
                                    ? 'Please wait…'
                                    : createAccount
                                        ? 'Already registered? Sign in'
                                        : 'New here? Create account'),
                              ),
                            ] else ...[
                              if (!_linkingPhone)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      'Already have an email account? Sign in with email, then link your phone in Account settings to keep the same café access.'),
                                ),
                              TextField(
                                controller: phoneController,
                                enabled: !loading,
                                onChanged: (_) => setState(_clearPhoneRequest),
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone number',
                                  hintText: '+91XXXXXXXXXX',
                                  prefixIcon: Icon(Icons.phone_android_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (verificationId != null)
                                TextField(
                                  controller: otpController,
                                  enabled: !loading,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  decoration: const InputDecoration(
                                    labelText: '6-digit SMS code',
                                    prefixIcon: Icon(Icons.password_rounded),
                                  ),
                                ),
                              FilledButton(
                                onPressed: loading
                                    ? null
                                    : verificationId == null
                                        ? sendOtp
                                        : verifyOtp,
                                child: Text(loading
                                    ? 'Please wait...'
                                    : verificationId == null
                                        ? 'Send OTP'
                                        : _linkingPhone
                                            ? 'Verify and link phone'
                                            : 'Verify and sign in'),
                              ),
                              if (verificationId != null)
                                TextButton(
                                  onPressed:
                                      loading || !_resendReady ? null : sendOtp,
                                  child: Text(_resendReady
                                      ? 'Resend OTP'
                                      : 'Wait 30 seconds to resend'),
                                ),
                            ],
                            if (usePhone && loading && !_phoneSigningIn)
                              TextButton(
                                  onPressed: () => setState(() {
                                        _clearPhoneRequest();
                                        loading = false;
                                        message = 'Code request cancelled.';
                                      }),
                                  child: const Text('Cancel code request')),
                            if (loading) ...[
                              const SizedBox(height: 12),
                              const Center(child: CircularProgressIndicator()),
                            ],
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: messageIsSuccess
                                        ? AppTheme.emerald
                                        : Theme.of(context).colorScheme.error),
                              ),
                            ],
                          ],
                        ),
                      ),
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
}
