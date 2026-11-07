import 'dart:async';

import 'package:flutter/material.dart';

import 'backend.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({required this.api, required this.onSignOut, super.key});
  final AdminApi api;
  final Future<void> Function() onSignOut;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Map<String, dynamic>? overview, selected;
  final cafes = <Map<String, dynamic>>[];
  String page = 'Overview', search = '', filter = 'All';
  String? cursor, error;
  bool busy = false, loading = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!busy && !loading) refresh();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final o = await widget.api.call('adminOverview');
      final p = await widget.api.call('adminListCafes');
      Map<String, dynamic>? detail;
      if (selected != null) {
        detail = await widget.api.call('adminCafeDetails', {
          'cafeId': selected!['cafe']['cafeId'],
        });
      }
      if (mounted) {
        setState(() {
          overview = o;
          cafes
            ..clear()
            ..addAll(
              (p['cafes'] as List).map((x) => Map<String, dynamic>.from(x)),
            );
          cursor = p['nextCursor'] as String?;
          if (detail != null) selected = detail;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && !busy) unawaited(completeSearch());
  }

  Future<void> more() async {
    setState(() => busy = true);
    try {
      final p = await widget.api.call('adminListCafes', {'cursor': cursor});
      if (mounted) {
        setState(() {
          cafes.addAll(
            (p['cafes'] as List).map((x) => Map<String, dynamic>.from(x)),
          );
          cursor = p['nextCursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> completeSearch() async {
    if (busy || loading) return;
    while (mounted &&
        cursor != null &&
        (search.isNotEmpty || filter != 'All')) {
      final previous = cursor;
      await more();
      if (cursor == previous) break;
    }
  }

  Future<void> open(String id) async {
    setState(() => busy = true);
    try {
      final d = await widget.api.call('adminCafeDetails', {'cafeId': id});
      if (mounted) setState(() => selected = d);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(String function, Map<String, dynamic> data) async {
    setState(() => busy = true);
    try {
      await widget.api.call(function, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved and audited successfully.')),
        );
        await refresh();
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted) unawaited(completeSearch());
  }

  String operationId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().hashCode.abs()}';
  Future<void> subscription(String action) async {
    final revision = selected!['subscription']['revision'] ?? 0;
    final cafeId = selected!['cafe']['cafeId'];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EntryDialog(
        title: action == 'activatePermanent'
            ? 'Activate permanent café access'
            : '${action[0].toUpperCase()}${action.substring(1)} access',
        fields: [
          if (action == 'activate' || action == 'extend')
            const EntryField(
              'expiresAt',
              'Expiry (ISO date with timezone)',
              hint: '2026-11-22T23:59:59+05:30',
            ),
          const EntryField('reason', 'Reason / payment reference'),
        ],
        notice: action == 'activatePermanent'
            ? 'Permanent access has no expiry. Only a Super Admin can suspend or resume it. This action is audited.'
            : 'Access changes do not record a payment. Verify payment separately, then choose an explicit expiry.',
      ),
    );
    if (result == null || !mounted) return;
    await perform('adminUpdateSubscription', {
      ...result,
      'cafeId': cafeId,
      'action': action,
      'expectedRevision': revision,
      'operationId': operationId(),
    });
  }

  Future<void> payment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EntryDialog(
        title: 'Record verified UPI payment',
        fields: [
          const EntryField('amount', 'Amount received (₹)', number: true),
          EntryField(
            'paidAt',
            'Payment date (ISO with timezone)',
            initial: DateTime.now().toUtc().toIso8601String(),
          ),
          const EntryField('reference', 'Full UPI reference'),
          const EntryField('note', 'How did you verify this payment?'),
        ],
        verification: true,
        notice: 'Check your own bank / UPI account first. BrewVerse cannot verify transfers. Recording this payment does not activate access.',
      ),
    );
    if (result == null || !mounted) return;
    final amount = double.tryParse('${result.remove('amount')}');
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => error = 'Enter a positive payment amount.');
      return;
    }
    await perform('adminRecordVerifiedPayment', {
      ...result,
      'amountMinor': (amount * 100).round(),
      'cafeId': selected!['cafe']['cafeId'],
    });
  }

  Future<void> policy() async {
    final settings = overview!['settings'] as Map;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EntryDialog(
        title: 'Subscription policy',
        fields: [
          EntryField(
            'price',
            'Monthly price (₹)',
            initial: ((settings['monthlyPriceMinor'] as num) / 100)
                .toStringAsFixed(2),
            number: true,
          ),
          EntryField(
            'grace',
            'Grace days (0–14)',
            initial: '${settings['graceDays']}',
            number: true,
          ),
          const EntryField('reason', 'Reason for changing policy'),
        ],
        toggleLabel: 'Require subscriptions for unmanaged local cafés',
        toggleInitial: settings['enforcementEnabled'] == true,
        notice: 'Grace applies to future activations and renewals. Production always enforces subscriptions. Enabling this locally blocks unmanaged fixtures.',
      ),
    );
    if (result == null || !mounted) return;
    final price = double.tryParse('${result.remove('price')}'),
        grace = int.tryParse('${result.remove('grace')}');
    if (price == null || !price.isFinite || price <= 0 || grace == null) {
      setState(() => error = 'Enter a valid price and whole grace days.');
      return;
    }
    await perform('adminSaveSubscriptionPolicy', {
      ...result,
      'monthlyPriceMinor': (price * 100).round(),
      'graceDays': grace,
      'expectedRevision': settings['revision'] ?? 0,
      'operationId': operationId(),
    });
  }

  Widget badge(String status) => Chip(
    label: Text(status.toUpperCase()),
    side: BorderSide.none,
    backgroundColor: ['active', 'grace'].contains(status)
        ? const Color(0xffdceee3)
        : status == 'suspended'
        ? const Color(0xffffe1dc)
        : const Color(0xffeceeea),
  );
  Widget overviewPage() {
    final counts = overview!['counts'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A clear view of your café network',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Manual UPI collection. Access controlled by the server.'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final pair in [
              ('Registered cafés', 'total'),
              ('Active cafés', 'active'),
              ('Grace period', 'grace'),
              ('Expired', 'expired'),
              ('Suspended', 'suspended'),
              ('Awaiting activation', 'pending'),
              ('Recorded revenue', 'revenueMinor'),
            ])
              SizedBox(
                width: 210,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pair.$1),
                        const SizedBox(height: 14),
                        Text(
                          pair.$2 == 'revenueMinor'
                              ? money(counts[pair.$2])
                              : '${counts[pair.$2]}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscription policy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Monthly: ${money(overview!['settings']['monthlyPriceMinor'])} · Grace: ${overview!['settings']['graceDays']} days',
                ),
                const Text(
                  'Revenue includes manually verified payment records only.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : policy,
                  icon: const Icon(Icons.tune),
                  label: const Text('Configure policy'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget cafesPage() {
    final visible = cafes
        .where(
          (c) =>
              (filter == 'All' || c['status'] == filter) &&
              '${c['name']} ${c['id']} ${c['ownerUid']}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Café management',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search cafés by name, ID or owner',
          ),
          onChanged: (v) {
            setState(() => search = v);
            unawaited(completeSearch());
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final state in [
              'All',
              'active',
              'grace',
              'expired',
              'suspended',
              'pending',
            ])
              ChoiceChip(
                label: Text(state),
                selected: filter == state,
                onSelected: (_) {
                  setState(() => filter = state);
                  unawaited(completeSearch());
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${cafes.length} cafés loaded. Search and filters load remaining pages automatically.',
        ),
        for (final c in visible)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                '${c['name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Owner: ${c['ownerEmail'] ?? c['ownerUid']}\n${c['id']}\nLicense: ${c['subscription']['licenseType'] == 'permanent' ? 'Permanent' : dateLabel(c['subscription']['expiresAt'])}',
              ),
              trailing: badge('${c['status']}'),
              onTap: busy ? null : () => open('${c['id']}'),
            ),
          ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching cafés in loaded pages.'),
          ),
        if (cursor != null)
          OutlinedButton(
            onPressed: busy ? null : more,
            child: const Text('Load more cafés'),
          ),
      ],
    );
  }

  Widget details() {
    final d = selected!, c = d['cafe'] as Map, sub = d['subscription'] as Map;
    final payments = (d['payments'] as List).toList()
      ..sort((a, b) => '${b['paidAt']}'.compareTo('${a['paidAt']}'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => selected = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('All cafés'),
        ),
        Text('${c['name']}', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'Owner: ${d['ownerEmail'] ?? c['ownerUid']}\nOwner UID: ${c['ownerUid']}\nCafe ID: ${c['cafeId']}',
        ),
        badge('${d['status']}'),
        Text(
          sub['licenseType'] == 'permanent'
              ? 'License: Permanent (subject to administrator suspension)'
              : 'Expires: ${dateLabel(sub['expiresAt'])} · Grace: ${sub['graceDays'] ?? 0} days',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final pair in [
              if (sub['licenseType'] != 'permanent')
                ('activatePermanent', 'Activate permanently'),
              if (sub['licenseType'] != 'permanent') ...[
                ('activate', 'Activate / renew'),
                ('extend', 'Extend expiry'),
              ],
              ('suspend', 'Suspend'),
              ('resume', 'Resume access'),
            ])
              OutlinedButton(
                onPressed: busy ? null : () => subscription(pair.$1),
                child: Text(pair.$2),
              ),
            FilledButton.icon(
              onPressed: busy ? null : payment,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Record verified payment'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Manual payment history',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Payment recording and activation are separate actions.'),
        if (payments.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No verified payments recorded.'),
          ),
        for (final p in payments)
          Card(
            child: ListTile(
              title: Text('${money(p['amountMinor'])} · ${p['reference']}'),
              subtitle: Text(
                '${dateLabel(p['paidAt'])}\nVerified by ${p['verifiedBy']} · ${p['verificationNote']}',
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Administrator audit trail',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        for (final a in d['audits'] as List)
          ListTile(
            title: Text('${a['action']}'),
            subtitle: Text(
              '${dateLabel(a['createdAt'])} · ${a['actorUid']}\n${a['reason'] ?? 'Read-only action'}',
            ),
          ),
        if (d['historyTruncated'] == true)
          const Text(
            'History is capped at 500 records; a paginated export is needed for larger accounts.',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final narrow = size.maxWidth < 850;
      return Scaffold(
        appBar: AppBar(
          title: const Text('BrewVerse · Admin'),
          actions: [
            const Padding(
              padding: EdgeInsets.all(10),
              child: Chip(label: Text('LOCAL')),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: busy || loading ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: busy ? null : widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        bottomNavigationBar: narrow
            ? Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: NavigationBar(
                  selectedIndex: page == 'Overview' ? 0 : 1,
                  onDestinationSelected: (i) =>
                      setState(() => page = i == 0 ? 'Overview' : 'Cafés'),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Overview',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.storefront),
                      label: 'Cafés',
                    ),
                  ],
                ),
              )
            : null,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!narrow)
              SizedBox(
                width: 220,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        'CONTROL CENTER',
                        style: TextStyle(letterSpacing: 2, color: Colors.grey),
                      ),
                      const SizedBox(height: 26),
                      for (final label in ['Overview', 'Cafés'])
                        ListTile(
                          selected: page == label,
                          leading: Icon(
                            label == 'Overview'
                                ? Icons.dashboard_outlined
                                : Icons.storefront,
                          ),
                          title: Text(label),
                          onTap: () => setState(() => page = label),
                        ),
                      const Spacer(),
                      const Text(
                        'BrewVerse V1\nManual subscriptions',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(narrow ? 16 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null)
                      Card(
                        color: const Color(0xffffe8e4),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(error!),
                              TextButton(
                                onPressed: busy ? null : refresh,
                                child: const Text('Refresh and retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (loading || busy) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    if (overview != null)
                      (page == 'Overview'
                          ? overviewPage()
                          : selected != null
                          ? details()
                          : cafesPage()),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class EntryField {
  const EntryField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.hint,
    this.number = false,
  });
  final String keyName, label, initial;
  final String? hint;
  final bool number;
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({
    required this.title,
    required this.fields,
    required this.notice,
    this.verification = false,
    this.toggleLabel,
    this.toggleInitial = false,
    super.key,
  });
  final String title, notice;
  final List<EntryField> fields;
  final bool verification, toggleInitial;
  final String? toggleLabel;
  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  late final controllers = {
    for (final f in widget.fields)
      f.keyName: TextEditingController(text: f.initial),
  };
  bool verified = false;
  late bool toggle = widget.toggleInitial;
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.notice),
            const SizedBox(height: 20),
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: controllers[f.keyName],
                  keyboardType: f.number
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: f.label,
                    hintText: f.hint,
                  ),
                ),
              ),
            if (widget.verification)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: verified,
                onChanged: (v) => setState(() => verified = v ?? false),
                title: const Text(
                  'I checked my bank / UPI account and verified this payment.',
                ),
              ),
            if (widget.toggleLabel != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: toggle,
                onChanged: (v) => setState(() => toggle = v),
                title: Text(widget.toggleLabel!),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.verification && !verified
            ? null
            : () {
                if (controllers.values.any((c) => c.text.trim().isEmpty)) {
                  setState(() => error = 'Complete all fields.');
                  return;
                }
                Navigator.pop(context, {
                  for (final e in controllers.entries)
                    e.key: e.value.text.trim(),
                  if (widget.verification) 'confirmedVerified': true,
                  if (widget.toggleLabel != null) 'enforcementEnabled': toggle,
                });
              },
        child: const Text('Confirm'),
      ),
    ],
  );
}
