import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models/saved_bill.dart';
import '../services/bill_history_service.dart';
import '../services/server_connection.dart';
import '../services/bill_reprint_service.dart';
import '../theme/app_theme.dart';
import 'thermal_printer_dialog.dart';

String _historyError(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Café access could not be verified. Check your workspace or sign in again.';
  }
  if (error is ArgumentError) return error.message.toString();
  return 'Could not load saved bills. Check your connection and try again.';
}

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({required this.cafeId, this.repository, super.key});
  final String cafeId;
  final BillHistoryRepository? repository;
  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  late BillHistoryRepository _repository;
  final _search = TextEditingController();
  BillSearchKind _kind = BillSearchKind.billId;
  DateTimeRange? _range;
  BillHistoryFilter _filter = const BillHistoryFilter();
  final _bills = <SavedBill>[];
  Object? _cursor;
  bool _hasMore = false;
  bool _usingCache = false;
  bool _loading = false;
  String? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _connect();
    ServerConnection.instance.addListener(_connectionChanged);
  }

  void _connectionChanged() {
    if (_usingCache &&
        ServerConnection.instance.managed &&
        ServerConnection.instance.state == ServerReadState.confirmed &&
        !_loading) {
      unawaited(_load(reset: true));
    }
  }

  void _connect() {
    _repository = widget.repository ??
        FirestoreBillHistoryRepository(cafeId: widget.cafeId);
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant BillHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cafeId != widget.cafeId ||
        oldWidget.repository != widget.repository) {
      _search.clear();
      _range = null;
      _filter = const BillHistoryFilter();
      _kind = BillSearchKind.billId;
      _connect();
    }
  }

  @override
  void dispose() {
    ServerConnection.instance.removeListener(_connectionChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _bills.clear();
        _cursor = null;
        _hasMore = false;
      }
    });
    try {
      if (_repository.cafeId != widget.cafeId) {
        throw StateError('Workspace mismatch');
      }
      final page = await _repository.load(filter: _filter, cursor: _cursor);
      if (!mounted || version != _version) return;
      if (page.bills.any((bill) => bill.text('cafeId') != widget.cafeId)) {
        throw StateError('Workspace mismatch');
      }
      setState(() {
        final ids = _bills.map((bill) => bill.id).toSet();
        _bills.addAll(page.bills.where((bill) => ids.add(bill.id)));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _usingCache = page.fromCache;
      });
    } catch (error) {
      if (mounted && version == _version) {
        setState(() => _error = _historyError(error));
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  void _apply() {
    _filter = BillHistoryFilter(
        search: _search.text,
        kind: _kind,
        start: _range?.start,
        endExclusive: _range == null
            ? null
            : DateTime(
                _range!.end.year, _range!.end.month, _range!.end.day + 1));
    unawaited(_load(reset: true));
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: _range,
        helpText: 'Filter bill dates');
    if (!mounted || range == null) return;
    setState(() => _range = range);
    _apply();
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: AppTheme.emeraldLight,
      child: Scaffold(
        appBar: AppBar(title: const Text('Bill History'), actions: [
          IconButton(
              tooltip: 'Refresh bills',
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.refresh)),
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Column(children: [
                        Row(children: [
                          DropdownButton<BillSearchKind>(
                              value: _kind,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                    value: BillSearchKind.billId,
                                    child: Text('Bill ID')),
                                DropdownMenuItem(
                                    value: BillSearchKind.phone,
                                    child: Text('Phone'))
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _kind = value;
                                    _search.clear();
                                  });
                                  _apply();
                                }
                              }),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextField(
                                  controller: _search,
                                  keyboardType: _kind == BillSearchKind.phone
                                      ? TextInputType.phone
                                      : TextInputType.text,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                      labelText: _kind == BillSearchKind.phone
                                          ? 'Full phone (+country code)'
                                          : 'Complete bill ID',
                                      suffixIcon: IconButton(
                                          tooltip: 'Search bills',
                                          onPressed: _apply,
                                          icon: const Icon(Icons.search))),
                                  onSubmitted: (_) => _apply())),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                                  onPressed: _chooseDates,
                                  icon: const Icon(Icons.date_range_outlined),
                                  label: Text(_range == null
                                      ? 'All dates'
                                      : '${billDate(_range!.start).split(' · ').first} – ${billDate(_range!.end).split(' · ').first}'))),
                          if (_range != null || _search.text.isNotEmpty)
                            IconButton(
                                tooltip: 'Clear filters',
                                onPressed: () {
                                  setState(() {
                                    _range = null;
                                    _search.clear();
                                  });
                                  _apply();
                                },
                                icon: const Icon(Icons.clear)),
                        ]),
                        if (_kind == BillSearchKind.phone)
                          const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                  'Only bills with a saved customer phone can match.',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.mutedInk))),
                      ])),
                  Expanded(
                      child: _loading && _bills.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                  if (_usingCache)
                                    const Padding(
                                        padding: EdgeInsets.only(bottom: 12),
                                        child: Text(
                                            'Cached bills — may be out of date. Reconnect to verify.')),
                                  if (_bills.isEmpty && _error == null)
                                    const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 48),
                                        child: Column(children: [
                                          Icon(Icons.receipt_long_outlined,
                                              size: 42,
                                              color: AppTheme.mutedInk),
                                          SizedBox(height: 12),
                                          Text('No bills found'),
                                          SizedBox(height: 6),
                                          Text(
                                              'Try another search or date range.',
                                              textAlign: TextAlign.center)
                                        ])),
                                  ..._bills.map((bill) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Card(
                                          child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    BillDetailsScreen(
                                                        billId: bill.id,
                                                        repository:
                                                            _repository))),
                                        child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                            child: Text(
                                                                billMoney(
                                                                    bill.amount(
                                                                        'total')),
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        20,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700))),
                                                        const SizedBox(
                                                            width: 8),
                                                        Flexible(
                                                            child: Text(
                                                                bill
                                                                    .statusLabel,
                                                                textAlign:
                                                                    TextAlign
                                                                        .right)),
                                                      ]),
                                                  const SizedBox(height: 6),
                                                  Text(bill.id,
                                                      style: const TextStyle(
                                                          fontSize: 12)),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      '${billDate(bill.createdAt)} · ${bill.orderLabel}'),
                                                  if (bill.customerName !=
                                                          null ||
                                                      bill.customerPhone !=
                                                          null)
                                                    Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 6),
                                                        child: Text([
                                                          if (bill.customerName !=
                                                              null)
                                                            bill.customerName!,
                                                          if (bill.customerPhone !=
                                                              null)
                                                            bill.maskedPhone
                                                        ].join(' · '))),
                                                ])),
                                      )))),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(children: [
                                          Text(_error!,
                                              textAlign: TextAlign.center),
                                          TextButton.icon(
                                              onPressed: () =>
                                                  _load(reset: _bills.isEmpty),
                                              icon: const Icon(Icons.refresh),
                                              label: const Text('Try again')),
                                        ])),
                                  if (_loading)
                                    const Center(
                                        child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator()))
                                  else if (_hasMore && _error == null)
                                    OutlinedButton(
                                        onPressed: _load,
                                        child: const Text('Load more bills')),
                                ])),
                ]))),
      ));
}

