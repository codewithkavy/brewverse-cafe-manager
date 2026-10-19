import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_functions_service.dart';
import '../services/cafe_membership_service.dart';
import 'home_screen.dart';

typedef CafeWorkspaceHomeBuilder = Widget Function(
  BuildContext context,
  CafeMembership membership,
  VoidCallback onSwitchCafe,
);

/// Membership-aware entry point for the future tenant-mode release.
///
/// This screen is enabled only by `--dart-define=BREWVERSE_TENANT_MODE=true`.
/// It does not import or claim legacy records when creating a new café.
class CafeWorkspaceGate extends StatefulWidget {
  const CafeWorkspaceGate({
    required this.uid,
    this.membershipService,
    this.functionsService,
    this.homeBuilder,
    super.key,
  });

  final String uid;
  final CafeMembershipService? membershipService;
  final CafeFunctionsService? functionsService;
  final CafeWorkspaceHomeBuilder? homeBuilder;

  @override
  State<CafeWorkspaceGate> createState() => _CafeWorkspaceGateState();
}

class _CafeWorkspaceGateState extends State<CafeWorkspaceGate> {
  late final CafeMembershipService _membershipService =
      widget.membershipService ?? CafeMembershipService();
  late final CafeFunctionsService _functionsService =
      widget.functionsService ?? CafeFunctionsService();

  String? _selectedCafeId;
  bool _choosingCafe = false;

  late Stream<List<CafeMembership>> _memberships =
      _membershipService.watchForUser(widget.uid);

  @override
  void didUpdateWidget(covariant CafeWorkspaceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _selectedCafeId = null;
      _choosingCafe = false;
      _memberships = _membershipService.watchForUser(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CafeMembership>>(
      key: ValueKey(widget.uid),
      stream: _memberships,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GateMessage(
            title: 'Could not load café access',
            message: 'Check your connection and try again.\n${snapshot.error}',
            icon: Icons.cloud_off_rounded,
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final active = snapshot.data!.where((item) => item.isActive).toList()
          ..sort((left, right) => left.cafeId.compareTo(right.cafeId));
        CafeMembership? selected;
        for (final membership in active) {
          if (membership.cafeId == _selectedCafeId) {
            selected = membership;
            break;
          }
        }
        selected ??=
            active.length == 1 && !_choosingCafe ? active.single : null;

        if (selected != null) {
          final membership = selected;
          // Keep pushed screens and dialogs within the authorized workspace.
          // Revocation, role changes, and switching users discard this stack.
          return Navigator(
            key: ValueKey((widget.uid, membership.cafeId, membership.role)),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => (widget.homeBuilder ?? _defaultHome)(
                context,
                membership,
                () => setState(() {
                  _selectedCafeId = null;
                  _choosingCafe = true;
                }),
              ),
            ),
          );
        }

        return _CafeChooser(
          memberships: active,
          functionsService: _functionsService,
          onSelect: (membership) => setState(() {
            _selectedCafeId = membership.cafeId;
            _choosingCafe = false;
          }),
        );
      },
    );
  }

  Widget _defaultHome(
    BuildContext context,
    CafeMembership membership,
    VoidCallback onSwitchCafe,
  ) =>
      HomeScreen(
        cafeId: membership.cafeId,
        cafeRole: membership.role,
        onSwitchCafe: onSwitchCafe,
      );
}

class _CafeChooser extends StatelessWidget {
  const _CafeChooser({
    required this.memberships,
    required this.functionsService,
    required this.onSelect,
  });

  final List<CafeMembership> memberships;
  final CafeFunctionsService functionsService;
  final ValueChanged<CafeMembership> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a café')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                memberships.isEmpty
                    ? 'No active café access'
                    : 'Your café workspaces',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                memberships.isEmpty
                    ? 'Create a new workspace or ask a café owner to add your account.'
                    : 'Choose the workspace you want to open.',
              ),
              const SizedBox(height: 20),
              for (final membership in memberships)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_cafe_outlined),
                    title: Text(membership.cafeId),
                    subtitle: Text(membership.role.name),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => onSelect(membership),
                  ),
                ),
              const SizedBox(height: 16),
              _CreateCafePanel(functionsService: functionsService),
              const SizedBox(height: 12),
              const Text(
                'Creating a café starts an empty workspace. Legacy records are '
                'not moved or removed automatically.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateCafePanel extends StatefulWidget {
  const _CreateCafePanel({required this.functionsService});

  final CafeFunctionsService functionsService;

  @override
  State<_CreateCafePanel> createState() => _CreateCafePanelState();
}

class _CreateCafePanelState extends State<_CreateCafePanel> {
  final _name = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _createCafe() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 80 || _creating) {
      setState(() => _error = 'Enter a café name from 2 to 80 characters.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await widget.functionsService.createCafe(name: name);
      // The membership stream will update and show the new workspace.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'Could not create café: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_creating,
              decoration: const InputDecoration(labelText: 'Café name'),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _createCafe(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _creating ? null : _createCafe,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_business_rounded),
              label: Text(_creating ? 'Creating café…' : 'Create café'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
