import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../services/cafe_service.dart';
import '../theme/app_theme.dart';

class RecipeEditorDialog extends StatefulWidget {
  const RecipeEditorDialog({
    required this.service,
    required this.product,
    super.key,
  });

  final CafeService service;
  final StockItem product;

  @override
  State<RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<RecipeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Future<Map<String, dynamic>?> _recipeFuture;
  final List<_RecipeLineDraft> _ingredients = [];
  final List<_RecipeLineDraft> _packaging = [];
  bool _initialized = false;
  bool _saving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _recipeFuture = widget.service.loadRecipe(widget.product.id);
  }

  @override
  void dispose() {
    for (final line in [..._ingredients, ..._packaging]) {
      line.quantity.dispose();
    }
    super.dispose();
  }

  void _initializeLines(Map<String, dynamic>? recipe) {
    if (_initialized) return;
    _initialized = true;
    try {
      _ingredients.addAll(_parseLines(recipe?['ingredients']));
      _packaging.addAll(_parseLines(recipe?['packaging']));
    } on FormatException catch (error) {
      _loadError = error.message;
    }
  }

  List<_RecipeLineDraft> _parseLines(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) {
      throw const FormatException('Saved recipe has an invalid line list.');
    }

    return raw.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Saved recipe contains an invalid line.');
      }
      final line = Map<String, dynamic>.from(entry);
      final id = line['stockItemId'];
      final quantity = line['quantity'];
      if (id is! String || quantity is! num || !quantity.toDouble().isFinite) {
        throw const FormatException('Saved recipe contains invalid values.');
      }
      return _RecipeLineDraft(
        stockItemId: id,
        quantity: quantity.toString(),
      );
    }).toList();
  }

  void _addLine(List<_RecipeLineDraft> lines, List<StockItem> choices) {
    if (choices.isEmpty) return;
    setState(() {
      lines.add(_RecipeLineDraft(
        stockItemId: choices.first.id,
        quantity: '1',
      ));
      _saveError = null;
    });
  }

  void _removeLine(List<_RecipeLineDraft> lines, int index) {
    setState(() {
      lines.removeAt(index).quantity.dispose();
      _saveError = null;
    });
  }

  Future<void> _save(List<StockItem> choices) async {
    if (_saving || _loadError != null) return;
    if (_ingredients.isEmpty) {
      setState(() => _saveError = 'Add at least one ingredient.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    List<Map<String, dynamic>> serialize(List<_RecipeLineDraft> lines) =>
        lines.map((line) {
          final item = choices.firstWhere(
            (candidate) => candidate.id == line.stockItemId,
          );
          return {
            'stockItemId': item.id,
            'stockItemName': item.name,
            'quantity': double.parse(line.quantity.text.trim()),
            'unit': item.unit,
          };
        }).toList();

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.service.saveRecipe(
        productId: widget.product.id,
        ingredients: serialize(_ingredients),
        packaging: serialize(_packaging),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save recipe: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: _recipeFuture,
        builder: (context, recipeSnapshot) {
          if (recipeSnapshot.hasError) {
            return _dialogShell(
              content: const Text('Could not load the saved recipe.'),
            );
          }
          if (!recipeSnapshot.hasData &&
              recipeSnapshot.connectionState != ConnectionState.done) {
            return _dialogShell(
              content: const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }

          _initializeLines(recipeSnapshot.data);
          return StreamBuilder<List<StockItem>>(
            stream: widget.service.watchStock(),
            builder: (context, stockSnapshot) {
              if (stockSnapshot.hasError) {
                return _dialogShell(
                  content: const Text('Could not load ingredient stock.'),
                );
              }
              if (!stockSnapshot.hasData) {
                return _dialogShell(
                  content: const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              final choices = stockSnapshot.data!
                  .where((item) =>
                      item.category != 'finished' &&
                      item.id != widget.product.id)
                  .toList();

              return _dialogShell(
                content: SizedBox(
                  width: 520,
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Define the quantities used for one ${widget.product.unit} of ${widget.product.name}.',
                            style: const TextStyle(
                              color: AppTheme.mutedInk,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _lineSection(
                            title: 'Ingredients',
                            lines: _ingredients,
                            choices: choices,
                            mandatory: true,
                          ),
                          const SizedBox(height: 18),
                          _lineSection(
                            title: 'Takeaway packaging',
                            lines: _packaging,
                            choices: choices,
                            mandatory: false,
                          ),
                          if (choices.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'Add ingredient stock items before configuring a recipe.',
                                style: TextStyle(color: AppTheme.copper),
                              ),
                            ),
                          if (_loadError != null || _saveError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                _loadError ?? _saveError!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                onSave: choices.isEmpty || _loadError != null || _saving
                    ? null
                    : () => _save(choices),
              );
            },
          );
        },
      );

  Widget _dialogShell({required Widget content, VoidCallback? onSave}) =>
      AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(
          'Recipe · ${widget.product.name}',
          style: const TextStyle(color: AppTheme.ink),
        ),
        content: content,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.emerald,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save recipe'),
          ),
        ],
      );

  Widget _lineSection({
    required String title,
    required List<_RecipeLineDraft> lines,
    required List<StockItem> choices,
    required bool mandatory,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _saving || choices.isEmpty
                    ? null
                    : () => _addLine(lines, choices),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add'),
              ),
            ],
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                mandatory ? 'At least one ingredient is required.' : 'Optional',
                style: const TextStyle(
                  color: AppTheme.mutedInk,
                  fontSize: 12,
                ),
              ),
            ),
          ...List.generate(lines.length, (index) {
            final line = lines[index];
            final selected = choices.any((item) => item.id == line.stockItemId)
                ? line.stockItemId
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Stock item',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 12,
                        ),
                      ),
                      items: choices
                          .map((item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                                line.stockItemId = value;
                                _saveError = null;
                              }),
                      validator: (value) =>
                          value == null ? 'Choose a stock item' : null,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: line.quantity,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Qty'),
                      validator: (value) {
                        final number = double.tryParse(value?.trim() ?? '');
                        if (number == null || !number.isFinite || number <= 0) {
                          return 'Enter a positive quantity';
                        }
                        return null;
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove line',
                    onPressed: _saving ? null : () => _removeLine(lines, index),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            );
          }),
        ],
      );
}

class _RecipeLineDraft {
  _RecipeLineDraft({required this.stockItemId, required String quantity})
      : quantity = TextEditingController(text: quantity);

  String? stockItemId;
  final TextEditingController quantity;
}
