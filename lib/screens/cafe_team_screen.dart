import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_functions_service.dart';
import '../theme/app_theme.dart';
import 'loyalty_settings_screen.dart';

class CafeTeamScreen extends StatefulWidget {
  const CafeTeamScreen({
    required this.cafeId,
    required this.callerRole,
    this.functionsService,
    this.currentUid,
    super.key,
  });

  final String cafeId;
  final CafeRole callerRole;
  final CafeFunctionsService? functionsService;
  final String? currentUid;

  @override
  State<CafeTeamScreen> createState() => _CafeTeamScreenState();
}

class _CafeTeamScreenState extends State<CafeTeamScreen> {
  late final _functions = widget.functionsService ?? CafeFunctionsService();
  List<CafeMembership> _memberships = const [];
  String? _nextPageToken;
  String? _loadError;
  String? _pageError;
  int _requestGeneration = 0;
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_requestGeneration;
    setState(() {
      _memberships = const [];
      _nextPageToken = null;
      _hasMore = false;
      _loadError = null;
      _pageError = null;
      _loading = true;
      _loadingMore = false;
    });
    try {
      final page = await _functions.listCafeMemberships(cafeId: widget.cafeId);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _memberships = page.memberships;
        _hasMore = page.hasMore;
        _nextPageToken = page.nextPageToken;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final pageToken = _nextPageToken;
    if (!_hasMore || pageToken == null || _loadingMore) return;
    final generation = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _pageError = null;
    });
    try {
      final page = await _functions.listCafeMemberships(
        cafeId: widget.cafeId,
        pageToken: pageToken,
      );
      if (!mounted || generation != _requestGeneration) return;
      final members = [..._memberships, ...page.memberships]
        ..sort((left, right) => left.uid.compareTo(right.uid));
      setState(() {
        _memberships = members;
        _hasMore = page.hasMore;
        _nextPageToken = page.nextPageToken;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _pageError = error.toString();
        _loadingMore = false;
      });
    }
  }

  Future<void> _addMember() async {
    final input = await showDialog<({String email, String role})>(
      useRootNavigator: false,
      context: context,
      builder: (context) => _AddMemberDialog(
        canGrantManager: widget.callerRole == CafeRole.owner,
      ),
    );
    if (input == null || !mounted) return;
    setState(() => _working = true);
    try {
      await _functions.grantCafeMembership(
        cafeId: widget.cafeId,
        targetEmail: input.email,
        role: input.role,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Café access updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update access: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revoke(CafeMembership membership) async {
    final confirmed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke café access?'),
        content: Text('This will revoke access for ${membership.uid}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await _functions.revokeCafeMembership(
        cafeId: widget.cafeId,
        targetUid: membership.uid,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Café access revoked.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not revoke access: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _canChange(CafeMembership membership, String? currentUid) {
    if (!membership.isActive ||
        membership.role == CafeRole.owner ||
        membership.uid == currentUid) {
      return false;
    }
    if (widget.callerRole == CafeRole.manager &&
        membership.role != CafeRole.staff) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid =
        widget.currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    return Theme(
      data: AppTheme.emeraldLight,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Café team'),
          actions: [
            if (widget.callerRole == CafeRole.owner)
              IconButton(
                tooltip: 'Loyalty settings',
                onPressed: _working
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LoyaltySettingsScreen(
                              cafeId: widget.cafeId,
                              role: widget.callerRole,
                              functionsService: _functions,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.loyalty_outlined),
              ),
            if (widget.callerRole == CafeRole.owner ||
                widget.callerRole == CafeRole.manager)
              IconButton(
                tooltip: 'Add or restore member access',
                onPressed: _working ? null : _addMember,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
          ],
        ),
        body: _loading && _memberships.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && _memberships.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load café team.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Manage who can use this café. Members must already '
                          'have a BrewVerse account; add the email they use to '
                          'sign in.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        if (_memberships.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: AppTheme.softGreen,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: const Icon(
                                      Icons.groups_2_rounded,
                                      color: AppTheme.emerald,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'No café members found',
                                          style: TextStyle(
                                            color: AppTheme.ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Add an existing account to give it café access.',
                                          style: TextStyle(
                                            color: AppTheme.mutedInk,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final membership in _memberships)
                          Card(
                            child: ListTile(
                              leading: Icon(
                                membership.role == CafeRole.owner
                                    ? Icons.verified_user_rounded
                                    : Icons.person_outline_rounded,
                              ),
                              title: Text(
                                membership.uid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${membership.role.name} · '
                                '${membership.status.name}',
                              ),
                              trailing: _canChange(membership, currentUid)
                                  ? IconButton(
                                      tooltip: 'Revoke access',
                                      onPressed: _working
                                          ? null
                                          : () => _revoke(membership),
                                      icon: const Icon(
                                        Icons.person_remove_alt_1_rounded,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        if (_pageError != null) ...[
                          Text(
                              'Could not load the next team page: $_pageError'),
                        ],
                        if (_hasMore)
                          OutlinedButton.icon(
                            onPressed: _loadingMore ? null : _loadMore,
                            icon: _loadingMore
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _pageError == null
                                        ? Icons.expand_more_rounded
                                        : Icons.refresh_rounded,
                                  ),
                            label: Text(
                              _loadingMore
                                  ? 'Loading members…'
                                  : _pageError == null
                                      ? 'Load more'
                                      : 'Retry loading members',
                            ),
                          ),
                        if (_working || _loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.canGrantManager});

  final bool canGrantManager;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _emailController = TextEditingController();
  String _role = 'staff';
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the member’s sign-in email.');
      return;
    }
    Navigator.pop(context, (email: email, role: _role));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add café member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Account email'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                const DropdownMenuItem(value: 'staff', child: Text('Staff')),
                if (widget.canGrantManager)
                  const DropdownMenuItem(
                    value: 'manager',
                    child: Text('Manager'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Grant access')),
        ],
      );
}
