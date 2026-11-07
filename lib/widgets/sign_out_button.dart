import 'package:flutter/material.dart';
import '../services/authentication_service.dart';

class SignOutButton extends StatefulWidget {
  const SignOutButton({super.key, this.signOut});
  final Future<void> Function()? signOut;
  @override
  State<SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<SignOutButton> {
  bool _busy = false;
  Future<void> _submit() async {
    if (_busy) return;
    final root = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await (widget.signOut ?? FirebaseAuthenticationService().signOut)();
      // Remove root-level dialogs/routes as well as the UID-scoped workspace.
      if (root.mounted) root.popUntil((route) => route.isFirst);
      if (messenger?.mounted ?? false) {
        messenger!.showSnackBar(const SnackBar(
            content: Text('Signed out. Your cafe data is unchanged.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Could not sign out. ${authenticationError(error)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
      onPressed: _busy ? null : _submit,
      icon: _busy
          ? const SizedBox.square(
              dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.logout_rounded),
      label: Text(_busy ? 'Signing out…' : 'Sign out'));
}
