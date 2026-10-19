import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_functions_service.dart';
import '../theme/app_theme.dart';

class BillAdjustmentScreen extends StatefulWidget {
  const BillAdjustmentScreen({
    required this.cafeId,
    required this.role,
    this.functionsService,
    super.key,
  });

  final String cafeId;
  final CafeRole role;
  final CafeFunctionsService? functionsService;

  @override
  State<BillAdjustmentScreen> createState() => _BillAdjustmentScreenState();
}

class _BillAdjustmentScreenState extends State<BillAdjustmentScreen> {
  late final CafeFunctionsService _service =
      widget.functionsService ?? CafeFunctionsService();
  final _billId = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _working = false;
  String? _error;
  String? _result;
  String? _pendingAdjustmentKey;
  String? _pendingAdjustmentId;

  bool get _canAdjust =>
      widget.role == CafeRole.owner || widget.role == CafeRole.manager;

  @override
  void dispose() {
    _billId.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _newAdjustmentId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${Random.secure().nextInt(1 << 32).toRadixString(36)}';

  Future<bool> _confirm(
      {required bool isVoid, required int? amountMinor}) async {
    return await showDialog<bool>(
          useRootNavigator: false,
          context: context,
          builder: (context) => AlertDialog(
            title: Text(isVoid ? 'Void this bill?' : 'Issue this refund?'),
            content: Text(isVoid
                ? 'The bill will be marked void, loyalty points will be reversed according to café policy, and consumed stock will not be restored.'
                : 'Refund ₹${(amountMinor! / 100).toStringAsFixed(2)}. Loyalty points will be adjusted according to café policy.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isVoid ? 'Void bill' : 'Refund'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _adjust({required bool isVoid}) async {
    if (!_canAdjust || _working) return;
    final billId = _billId.text.trim();
    if (billId.isEmpty || billId.contains('/')) {
      setState(() => _error = 'Enter a valid bill ID.');
      return;
    }
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason for the adjustment.');
      return;
    }
    int? amountMinor;
    if (!isVoid) {
      final amount = double.tryParse(_amount.text.trim());
      if (amount == null ||
          !amount.isFinite ||
          amount <= 0 ||
          amount > 100000000000) {
        setState(() => _error = 'Enter a valid refund amount.');
        return;
      }
      amountMinor = (amount * 100).round();
    }
    if (!await _confirm(isVoid: isVoid, amountMinor: amountMinor) || !mounted) {
      return;
    }
    final requestKey = jsonEncode([billId, isVoid, amountMinor, reason]);
    if (_pendingAdjustmentKey != requestKey || _pendingAdjustmentId == null) {
      _pendingAdjustmentKey = requestKey;
      _pendingAdjustmentId = _newAdjustmentId();
    }
    setState(() {
      _working = true;
      _error = null;
      _result = null;
    });
    final adjustmentId = _pendingAdjustmentId!;
    try {
      final result = isVoid
          ? await _service.voidBill(
              cafeId: widget.cafeId,
              billId: billId,
              adjustmentId: adjustmentId,
              reason: reason,
            )
          : await _service.refundBill(
              cafeId: widget.cafeId,
              billId: billId,
              adjustmentId: adjustmentId,
              amountMinor: amountMinor!,
              reason: reason,
            );
      if (!mounted) return;
      final refundedMinor = result['refundedMinor'];
      setState(() {
        _pendingAdjustmentId = null;
        _pendingAdjustmentKey = null;
        _result = result['duplicate'] == true
            ? 'This adjustment was already applied.'
            : '${result['status']} · refunded ₹${refundedMinor is int ? (refundedMinor / 100).toStringAsFixed(2) : '0.00'}';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          appBar: AppBar(title: const Text('Refund or void bill')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_canAdjust)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title:
                        Text('Only café owners and managers can adjust bills.'),
                  ),
                ),
              const Text(
                'Adjustments are recorded in the café ledger. Refunds reduce recorded revenue. Voids and refunds do not restore prepared stock automatically.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _billId,
                enabled: _canAdjust && !_working,
                decoration: const InputDecoration(
                  labelText: 'Bill ID',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                enabled: _canAdjust && !_working,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Refund amount',
                  prefixText: '₹',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: _canAdjust && !_working,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 8),
                Text(_result!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: !_canAdjust || _working
                    ? null
                    : () => _adjust(isVoid: false),
                icon: const Icon(Icons.currency_exchange_rounded),
                label: const Text('Issue refund'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: !_canAdjust || _working
                    ? null
                    : () => _adjust(isVoid: true),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Void remaining bill'),
              ),
              if (_working) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      );
}
