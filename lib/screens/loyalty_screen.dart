import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import 'billing_screen.dart';
import 'home_screen.dart';
import 'loyalty_customer_details_screen.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({
    super.key,
    required this.cafeId,
    this.cafeRole,
    this.cafeService,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final CafeService? cafeService;

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _phone = TextEditingController();
  CafeService? _service;
  Map<String, dynamic>? _customer;
  int? _pointValueMinor;
  bool _loading = false;
  String? _error;
  String? _customerPhone;
  bool _settingsUnavailable = false;
  int _tab = 0;
  int _lookupVersion = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.cafeService ??
        (widget.cafeId == null ? null : CafeService(cafeId: widget.cafeId));
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LoyaltyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cafeId != widget.cafeId ||
        oldWidget.cafeService != widget.cafeService) {
      _lookupVersion++;
      _service = widget.cafeService ??
          (widget.cafeId == null ? null : CafeService(cafeId: widget.cafeId));
      _phone.clear();
      _resetResult();
    }
  }

  void _resetResult() {
    _customer = null;
    _customerPhone = null;
    _pointValueMinor = null;
    _settingsUnavailable = false;
    _error = null;
    _loading = false;
  }

  void _phoneChanged() => setState(() {
        _lookupVersion++;
        _resetResult();
      });

  Future<void> _lookup() async {
    final phone = _phone.text.trim();
    final service = _service;
    if (service == null || widget.cafeId == null || _loading) return;
    if (phone.isEmpty) {
      setState(
          () => _error = 'Enter a customer phone number with country code.');
      return;
    }
    final version = ++_lookupVersion;
    setState(() {
      _loading = true;
      _error = null;
      _customer = null;
      _customerPhone = null;
      _pointValueMinor = null;
      _settingsUnavailable = false;
    });
    try {
      // A missing point-value setting must not hide a saved customer balance.
      final settingsRequest = service
          .getLoyaltySettings()
          .then<Map<String, dynamic>?>((settings) => settings,
              onError: (Object _) => null);
      final customer = await service.lookupLoyaltyCustomer(phoneNumber: phone);
      final settings = await settingsRequest;
      if (!mounted ||
          version != _lookupVersion ||
          _phone.text.trim() != phone) {
        return;
      }
      final pointValue = settings?['pointValueMinor'];
      final normalizedPhone = customer['phoneNumber'];
      setState(() {
        _customer = customer;
        _customerPhone = normalizedPhone is String && normalizedPhone.isNotEmpty
            ? normalizedPhone
            : phone;
        _pointValueMinor =
            pointValue is int && pointValue > 0 ? pointValue : null;
        _settingsUnavailable = _pointValueMinor == null;
      });
    } catch (error) {
      if (mounted && version == _lookupVersion) {
        setState(() => _error = 'Could not look up this customer. $error');
      }
    } finally {
      if (mounted && version == _lookupVersion) {
        setState(() => _loading = false);
      }
    }
  }

  void _startBill() {
    final cafeId = widget.cafeId;
    if (cafeId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BillingScreen(
        cafeId: cafeId,
        cafeRole: widget.cafeRole,
        cafeService: _service,
        stockStream: _service?.watchStock(),
        initialCustomerPhone: _customerPhone ?? _phone.text.trim(),
      ),
    ));
  }

  bool get _hasWorkspace => widget.cafeId != null && _service != null;

  void _viewCustomer() {
    final customer = _customer;
    final phone = _customerPhone;
    if (customer == null || customer['found'] != true || phone == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LoyaltyCustomerDetailsScreen(
        customer: customer,
        phoneNumber: phone,
        pointValueMinor: _pointValueMinor,
        onStartBill: _startBill,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          backgroundColor: AppTheme.forest,
          appBar: AppBar(
            toolbarHeight: 52,
            leadingWidth: 42,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 21),
            ),
            backgroundColor: AppTheme.forest,
            foregroundColor: Colors.white,
            titleSpacing: 0,
            title: const Text('Loyalty',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          body: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ColoredBox(
              color: AppTheme.paper,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAE9E2),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(children: [
                            _tabButton('Customers', 0),
                            _tabButton('Transactions', 1),
                          ]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 7),
                        child: TextField(
                          controller: _phone,
                          enabled: _hasWorkspace && !_loading && _tab == 0,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                              color: AppTheme.ink, fontSize: 13),
                          onChanged: (_) => _phoneChanged(),
                          onSubmitted: (_) => _lookup(),
                          decoration: InputDecoration(
                            labelText: 'Customer phone number',
                            hintText: '+country code',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 19),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_phone.text.isNotEmpty)
                                  SizedBox(
                                    width: 36,
                                    child: IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: _loading || _tab != 0
                                          ? null
                                          : () {
                                              _phone.clear();
                                              _phoneChanged();
                                            },
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.close_rounded,
                                          size: 17),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Find customer',
                                  onPressed:
                                      !_hasWorkspace || _loading || _tab != 0
                                          ? null
                                          : _lookup,
                                  icon: _loading
                                      ? const SizedBox.square(
                                          dimension: 17,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.arrow_forward_rounded,
                                          size: 20),
                                ),
                              ],
                            ),
                            fillColor: AppTheme.card,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            labelStyle: const TextStyle(
                                color: AppTheme.mutedInk, fontSize: 12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                  color: AppTheme.emerald, width: 1.2),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _content(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: ColoredBox(
            color: AppTheme.paper,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_tab == 0)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: !_hasWorkspace || _loading
                                    ? null
                                    : _startBill,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.orange,
                                  foregroundColor: AppTheme.forest,
                                  disabledBackgroundColor: AppTheme.softOrange,
                                  disabledForegroundColor: AppTheme.orangeDeep
                                      .withValues(alpha: 0.65),
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.person_add_alt_outlined,
                                        size: 20),
                                    const SizedBox(width: 9),
                                    Flexible(
                                      child: Text(
                                        _customer == null
                                            ? 'New customer bill'
                                            : _customer!['found'] == true
                                                ? 'Use phone at checkout'
                                                : 'Start a bill for this phone',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    const Icon(Icons.arrow_forward_rounded,
                                        size: 18),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Customer setup continues at checkout.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppTheme.mutedInk,
                                  fontSize: 10,
                                  height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                CafeBottomNavigation(
                    selectedIndex: 3, onDestinationSelected: _selectTab),
              ],
            ),
          ),
        ),
      );

  Widget _tabButton(String label, int index) => Expanded(
        child: Semantics(
          selected: _tab == index,
          button: true,
          child: Material(
            color: _tab == index ? AppTheme.emerald : Colors.transparent,
            borderRadius: BorderRadius.circular(23),
            child: InkWell(
              borderRadius: BorderRadius.circular(23),
              onTap: () => setState(() => _tab = index),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _tab == index ? Colors.white : AppTheme.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );

  Widget _content() {
    if (_tab == 1) {
      return _LoyaltyState(
        key: const ValueKey('transactions'),
        icon: Icons.receipt_long_outlined,
        title: 'Transaction history unavailable',
        message: _hasWorkspace
            ? 'Look up a customer to view their current points balance. Points history is not available here yet.'
            : 'Select a café to look up customer balances. Points history is not available here yet.',
      );
    }
    if (!_hasWorkspace) {
      return const _LoyaltyState(
        key: ValueKey('no-workspace'),
        icon: Icons.favorite_outline_rounded,
        title: 'Select a café workspace',
        message:
            'Select a café to look up members. No customer or points data is shown without an active workspace.',
      );
    }
    if (_loading) {
      return const Center(
        key: ValueKey('loading'),
        child: Text('Searching customer…',
            style: TextStyle(color: AppTheme.mutedInk, fontSize: 13)),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(
        key: const ValueKey('lookup-error'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.orangeDeep, size: 26),
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: AppTheme.ink, fontSize: 13, height: 1.5)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _lookup,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_customer == null) {
      return const _LoyaltyState(
        key: ValueKey('lookup-ready'),
        icon: Icons.people_alt_outlined,
        title: 'Find a loyalty member',
        message: 'Search by phone number to view their saved points balance.',
        note: 'Customer list unavailable',
      );
    }
    return ListView(
      key: const ValueKey('lookup-result'),
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 20),
      children: [
        _customerCard(),
        if (_settingsUnavailable && _customer!['found'] == true) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.softOrange,
                borderRadius: BorderRadius.circular(13)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppTheme.orangeDeep, size: 18),
                SizedBox(width: 9),
                Expanded(
                    child: Text(
                        'Point value unavailable. The saved points balance is shown.',
                        style: TextStyle(
                            color: AppTheme.ink, fontSize: 12, height: 1.4))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Customer list unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.mutedInk, fontSize: 11)),
      ],
    );
  }

  Widget _customerCard() {
    final customer = _customer!;
    final found = customer['found'] == true;
    final rawBalance = customer['pointsBalance'];
    final balance = rawBalance is int && rawBalance >= 0 ? rawBalance : null;
    final phone = _customerPhone ?? '';
    final maskedPhone = phone.length <= 4
        ? phone
        : '${'•' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
    final card = Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: found ? _viewCustomer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                  radius: 21,
                  backgroundColor: AppTheme.softGreen,
                  foregroundColor: AppTheme.emerald,
                  child: Icon(
                      found
                          ? Icons.person_outline_rounded
                          : Icons.person_add_alt_outlined,
                      size: 22)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(found ? 'Loyalty member' : 'No member found',
                        style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(maskedPhone,
                        style: const TextStyle(
                            color: AppTheme.mutedInk, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                        found
                            ? balance == null
                                ? 'Balance unavailable'
                                : '$balance points available'
                            : 'Add this phone to a bill to get started.',
                        style: const TextStyle(
                            color: AppTheme.mutedInk,
                            fontSize: 11,
                            height: 1.4)),
                  ],
                ),
              ),
              if (found) ...[
                const SizedBox(width: 6),
                const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Icon(Icons.chevron_right_rounded,
                        color: AppTheme.mutedInk, size: 20)),
              ],
            ],
          ),
        ),
      ),
    );
    return found
        ? Tooltip(message: 'View customer details', child: card)
        : card;
  }

  HomeScreen _homePage() => HomeScreen(
      cafeId: widget.cafeId,
      cafeRole: widget.cafeRole,
      cafeService: _service,
      stockStream: _service?.watchStock());

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _selectTab(0);
    }
  }

  void _selectTab(int index) {
    if (index == 3) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _homePage()));
      if (index == 0) return;
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => cafeTabPage(index,
              cafeId: widget.cafeId,
              cafeRole: widget.cafeRole,
              cafeService: _service)));
      return;
    }
    selectCafeTab(
        context: context,
        currentIndex: 3,
        nextIndex: index,
        pageForIndex: (index) => cafeTabPage(index,
            cafeId: widget.cafeId,
            cafeRole: widget.cafeRole,
            cafeService: _service));
  }
}

class _LoyaltyState extends StatelessWidget {
  const _LoyaltyState({
    required this.icon,
    required this.title,
    required this.message,
    this.note,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? note;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  padding: const EdgeInsets.all(17),
                  decoration: const BoxDecoration(
                      color: AppTheme.softGreen, shape: BoxShape.circle),
                  child: Icon(icon, color: AppTheme.emerald, size: 29)),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.mutedInk, fontSize: 12, height: 1.5)),
              if (note != null) ...[
                const SizedBox(height: 13),
                Text(note!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.mutedInk,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      );
}
