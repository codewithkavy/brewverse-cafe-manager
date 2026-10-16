import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../services/cafe_service.dart';

const Color _bg = Color(0xFF171210);
const Color _panel = Color(0xFF241B17);
const Color _card = Color(0xFF30231D);
const Color _caramel = Color(0xFFE5A365);
const Color _copper = Color(0xFFC7794D);
const Color _cream = Color(0xFFF5E9DD);
const Color _muted = Color(0xFFBDA99A);

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CafeService();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Inventory'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _caramel,
        foregroundColor: _bg,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _AddItemDialog(service: service),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: StreamBuilder<List<StockItem>>(
        stream: service.watchStock(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load inventory. Check your connection.',
                  style: TextStyle(color: _cream),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _caramel),
            );
          }

          final items = snapshot.data!;

          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No stock items yet. Tap Add item to begin.',
                style: TextStyle(color: _muted),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return Card(
                    color: _card,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: item.isLow
                            ? _copper.withValues(alpha: 0.35)
                            : Colors.white10,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor:
                        _caramel.withValues(alpha: 0.13),
                        backgroundImage: item.photoUrl.isNotEmpty
                            ? NetworkImage(item.photoUrl)
                            : null,
                        child: item.photoUrl.isEmpty
                            ? const Icon(
                          Icons.coffee_rounded,
                          color: _caramel,
                        )
                            : null,
                      ),
                      title: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _cream,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '${item.quantity} ${item.unit} in stock'
                              '\nMinimum: ${item.minimumQuantity} ${item.unit}'
                              '\nPurchase: ₹${item.purchasePricePerUnit}'
                              '  •  Selling: ₹${item.sellingPrice}',
                          style: const TextStyle(
                            color: _muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                      isThreeLine: true,
                      trailing: SizedBox(
                        width: 112,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Edit item',
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 40,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => _EditItemDialog(
                                  service: service,
                                  item: item,
                                ),
                              ),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: _cream,
                                size: 21,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add stock',
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 40,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => _AddStockDialog(
                                  service: service,
                                  item: item,
                                ),
                              ),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                                color: _caramel,
                              ),
                            ),
                            if (item.isLow)
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: _copper,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddStockDialog extends StatefulWidget {
  const _AddStockDialog({
    required this.service,
    required this.item,
  });

  final CafeService service;
  final StockItem item;

  @override
  State<_AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends State<_AddStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController(text: 'Supplier delivery');

  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final amount = double.parse(_quantity.text.trim());
    final reason = _reason.text.trim().isEmpty
        ? 'Stock addition'
        : _reason.text.trim();

    setState(() => _saving = true);

    try {
      await widget.service.addStock(
        itemId: widget.item.id,
        quantity: amount,
        reason: reason,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add stock: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      title: const Text('Add stock', style: TextStyle(color: _cream)),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.item.name,
                  style: const TextStyle(color: _caramel),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantity,
                enabled: !_saving,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: _cream),
                decoration: InputDecoration(
                  labelText: 'Quantity (${widget.item.unit})',
                  labelStyle: const TextStyle(color: _muted),
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null ||
                      !amount.isFinite ||
                      amount <= 0) {
                    return 'Enter a quantity greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                enabled: !_saving,
                style: const TextStyle(color: _cream),
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  labelStyle: TextStyle(color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: _caramel,
            foregroundColor: _bg,
          ),
          child: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Save stock'),
        ),
      ],
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.service});

  final CafeService service;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '0');
  final _minimum = TextEditingController(text: '5');
  final _purchase = TextEditingController(text: '0');
  final _selling = TextEditingController(text: '0');

  String _category = 'ingredient';
  String _unit = 'g';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _minimum.dispose();
    _purchase.dispose();
    _selling.dispose();
    super.dispose();
  }

  double? _number(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    return value != null && value.isFinite ? value : null;
  }

  String? _validateNumber(
      String? input,
      TextEditingController controller,
      String label,
      ) {
    final value = _number(controller);
    if (value == null) return 'Enter a valid $label';
    if (value < 0) return '$label cannot be negative';
    return null;
  }

  Future<void> _saveItem() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final item = StockItem(
        id: '',
        name: _name.text.trim(),
        category: _category,
        unit: _unit,
        quantity: _number(_quantity)!,
        minimumQuantity: _number(_minimum)!,
        purchasePricePerUnit: _number(_purchase)!,
        sellingPrice: _number(_selling)!,
      );

      await widget.service.addItem(item);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save item: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      title: const Text(
        'Add stock item',
        style: TextStyle(color: _cream),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  style: const TextStyle(color: _cream),
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? 'Enter an item name'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Stock type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'ingredient',
                      child: Text('Ingredient'),
                    ),
                    DropdownMenuItem(
                      value: 'finished',
                      child: Text('Finished product'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                        () => _category = value ?? 'ingredient',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('Grams (g)')),
                    DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                    DropdownMenuItem(value: 'ml', child: Text('Millilitres (ml)')),
                    DropdownMenuItem(value: 'L', child: Text('Litres (L)')),
                    DropdownMenuItem(value: 'piece', child: Text('Pieces')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _unit = value ?? 'g'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening quantity',
                  ),
                  validator: (value) => _validateNumber(
                    value, _quantity, 'opening quantity',
                  ),
                ),
                TextFormField(
                  controller: _minimum,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Minimum stock alert level',
                  ),
                  validator: (value) => _validateNumber(
                    value, _minimum, 'minimum stock level',
                  ),
                ),
                TextFormField(
                  controller: _purchase,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Purchase cost per unit (₹)',
                  ),
                  validator: (value) => _validateNumber(
                    value, _purchase, 'purchase cost',
                  ),
                ),
                TextFormField(
                  controller: _selling,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price (₹)',
                  ),
                  validator: (value) => _validateNumber(
                    value, _selling, 'selling price',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can add a product photo later.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _saveItem,
          style: FilledButton.styleFrom(
            backgroundColor: _caramel,
            foregroundColor: _bg,
          ),
          child: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Save item'),
        ),
      ],
    );
  }
}

