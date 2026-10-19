import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_functions_service.dart';
import '../theme/app_theme.dart';

class LoyaltySettingsScreen extends StatefulWidget {
  const LoyaltySettingsScreen({
    required this.cafeId,
    required this.role,
    this.functionsService,
    super.key,
  });

  final String cafeId;
  final CafeRole role;
  final CafeFunctionsService? functionsService;

  @override
  State<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends State<LoyaltySettingsScreen> {
  late final CafeFunctionsService _service =
      widget.functionsService ?? CafeFunctionsService();
  final _formKey = GlobalKey<FormState>();
  final _spendUnit = TextEditingController();
  final _pointsPerUnit = TextEditingController();
  final _pointValue = TextEditingController();
  final _redemptionPercent = TextEditingController();
  final _expiryMonths = TextEditingController();
  final List<({TextEditingController spend, TextEditingController points})>
      _bonusTiers = [];
  bool _enabled = true;
  bool _expiryEnabled = true;
  bool _reverseEarnedOnRefund = true;
  bool _restoreRedeemedOnRefund = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canEdit => widget.role == CafeRole.owner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _spendUnit.dispose();
    _pointsPerUnit.dispose();
    _pointValue.dispose();
    _redemptionPercent.dispose();
    _expiryMonths.dispose();
    for (final tier in _bonusTiers) {
      tier.spend.dispose();
      tier.points.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.getLoyaltySettings(cafeId: widget.cafeId);
      if (!mounted) return;
      _enabled = settings['enabled'] as bool;
      _spendUnit.text = _rupees(settings['spendUnitMinor']);
      _pointsPerUnit.text = '${settings['pointsPerSpendUnit']}';
      _pointValue.text = _rupees(settings['pointValueMinor']);
      _redemptionPercent.text = '${settings['maxRedemptionPercent']}';
      final expiry = settings['expiryMonths'];
      _expiryEnabled = expiry is int;
      _expiryMonths.text = expiry is int ? '$expiry' : '12';
      _reverseEarnedOnRefund =
          settings['reverseEarnedOnRefund'] as bool? ?? true;
      _restoreRedeemedOnRefund =
          settings['restoreRedeemedOnRefund'] as bool? ?? true;
      for (final tier in _bonusTiers) {
        tier.spend.dispose();
        tier.points.dispose();
      }
      _bonusTiers
        ..clear()
        ..addAll(
            (settings['bonusTiers'] as List).whereType<Map>().map((tier) => (
                  spend: TextEditingController(
                    text: _rupees(tier['minimumSpendMinor']),
                  ),
                  points: TextEditingController(text: '${tier['points']}'),
                )));
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _rupees(dynamic minorUnits) =>
      minorUnits is num ? (minorUnits / 100).toStringAsFixed(2) : '';

  double? _amount(String value) => double.tryParse(value.trim());

  int _rupeesToMinor(String value, String field) {
    final amount = _amount(value);
    if (amount == null || !amount.isFinite || amount <= 0 || amount > 1000000) {
      throw FormatException(
          '$field must be greater than ₹0 and at most ₹1,000,000.');
    }
    return (amount * 100).round();
  }

  int _wholeNumber(String value, String field,
      {int minimum = 0, int maximum = 100000}) {
    final number = int.tryParse(value.trim());
    if (number == null || number < minimum || number > maximum) {
      throw FormatException(
          '$field must be a whole number from $minimum to $maximum.');
    }
    return number;
  }

  Map<String, dynamic> _settingsFromForm() => {
        'enabled': _enabled,
        'spendUnitMinor': _rupeesToMinor(_spendUnit.text, 'Spend unit'),
        'pointsPerSpendUnit':
            _wholeNumber(_pointsPerUnit.text, 'Earned points'),
        'pointValueMinor': _rupeesToMinor(_pointValue.text, 'Point value'),
        'maxRedemptionPercent': _wholeNumber(
            _redemptionPercent.text, 'Redemption limit',
            maximum: 100),
        'bonusTiers': [
          for (final tier in _bonusTiers)
            {
              'minimumSpendMinor':
                  _rupeesToMinor(tier.spend.text, 'Bonus threshold'),
              'points': _wholeNumber(tier.points.text, 'Bonus points'),
            },
        ],
        'expiryMonths': _expiryEnabled
            ? _wholeNumber(_expiryMonths.text, 'Expiry months',
                minimum: 1, maximum: 120)
            : null,
        'reverseEarnedOnRefund': _reverseEarnedOnRefund,
        'restoreRedeemedOnRefund': _restoreRedeemedOnRefund,
      };

  Future<void> _save() async {
    if (!_canEdit || _saving || !_formKey.currentState!.validate()) return;
    late final Map<String, dynamic> settings;
    try {
      settings = _settingsFromForm();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveLoyaltySettings(
        cafeId: widget.cafeId,
        settings: settings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loyalty policy saved.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TextFormField _numberField(
    TextEditingController controller,
    String label, {
    String? prefix,
    bool decimal = false,
    int maximumLength = 12,
  }) =>
      TextFormField(
        controller: controller,
        enabled: _canEdit && !_loading && !_saving,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        maxLength: maximumLength,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          counterText: '',
        ),
        validator: (value) {
          final number =
              decimal ? _amount(value ?? '') : int.tryParse(value ?? '');
          if (number == null || !number.isFinite || number < 0) {
            return 'Enter a valid non-negative number';
          }
          return null;
        },
      );

  void _addBonusTier() {
    setState(() {
      _bonusTiers.add((
        spend: TextEditingController(),
        points: TextEditingController(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          appBar: AppBar(title: const Text('Loyalty settings')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (!_canEdit)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.lock_outline),
                            title: Text(
                                'Only the café owner can edit loyalty rules.'),
                          ),
                        ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable loyalty points'),
                        value: _enabled,
                        onChanged: !_canEdit || _saving
                            ? null
                            : (value) => setState(() => _enabled = value),
                      ),
                      const SizedBox(height: 12),
                      _numberField(_spendUnit, 'Spend amount per earning step',
                          prefix: '₹', decimal: true),
                      const SizedBox(height: 12),
                      _numberField(_pointsPerUnit, 'Points earned per step'),
                      const SizedBox(height: 12),
                      _numberField(_pointValue, 'Rupee value of one point',
                          prefix: '₹', decimal: true),
                      const SizedBox(height: 12),
                      _numberField(
                        _redemptionPercent,
                        'Maximum bill percentage payable with points',
                        maximumLength: 3,
                      ),
                      const SizedBox(height: 16),
                      Text('Bonus tiers',
                          style: Theme.of(context).textTheme.titleLarge),
                      for (var index = 0; index < _bonusTiers.length; index++)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _numberField(
                                    _bonusTiers[index].spend,
                                    'Order spend threshold',
                                    prefix: '₹',
                                    decimal: true,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _numberField(
                                    _bonusTiers[index].points,
                                    'Bonus points',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove bonus tier',
                                  onPressed: !_canEdit || _saving
                                      ? null
                                      : () => setState(() {
                                            final tier =
                                                _bonusTiers.removeAt(index);
                                            tier.spend.dispose();
                                            tier.points.dispose();
                                          }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              !_canEdit || _saving || _bonusTiers.length >= 10
                                  ? null
                                  : _addBonusTier,
                          icon: const Icon(Icons.add),
                          label: const Text('Add bonus tier'),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Expire points'),
                        subtitle: const Text('Default expiry is 12 months.'),
                        value: _expiryEnabled,
                        onChanged: !_canEdit || _saving
                            ? null
                            : (value) => setState(() => _expiryEnabled = value),
                      ),
                      if (_expiryEnabled)
                        _numberField(_expiryMonths, 'Expire after months',
                            maximumLength: 3),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reverse earned points on refunds'),
                        value: _reverseEarnedOnRefund,
                        onChanged: !_canEdit || _saving
                            ? null
                            : (value) =>
                                setState(() => _reverseEarnedOnRefund = value),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Restore redeemed points on refunds'),
                        value: _restoreRedeemedOnRefund,
                        onChanged: !_canEdit || _saving
                            ? null
                            : (value) => setState(
                                () => _restoreRedeemedOnRefund = value),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: !_canEdit || _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save loyalty policy'),
                      ),
                    ],
                  ),
                ),
        ),
      );
}
