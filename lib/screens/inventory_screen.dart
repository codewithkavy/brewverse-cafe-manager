import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../services/server_connection.dart';
import '../services/photo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import '../widgets/inventory_form_shell.dart';
import 'home_screen.dart';
import 'recipe_editor_dialog.dart';

const Color _panel = AppTheme.card;
const Color _card = AppTheme.card;
const Color _caramel = AppTheme.emerald;
const Color _copper = AppTheme.orange;
const Color _cream = AppTheme.ink;
const Color _muted = AppTheme.mutedInk;

String? _validateItemName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter an item name';
  if (name.length > 120) return 'Item name must be 120 characters or fewer';
  return null;
}

Widget _stockPhoto(String url, {double size = 40, bool product = false}) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: AppTheme.softGreen,
          child: url.isEmpty
              ? Icon(
                  product
                      ? Icons.local_cafe_outlined
                      : Icons.inventory_2_outlined,
                  color: AppTheme.emerald,
                  size: size * 0.5)
              : Image.network(url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppTheme.mutedInk,
                      size: 22)),
        ),
      ),
    );

String _stockNumber(num value) =>
    value.toString().replaceFirst(RegExp(r'\.0$'), '');

enum _StockAction { edit, addStock, recipe }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    this.cafeId,
    this.cafeRole,
    this.canManageInventory = true,
    this.openAddItemOnStart = false,
    this.cafeService,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final bool canManageInventory;
  final bool openAddItemOnStart;
  final CafeService? cafeService;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final CafeService service =
      widget.cafeService ?? CafeService(cafeId: widget.cafeId);
  late final Stream<List<StockItem>> _stockStream;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _stockStream = service.watchStock();
    if (widget.openAddItemOnStart && widget.canManageInventory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAddItemDialog();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<T?> _openDialog<T>(Widget page) => showDialog<T>(
        useRootNavigator: false,
        context: context,
        builder: (_) => Theme(data: AppTheme.emeraldLight, child: page),
      );

  Future<void> _openForm(Widget page, String successMessage) async {
    final saved = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (_) => ScaffoldMessenger(
        child: Theme(data: AppTheme.emeraldLight, child: page),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  }

  void _showAddItemDialog() {
    if (!ServerConnection.instance.canWrite) return;
    _openForm(_AddItemDialog(service: service), 'Stock item saved.');
  }

  void _itemAction(_StockAction action, StockItem item) {
    if (!widget.canManageInventory || !ServerConnection.instance.canWrite) {
      return;
    }
    switch (action) {
      case _StockAction.edit:
        _openForm(_EditItemDialog(service: service, item: item),
            'Item details updated successfully.');
      case _StockAction.addStock:
        _openForm(_AddStockDialog(service: service, item: item),
            'Stock added successfully.');
      case _StockAction.recipe:
        if (item.isRecipeProduct) {
          _openDialog<bool>(
              RecipeEditorDialog(service: service, product: item));
        }
    }
  }

  void _showItemDetails(StockItem item) => _openDialog<void>(
        AlertDialog(
          title: Text(item.name),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stockPhoto(item.photoUrl,
                      size: 68, product: item.category == 'finished'),
                  const SizedBox(height: 16),
                  _detailRow(
                      'Stock type',
                      item.category == 'finished'
                          ? 'Finished product'
                          : 'Ingredient'),
                  if (item.category == 'finished')
                    _detailRow(
                        'Stock deduction',
                        item.isRecipeProduct
                            ? 'Recipe ingredients'
                            : 'Direct stock'),
                  _detailRow('Current quantity',
                      '${_stockNumber(item.quantity)} ${item.unit}'),
                  _detailRow('Minimum quantity',
                      '${_stockNumber(item.minimumQuantity)} ${item.unit}'),
                  _detailRow('Purchase price',
                      '₹${item.purchasePricePerUnit.toStringAsFixed(2)}'),
                  _detailRow('Selling price',
                      '₹${item.sellingPrice.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close')),
          ],
        ),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: _muted, fontSize: 12))),
            const SizedBox(width: 12),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: _cream,
                        fontSize: 13,
                        fontWeight: FontWeight.w600))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ServerConnection.instance,
        builder: (context, _) => Theme(
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
              title: const Text('Inventory',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              actions: [
                IconButton(
                  tooltip: 'Stock movement history',
                  onPressed: () => _openDialog<void>(
                      _MovementHistoryDialog(service: service)),
                  icon: const Icon(Icons.history_rounded, size: 21),
                ),
                if (widget.canManageInventory)
                  IconButton.filled(
                    tooltip: 'Add item',
                    style: IconButton.styleFrom(
                      backgroundColor: _copper,
                      foregroundColor: AppTheme.forest,
                      minimumSize: const Size(36, 36),
                    ),
                    onPressed: ServerConnection.instance.canWrite
                        ? _showAddItemDialog
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 23),
                  ),
                const SizedBox(width: 8),
              ],
            ),
            body: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: ColoredBox(
                color: AppTheme.paper,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  style: const TextStyle(
                                      color: _cream, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Search stock items',
                                    prefixIcon: const Icon(Icons.search_rounded,
                                        size: 19),
                                    suffixIcon: _searchQuery.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18),
                                          ),
                                    fillColor: AppTheme.card,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              PopupMenuButton<String>(
                                tooltip: 'Filter stock items',
                                color: AppTheme.card,
                                onSelected: (value) =>
                                    setState(() => _filter = value),
                                icon: Container(
                                    width: 32,
                                    height: 36,
                                    decoration: BoxDecoration(
                                        color: AppTheme.forest,
                                        borderRadius:
                                            BorderRadius.circular(11)),
                                    child: const Icon(Icons.filter_alt_outlined,
                                        color: Colors.white, size: 19)),
                                itemBuilder: (_) => [
                                  for (final entry in const {
                                    'all': 'All',
                                    'ingredients': 'Ingredients',
                                    'products': 'Products',
                                    'low': 'Low stock',
                                  }.entries)
                                    CheckedPopupMenuItem(
                                        value: entry.key,
                                        checked: _filter == entry.key,
                                        child: Text(entry.value)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height:
                              MediaQuery.textScalerOf(context).scale(12) + 28,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            scrollDirection: Axis.horizontal,
                            children: [
                              _filterChip('All', 'all'),
                              _filterChip('Ingredients', 'ingredients'),
                              _filterChip('Products', 'products'),
                              _filterChip('Low stock', 'low'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: StreamBuilder<List<StockItem>>(
                            stream: _stockStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return _emptyState(
                                    Icons.cloud_off_outlined,
                                    'Inventory unavailable',
                                    'Could not load inventory. Check your connection.');
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final items = snapshot.data!;
                              final visibleItems = items.where((item) {
                                final queryMatches = item.name
                                    .toLowerCase()
                                    .contains(
                                        _searchQuery.trim().toLowerCase());
                                final filterMatches = switch (_filter) {
                                  'ingredients' =>
                                    item.category == 'ingredient',
                                  'products' => item.category == 'finished',
                                  'low' => item.isLow,
                                  _ => true,
                                };
                                return queryMatches && filterMatches;
                              }).toList(growable: false);
                              if (visibleItems.isEmpty) {
                                return _emptyState(
                                  items.isEmpty
                                      ? Icons.inventory_2_outlined
                                      : Icons.search_off_rounded,
                                  items.isEmpty
                                      ? 'No stock items yet'
                                      : 'No matching stock',
                                  items.isEmpty
                                      ? 'Add an item to start tracking café stock.'
                                      : _searchQuery.isEmpty
                                          ? 'No items in this filter.'
                                          : 'No items match “$_searchQuery”.',
                                );
                              }
                              return ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 16),
                                itemCount: visibleItems.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 2),
                                itemBuilder: (_, index) =>
                                    _stockRow(visibleItems[index]),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: CafeBottomNavigation(
                selectedIndex: 1, onDestinationSelected: _selectTab),
          ),
        ),
      );

  Widget _emptyState(IconData icon, String title, String message) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                    color: AppTheme.softGreen, shape: BoxShape.circle),
                child: Icon(icon, color: _caramel, size: 30)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _cream, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 7),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
          ]),
        ),
      );

  Widget _stockRow(StockItem item) {
    final product = item.category == 'finished';
    final status = item.isRecipeProduct
        ? 'Recipe product'
        : item.quantity <= 0
            ? 'Out of stock'
            : item.isLow
                ? 'Low stock'
                : 'In stock';
    final low = item.isLow;
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showItemDetails(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 5, 12),
          child: Row(
            children: [
              _stockPhoto(item.photoUrl, product: product),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _cream,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${_stockNumber(item.quantity)} ${item.unit}',
                        style: const TextStyle(color: _muted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 66),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                      color: low ? AppTheme.softOrange : AppTheme.softGreen,
                      borderRadius: BorderRadius.circular(7)),
                  child: Text(status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: low ? AppTheme.orangeDeep : AppTheme.emerald,
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              if (widget.canManageInventory)
                SizedBox(
                  width: 44,
                  child: PopupMenuButton<_StockAction>(
                    tooltip: 'Item actions',
                    padding: EdgeInsets.zero,
                    color: AppTheme.card,
                    icon: const Icon(Icons.more_vert_rounded,
                        color: _muted, size: 18),
                    enabled: ServerConnection.instance.canWrite,
                    onSelected: (action) => _itemAction(action, item),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: _StockAction.edit, child: Text('Edit item')),
                      const PopupMenuItem(
                          value: _StockAction.addStock,
                          child: Text('Add stock')),
                      if (item.isRecipeProduct)
                        const PopupMenuItem(
                            value: _StockAction.recipe,
                            child: Text('Manage recipe')),
                    ],
                  ),
                )
              else
                const SizedBox(width: 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
          selectedColor: _caramel,
          backgroundColor: const Color(0xFFEEEDE6),
          labelStyle: TextStyle(
              color: _filter == value ? Colors.white : _cream,
              fontSize: 11,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(vertical: 1),
        ),
      );

  HomeScreen _homePage() => HomeScreen(
      cafeId: widget.cafeId,
      cafeRole: widget.cafeRole,
      cafeService: service,
      stockStream: service.watchStock());

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _selectTab(0);
    }
  }

  void _selectTab(int index) {
    if (index == 1) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _homePage()));
      if (index == 0) return;
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => cafeTabPage(index,
              cafeId: widget.cafeId,
              cafeRole: widget.cafeRole,
              cafeService: service)));
      return;
    }
    selectCafeTab(
        context: context,
        currentIndex: 1,
        nextIndex: index,
        pageForIndex: (index) => cafeTabPage(index,
            cafeId: widget.cafeId,
            cafeRole: widget.cafeRole,
            cafeService: service));
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
    final reason =
        _reason.text.trim().isEmpty ? 'Stock addition' : _reason.text.trim();

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
  Widget build(BuildContext context) => InventoryFormShell(
        title: 'Add stock',
        saveLabel: 'Save stock',
        saving: _saving,
        onSave: _saving ? null : _save,
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
                  if (amount == null || !amount.isFinite || amount <= 0) {
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
      );
}

