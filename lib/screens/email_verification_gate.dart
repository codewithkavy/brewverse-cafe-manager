import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/authentication_service.dart';
import '../theme/app_theme.dart';

/// A cloud email/password session cannot enter a café until ownership is proved.
class EmailVerificationGate extends StatefulWidget {
  const EmailVerificationGate(
      {required this.user, required this.child, this.security, super.key});
  final User user;
  final Widget child;
  final AccountSecurityService? security;
  @override
  State<EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<EmailVerificationGate> {
  late final _security = widget.security ?? FirebaseAccountSecurityService();
  bool _verified = false;
  bool _working = false;
  bool _canResend = true;
  String? _message;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final current = await _security.reloadUser();
      if (current?.uid != widget.user.uid) {
        throw FirebaseAuthException(code: 'session-changed');
      }
      if (current!.emailVerified) {
        await current.getIdToken(true);
        if (mounted) setState(() => _verified = true);
      } else if (mounted) {
        setState(() => _message =
            'Email is not verified yet. Open the link in your inbox, then check again.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = authenticationError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _resend() async {
    if (_working || !_canResend) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await _security.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _message = 'Verification email sent. Check your inbox and spam folder.';
        _canResend = false;
      });
      _resendTimer?.cancel();
      _resendTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _canResend = true);
      });
    } catch (error) {
      if (mounted) setState(() => _message = authenticationError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verified || !requiresEmailVerification(widget.user)) {
      return widget.child;
    }
    return Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          appBar: AppBar(title: const Text('Verify your email')),
          body: Center(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mark_email_unread_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                    'Verify ${widget.user.email ?? 'your email address'} before opening your café.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _working ? null : _check,
                    child: const Text('I verified my email')),
                TextButton(
                    onPressed: _working || !_canResend ? null : _resend,
                    child: Text(_canResend
                        ? 'Resend verification email'
                        : 'Wait 30 seconds to resend')),
                TextButton(
                    onPressed: _working
                        ? null
                        : () async {
                            setState(() => _working = true);
                            try {
                              await _security.signOut();
                            } catch (error) {
                              if (mounted) {
                                setState(() =>
                                    _message = authenticationError(error));
                              }
                            } finally {
                              if (mounted) setState(() => _working = false);
                            }
                          },
                    child: const Text('Sign out')),
                if (_working) const CircularProgressIndicator(),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!, textAlign: TextAlign.center)),
              ]),
            ),
          )),
        ));
  }
}