class _EditItemDialog extends StatefulWidget {
  const _EditItemDialog({
    required this.service,
    required this.item,
  });

  final CafeService service;
  final StockItem item;

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minimum;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;

  late String _category;
  late String _unit;
  bool _saving = false;

  static const List<String> _units = ['g', 'kg', 'ml', 'L', 'piece'];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item.name);
    _minimum = TextEditingController(
      text: item.minimumQuantity.toString(),
    );
    _purchase = TextEditingController(
      text: item.purchasePricePerUnit.toString(),
    );
    _selling = TextEditingController(text: item.sellingPrice.toString());
    _category = item.category;
    _unit = _units.contains(item.unit) ? item.unit : 'piece';
  }

  @override
  void dispose() {
    _name.dispose();
    _minimum.dispose();
    _purchase.dispose();
    _selling.dispose();
    super.dispose();
  }

  double? _number(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    return value != null && value.isFinite ? value : null;
  }

  String? _validateNumber(
      String? input,
      TextEditingController controller,
      String label,
      ) {
    final value = _number(controller);
    if (value == null) return 'Enter a valid $label';
    if (value < 0) return '$label cannot be negative';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final old = widget.item;

      final updated = StockItem(
        id: old.id,
        name: _name.text.trim(),
        category: _category,
        unit: _unit,
        // This value is preserved again by CafeService.updateItem.
        quantity: old.quantity,
        minimumQuantity: _number(_minimum)!,
        purchasePricePerUnit: _number(_purchase)!,
        sellingPrice: _number(_selling)!,
        photoUrl: old.photoUrl,
      );

      await widget.service.updateItem(updated);

      if (!mounted) return;
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item details updated successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update item: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      title: const Text(
        'Edit item details',
        style: TextStyle(color: _cream),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  style: const TextStyle(color: _cream),
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? 'Enter an item name'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Stock type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'ingredient',
                      child: Text('Ingredient'),
                    ),
                    DropdownMenuItem(
                      value: 'finished',
                      child: Text('Finished product'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                        () => _category = value ?? _category,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('Grams (g)')),
                    DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                    DropdownMenuItem(value: 'ml', child: Text('Millilitres (ml)')),
                    DropdownMenuItem(value: 'L', child: Text('Litres (L)')),
                    DropdownMenuItem(value: 'piece', child: Text('Pieces')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                        () => _unit = value ?? _unit,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue:
                  '${widget.item.quantity} ${widget.item.unit}',
                  readOnly: true,
                  style: const TextStyle(color: _muted),
                  decoration: const InputDecoration(
                    labelText: 'Current quantity (unchanged)',
                  ),
                ),
                TextFormField(
                  controller: _minimum,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Minimum stock alert level',
                  ),
                  validator: (value) => _validateNumber(
                    value, _minimum, 'minimum stock level',
                  ),
                ),
                TextFormField(
                  controller: _purchase,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Purchase cost per unit (₹)',
                  ),
                  validator: (value) => _validateNumber(
                    value, _purchase, 'purchase cost',
                  ),
                ),
                TextFormField(
                  controller: _selling,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price (₹)',
                  ),
                  validator: (value) => _validateNumber(
                    value, _selling, 'selling price',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: _caramel,
            foregroundColor: _bg,
          ),
          child: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Save changes'),
        ),
      ],
    );
  }
}