typedef BillPrinterOpener = Future<void> Function(
    BuildContext context, SavedBill bill);

class BillDetailsScreen extends StatefulWidget {
  const BillDetailsScreen(
      {required this.billId,
      required this.repository,
      this.printerOpener,
      super.key});
  final String billId;
  final BillHistoryRepository repository;
  final BillPrinterOpener? printerOpener;
  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  SavedBill? _bill;
  String? _error;
  bool _loading = true;
  bool _printing = false;
  bool _showPhone = false;
  late final BillReprintService _reprints =
      BillReprintService(widget.repository);
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _bill = null;
    });
    try {
      final bill = await widget.repository.get(widget.billId);
      if (!mounted) return;
      if (bill == null ||
          bill.id != widget.billId ||
          bill.text('cafeId') != widget.repository.cafeId) {
        setState(() => _error = 'Bill not found in this café.');
      } else {
        setState(() => _bill = bill);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _historyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await _reprints.reprint(widget.billId, (fresh) async {
        if (!mounted) return;
        setState(() => _bill = fresh);
        if (widget.printerOpener != null) {
          await widget.printerOpener!(context, fresh);
          return;
        }
        await showDialog<void>(
            context: context,
            useRootNavigator: false,
            barrierDismissible: false,
            builder: (_) => ThermalPrinterDialog(
                cafeId: widget.repository.cafeId,
                cafeName: fresh.text('cafeName') ?? 'BrewVerse receipt copy',
                billNumber: fresh.id,
                orderType: fresh.text('orderType')!,
                items: fresh.items,
                total: fresh.amount('total')!.toDouble(),
                discount: fresh.amount('discount')!.toDouble(),
                issuedAt: fresh.createdAt,
                transactionStatus: fresh.text('status'),
                isReprint: true));
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not prepare this saved receipt. Verify access and saved bill details, then retry. No sale was created.')));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Text(label, style: const TextStyle(color: AppTheme.mutedInk))),
        const SizedBox(width: 12),
        Flexible(child: Text(value, textAlign: TextAlign.right)),
      ]));

  @override
  Widget build(BuildContext context) => Theme(
      data: AppTheme.emeraldLight,
      child: Scaffold(
        appBar: AppBar(title: const Text('Bill details')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _bill == null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error ?? 'Bill unavailable',
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: _load, child: const Text('Try again')),
                        ])))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (_bill!.isFromCache)
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Text(
                                        'Cached bill — may be out of date. Reconnect to verify.')),
                              SelectableText(_bill!.id,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              _row('Date and time', billDate(_bill!.createdAt)),
                              _row('Order type', _bill!.orderLabel),
                              _row('Status', _bill!.statusLabel),
                              if (_bill!.customerName != null)
                                _row('Customer', _bill!.customerName!),
                              if (_bill!.customerPhone == null)
                                _row('Customer phone', 'Not recorded')
                              else
                                Row(children: [
                                  Expanded(
                                      child: _row(
                                          'Customer phone',
                                          _showPhone
                                              ? _bill!.customerPhone!
                                              : _bill!.maskedPhone)),
                                  IconButton(
                                      tooltip: _showPhone
                                          ? 'Hide customer phone'
                                          : 'Show customer phone',
                                      onPressed: () => setState(
                                          () => _showPhone = !_showPhone),
                                      icon: Icon(_showPhone
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined))
                                ]),
                              const Divider(height: 28),
                              const Text('Items',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              if (_bill!.items.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('Item details not recorded')),
                              ..._bill!.items.map((line) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            line['name'] is String
                                                ? line['name'] as String
                                                : 'Name not recorded',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        _row(
                                            'Quantity',
                                            line['quantity'] is num
                                                ? '${line['quantity']}'
                                                : 'Not recorded'),
                                        _row('Unit price',
                                            billMoney(line['unitPrice'])),
                                        _row('Line total',
                                            billMoney(line['lineTotal'])),
                                      ]))),
                              const Divider(),
                              _row('Subtotal',
                                  billMoney(_bill!.amount('subtotal'))),
                              _row('Discount',
                                  billMoney(_bill!.amount('discount'))),
                              if (_bill!.loyalty?['pointsRedeemed'] is num)
                                _row('Loyalty points redeemed',
                                    '${_bill!.loyalty!['pointsRedeemed']}'),
                              if (_bill!.loyalty?['pointsEarned'] is num)
                                _row('Loyalty points earned',
                                    '${_bill!.loyalty!['pointsEarned']}'),
                              _row('Bill total',
                                  billMoney(_bill!.amount('total'))),
                              if (_bill!.amount('refundedMinor') != null)
                                _row(
                                    'Refunded',
                                    billMoney(
                                        _bill!.amount('refundedMinor')! / 100)),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                  onPressed:
                                      _printing || !_bill!.hasReceiptFields
                                          ? null
                                          : _print,
                                  icon: _printing
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.print_outlined),
                                  label: Text(_printing
                                      ? 'Preparing receipt…'
                                      : 'Reprint receipt')),
                              const SizedBox(height: 10),
                              Text(
                                  _bill!.hasReceiptFields
                                      ? 'Prints a copy of this saved bill. The sale, stock and loyalty points stay unchanged.'
                                      : 'Reprinting requires complete saved item prices, discounts, total and order type.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.mutedInk)),
                            ]))),
      ));
}
