import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/authentication_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Links a verified SMS credential to the current identity; never merges users.
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({this.security, this.authentication, super.key});
  final AccountSecurityService? security;
  final AuthenticationService? authentication;
  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  late final _security = widget.security ?? FirebaseAccountSecurityService();
  late final _authentication =
      widget.authentication ?? FirebaseAuthenticationService();
  final _password = TextEditingController();
  User? _user;
  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _user = _security.currentUser;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = authenticationError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _linkPhone() => _run(() async {
        final user = _user;
        if (user == null) throw FirebaseAuthException(code: 'unauthenticated');
        if (!user.emailVerified) {
          throw FirebaseAuthException(code: 'email-not-verified');
        }
        if (_password.text.isEmpty) {
          setState(() => _message =
              'Enter your current email password to confirm account ownership.');
          return;
        }
        await _security.reauthenticateEmail(_password.text);
        _password.clear();
        if (!mounted) return;
        final linked = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => LoginScreen(
              linkAccountUid: user.uid,
              accountSecurity: _security,
              authentication: _authentication),
        ));
        if (linked == true) {
          final user = await _security.reloadUser();
          if (mounted) {
            setState(() {
              _user = user;
              _message = 'Phone number linked to your existing account.';
            });
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final emailAccount = user?.providerData
            .any((provider) => provider.providerId == 'password') ??
        false;
    return Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          appBar: AppBar(title: const Text('Account settings')),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            if (user == null)
              const Text('Sign in before changing account settings.')
            else ...[
              Text(user.email ?? 'Phone account',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (emailAccount)
                Text(user.emailVerified
                    ? 'Email verified'
                    : 'Email verification required'),
              if (user.phoneNumber != null)
                Text('Linked phone: ${user.phoneNumber}'),
              if (emailAccount && !user.emailVerified) ...[
                TextButton(
                    onPressed: _working
                        ? null
                        : () => _run(() async {
                              await _security.sendEmailVerification();
                              if (mounted) {
                                setState(() => _message =
                                    'Verification email sent. Check your inbox and spam folder.');
                              }
                            }),
                    child: const Text('Send verification email')),
                TextButton(
                    onPressed: _working
                        ? null
                        : () => _run(() async {
                              final refreshed = await _security.reloadUser();
                              if (mounted) setState(() => _user = refreshed);
                            }),
                    child: const Text('Check email verification')),
              ],
              const SizedBox(height: 20),
              if (emailAccount && user.phoneNumber == null) ...[
                const Text(
                    'Link your phone to use email or SMS login with the same café access. Verify your email, confirm its password, then enter the SMS code for the number you own. Numbers on another account cannot be linked here.'),
                const SizedBox(height: 12),
                TextField(
                    controller: _password,
                    enabled: !_working,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                        labelText: 'Current email password')),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed:
                        _working || !user.emailVerified ? null : _linkPhone,
                    child: const Text('Verify and link phone')),
              ],
              if (!emailAccount)
                const Text(
                    'This account signs in by SMS. To combine it with an existing email account, contact your café owner. Accounts are never merged automatically.'),
              if (emailAccount)
                TextButton(
                    onPressed: _working
                        ? null
                        : () => _run(() async {
                              await _authentication.resetPassword(user.email!);
                              if (mounted) {
                                setState(() => _message =
                                    'If this account can reset its password, a reset link has been sent.');
                              }
                            }),
                    child: const Text('Send password reset email')),
              TextButton(
                  onPressed: _working ? null : () => _run(_security.signOut),
                  child: const Text('Sign out')),
            ],
            if (_working) const Center(child: CircularProgressIndicator()),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!)),
          ]),
        ));
  }
}
