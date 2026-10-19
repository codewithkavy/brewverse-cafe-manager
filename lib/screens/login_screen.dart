import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final auth = FirebaseAuth.instance;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  bool usePhone = false;
  bool createAccount = false;
  bool loading = false;
  String? verificationId;
  int? resendToken;
  String message = '';

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> emailLogin() async {
    setState(() {
      loading = true;
      message = '';
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Enter your email and password.');
      }

      if (createAccount) {
        await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? e.code);
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();

    if (!phone.startsWith('+') || phone.length < 8) {
      setState(() =>
          message = 'Enter your phone with country code, e.g. +91XXXXXXXXXX.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: resendToken,
        verificationCompleted: (credential) async {
          await auth.signInWithCredential(credential);
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() => message = e.message ?? e.code);
          }
        },
        codeSent: (id, token) {
          if (!mounted) return;
          setState(() {
            verificationId = id;
            resendToken = token;
            message = 'OTP sent. Check your SMS.';
          });
        },
        codeAutoRetrievalTimeout: (id) {
          verificationId = id;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyOtp() async {
    final id = verificationId;
    final code = otpController.text.trim();

    if (id == null || code.length != 6) {
      setState(() => message = 'Enter the 6-digit SMS code.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: id,
        smsCode: code,
      );
      await auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
                              createAccount
                                  ? 'Create your account'
                                  : 'Welcome back',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Sign in to manage your café',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 22),
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
                              onSelectionChanged: (values) {
                                setState(() {
                                  usePhone = values.first;
                                  message = '';
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            if (!usePhone) ...[
                              TextField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    final email = emailController.text.trim();
                                    if (email.isEmpty) {
                                      setState(() =>
                                          message = 'Enter your email first.');
                                      return;
                                    }
                                    try {
                                      await auth.sendPasswordResetEmail(
                                          email: email);
                                      if (mounted) {
                                        setState(() => message =
                                            'Password reset email sent if the account exists.');
                                      }
                                    } on FirebaseAuthException catch (e) {
                                      if (mounted) {
                                        setState(() =>
                                            message = e.message ?? e.code);
                                      }
                                    }
                                  },
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              FilledButton(
                                onPressed: loading ? null : emailLogin,
                                child: Text(createAccount
                                    ? 'Create account'
                                    : 'Sign in'),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  createAccount = !createAccount;
                                  message = '';
                                }),
                                child: Text(createAccount
                                    ? 'Already registered? Sign in'
                                    : 'New here? Create account'),
                              ),
                            ] else ...[
                              TextField(
                                controller: phoneController,
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
                                        : 'Verify and sign in'),
                              ),
                              if (verificationId != null)
                                TextButton(
                                  onPressed: loading ? null : sendOtp,
                                  child: const Text('Resend OTP'),
                                ),
                            ],
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
                                    color: Theme.of(context).colorScheme.error),
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