class _StockModeField extends StatelessWidget {
  const _StockModeField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: const Key('itemStockMode'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Stock deduction',
          helperText: value == 'direct'
              ? 'Checkout deducts this item’s quantity.'
              : 'Checkout deducts ingredients from the saved recipe.',
          helperMaxLines: 3,
        ),
        items: const [
          DropdownMenuItem(
            value: 'recipe',
            child: Text('Recipe ingredients'),
          ),
          DropdownMenuItem(
            value: 'direct',
            child: Text('Direct stock'),
          ),
        ],
        onChanged: enabled
            ? (next) {
                if (next != null) onChanged(next);
              }
            : null,
      );
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
  String _stockMode = 'recipe';
  String _unit = 'g';
  bool _saving = false;
  bool _pickingPhoto = false;
  SelectedProductPhoto? _selectedPhoto;

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

  Future<void> _choosePhoto() async {
    final cafeId = widget.service.cafeId;
    if (cafeId == null || _saving || _pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final selected = await PhotoService(cafeId: cafeId).choosePhoto();
      if (selected != null && mounted) {
        setState(() => _selectedPhoto = selected);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select photo: $error')),
      );
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _saveItem() async {
    if (_saving || _pickingPhoto || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final item = StockItem(
        id: '',
        name: _name.text.trim(),
        category: _category,
        stockMode: _category == 'finished' ? _stockMode : 'recipe',
        unit: _unit,
        quantity: _number(_quantity)!,
        minimumQuantity: _number(_minimum)!,
        purchasePricePerUnit: _number(_purchase)!,
        sellingPrice: _number(_selling)!,
      );

      final itemId = await widget.service.addItem(item);
      final selected = _selectedPhoto;
      final cafeId = widget.service.cafeId;
      if (selected != null && cafeId != null) {
        final photos = PhotoService(cafeId: cafeId);
        UploadedProductPhoto? uploaded;
        try {
          uploaded = await photos.uploadPhoto(itemId, selected);
          await widget.service.replacePhotoUrl(
            itemId: itemId,
            expectedUrl: '',
            newUrl: uploaded.url,
          );
        } catch (error) {
          if (uploaded != null) {
            try {
              await photos.deleteUploadedPhoto(uploaded);
            } catch (_) {
              // A failed cleanup must not result in a duplicate stock item.
            }
          }
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Item saved without a photo'),
                content: Text(
                  'Your inventory item was created, but its photo could not '
                  'be saved. Edit the item to try again.\n${PhotoService.failureMessage(error)}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      }

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
  Widget build(BuildContext context) => InventoryFormShell(
        title: 'Add stock item',
        saveLabel: 'Save item',
        saving: _saving,
        onSave: _saving || _pickingPhoto ? null : _saveItem,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  InkWell(
                    key: const Key('addItemPhotoTile'),
                    onTap: widget.service.cafeId == null ||
                            _saving ||
                            _pickingPhoto
                        ? null
                        : _choosePhoto,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 64,
                        height: 72,
                        child: ColoredBox(
                          color: AppTheme.softOrange,
                          child: _selectedPhoto != null
                              ? Image.memory(
                                  _selectedPhoto!.bytes,
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.photo_camera_outlined,
                                    color: AppTheme.orangeDeep,
                                    size: 23,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _name,
                      style: const TextStyle(color: _cream),
                      decoration: const InputDecoration(labelText: 'Item name'),
                      validator: _validateItemName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.service.cafeId != null) ...[
                OutlinedButton.icon(
                  key: const Key('addItemChoosePhoto'),
                  onPressed: _saving || _pickingPhoto ? null : _choosePhoto,
                  icon: _pickingPhoto
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _pickingPhoto
                        ? 'Opening gallery…'
                        : _selectedPhoto == null
                            ? 'Choose product photo (optional)'
                            : 'Change selected photo',
                  ),
                ),
                if (_selectedPhoto != null)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _selectedPhoto = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Clear selection'),
                  ),
              ] else
                const Text(
                  'Photos require a selected café workspace.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
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
              if (_category == 'finished') ...[
                const SizedBox(height: 10),
                _StockModeField(
                  value: _stockMode,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _stockMode = value),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('Grams (g)')),
                  DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                  DropdownMenuItem(
                      value: 'ml', child: Text('Millilitres (ml)')),
                  DropdownMenuItem(value: 'L', child: Text('Litres (L)')),
                  DropdownMenuItem(value: 'piece', child: Text('Pieces')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _unit = value ?? 'g'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Minimum quantity',
                ),
                validator: (value) => _validateNumber(
                  value,
                  _minimum,
                  'minimum stock level',
                ),
              ),
              const SizedBox(height: 10),
              InventoryFieldPair(
                  first: TextFormField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening quantity',
                    ),
                    validator: (value) => _validateNumber(
                      value,
                      _quantity,
                      'opening quantity',
                    ),
                  ),
                  second: TextFormField(
                    controller: _purchase,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Purchase (₹)',
                    ),
                    validator: (value) => _validateNumber(
                      value,
                      _purchase,
                      'purchase cost',
                    ),
                  )),
              const SizedBox(height: 8),
              TextFormField(
                controller: _selling,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Selling price (₹)',
                ),
                validator: (value) => _validateNumber(
                  value,
                  _selling,
                  'selling price',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
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
  late String _stockMode;
  late String _unit;
  late String _photoUrl;
  bool _saving = false;
  bool _uploadingPhoto = false;

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
    _stockMode = item.stockMode == 'direct' ? 'direct' : 'recipe';
    _unit = _units.contains(item.unit) ? item.unit : 'piece';
    _photoUrl = item.photoUrl;
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

  Future<void> _choosePhoto() async {
    final cafeId = widget.service.cafeId;
    if (_saving || _uploadingPhoto || cafeId == null) return;

    setState(() => _uploadingPhoto = true);
    final photos = PhotoService(cafeId: cafeId);
    UploadedProductPhoto? uploaded;
    try {
      final selected = await photos.choosePhoto();
      if (selected == null) return;

      final previousUrl = _photoUrl;
      uploaded = await photos.uploadPhoto(widget.item.id, selected);
      await widget.service.replacePhotoUrl(
        itemId: widget.item.id,
        expectedUrl: previousUrl,
        newUrl: uploaded.url,
      );
      if (!mounted) return;
      setState(() => _photoUrl = uploaded!.url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product photo updated.')),
      );
      if (previousUrl.isNotEmpty) {
        try {
          await photos.deletePreviousPhoto(widget.item.id, previousUrl);
        } catch (_) {
          // The newly saved photo is valid even when old cleanup fails.
        }
      }
    } catch (error) {
      if (uploaded != null) {
        try {
          await photos.deleteUploadedPhoto(uploaded);
        } catch (_) {
          // Best-effort cleanup. Do not overwrite the original failure.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not update product photo: ${PhotoService.failureMessage(error)}')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    final cafeId = widget.service.cafeId;
    if (cafeId == null || _uploadingPhoto || _saving || _photoUrl.isEmpty) {
      return;
    }
    setState(() => _uploadingPhoto = true);
    final previousUrl = _photoUrl;
    try {
      await widget.service.replacePhotoUrl(
        itemId: widget.item.id,
        expectedUrl: previousUrl,
        newUrl: '',
      );
      if (!mounted) return;
      setState(() => _photoUrl = '');
      try {
        await PhotoService(cafeId: cafeId)
            .deletePreviousPhoto(widget.item.id, previousUrl);
      } catch (_) {
        // The Firestore reference is cleared; old-object cleanup may retry.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product photo removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not remove product photo: ${PhotoService.failureMessage(error)}')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
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
        stockMode: _category == 'finished' ? _stockMode : 'recipe',
        unit: _unit,
        // This value is preserved again by CafeService.updateItem.
        quantity: old.quantity,
        minimumQuantity: _number(_minimum)!,
        purchasePricePerUnit: _number(_purchase)!,
        sellingPrice: _number(_selling)!,
        photoUrl: _photoUrl,
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
  Widget build(BuildContext context) => InventoryFormShell(
        title: 'Edit item details',
        saveLabel: 'Save changes',
        saving: _saving,
        onSave: _saving || _uploadingPhoto ? null : _save,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.service.cafeId != null) ...[
                Row(
                  children: [
                    _stockPhoto(_photoUrl,
                        size: 48, product: widget.item.category == 'finished'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _saving || _uploadingPhoto ? null : _choosePhoto,
                        icon: _uploadingPhoto
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _uploadingPhoto
                              ? 'Uploading photo…'
                              : 'Choose product photo',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_photoUrl.isNotEmpty)
                  TextButton.icon(
                    key: const Key('editItemRemovePhoto'),
                    onPressed: _saving || _uploadingPhoto ? null : _removePhoto,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove product photo'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'JPEG, PNG or WebP product photos up to 5 MiB are stored in this café.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _name,
                enabled: !_saving,
                style: const TextStyle(color: _cream),
                decoration: const InputDecoration(labelText: 'Item name'),
                validator: _validateItemName,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
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
              if (_category == 'finished') ...[
                const SizedBox(height: 10),
                _StockModeField(
                  value: _stockMode,
                  enabled: !_saving,
                  onChanged: (value) => setState(() => _stockMode = value),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('Grams (g)')),
                  DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                  DropdownMenuItem(
                      value: 'ml', child: Text('Millilitres (ml)')),
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
                controller: _minimum,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Minimum quantity',
                ),
                validator: (value) => _validateNumber(
                  value,
                  _minimum,
                  'minimum stock level',
                ),
              ),
              const SizedBox(height: 10),
              InventoryFieldPair(
                  first: TextFormField(
                    initialValue: '${widget.item.quantity} ${widget.item.unit}',
                    readOnly: true,
                    style: const TextStyle(color: _muted),
                    decoration: const InputDecoration(
                      labelText: 'Current quantity',
                      helperText: 'Read only',
                    ),
                  ),
                  second: TextFormField(
                    controller: _purchase,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Purchase (₹)',
                    ),
                    validator: (value) => _validateNumber(
                      value,
                      _purchase,
                      'purchase cost',
                    ),
                  )),
              const SizedBox(height: 8),
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
                  value,
                  _selling,
                  'selling price',
                ),
              ),
            ],
          ),
        ),
      );
}

class _MovementHistoryDialog extends StatelessWidget {
  const _MovementHistoryDialog({
    required this.service,
  });

  final CafeService service;

  String _dateLabel(Object? value) {
    final date = value is DateTime
        ? value
        : value is Timestamp
            ? value.toDate()
            : null;
    if (date == null) return 'Time unavailable';
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = (local.hour % 12 == 0 ? 12 : local.hour % 12)
        .toString()
        .padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$day/$month/${local.year} · $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _panel,
      title: const Text(
        'Stock movement history',
        style: TextStyle(color: _cream),
      ),
      content: SizedBox(
        width: 520,
        height: 440,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchRecentMovements(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load movement history.',
                  style: TextStyle(color: _muted),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _caramel),
              );
            }
            final movements = snapshot.data!;
            if (movements.isEmpty) {
              return const Center(
                child: Text(
                  'No stock movements recorded yet.',
                  style: TextStyle(color: _muted),
                ),
              );
            }
            return ListView.separated(
              itemCount: movements.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12),
              itemBuilder: (context, index) {
                final movement = movements[index];
                final quantity = movement['quantityChange'];
                final after = movement['quantityAfter'];
                final itemId = movement['stockItemId'] as String? ?? '';
                final itemName = movement['stockItemName'] as String? ??
                    (itemId.isEmpty
                        ? 'Inventory item'
                        : 'Inventory item ($itemId)');
                final isAddition = movement['type'] == 'addition';
                final signedQuantity = quantity is num
                    ? '${quantity > 0 ? '+' : ''}${quantity.toString()}'
                    : '—';
                final afterLabel = after is num ? after.toString() : '—';
                final unit = movement['stockItemUnit'] as String?;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isAddition
                        ? Icons.add_circle_outline_rounded
                        : Icons.remove_circle_outline_rounded,
                    color: isAddition ? _caramel : _copper,
                  ),
                  title: Text(
                    itemName,
                    style: const TextStyle(
                      color: _cream,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${movement['reason'] ?? movement['type'] ?? 'Movement'}'
                    '\n${_dateLabel(movement['createdAt'])}',
                    style: const TextStyle(color: _muted, height: 1.45),
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        unit == null ? signedQuantity : '$signedQuantity $unit',
                        style: TextStyle(
                          color: isAddition ? _caramel : _copper,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Balance: $afterLabel${unit == null ? '' : ' $unit'}',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
