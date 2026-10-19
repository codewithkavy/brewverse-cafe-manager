import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import 'home_screen.dart';
import 'thermal_printer_dialog.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({
    super.key,
    this.cafeId,
    this.cafeRole,
    this.initialCustomerPhone,
    this.stockStream,
    this.cafeService,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final String? initialCustomerPhone;
  final Stream<List<StockItem>>? stockStream;
  final CafeService? cafeService;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const Color cardColor = AppTheme.card;
  static const Color caramel = AppTheme.emerald;

  late final CafeService service;
  final Map<String, int> cart = {};
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _redeemPointsController =
      TextEditingController(text: '0');
  Map<String, dynamic>? _loyaltyCustomer;
  Map<String, dynamic>? _loyaltySettings;
  bool _lookingUpCustomer = false;

  List<StockItem> _products = [];
  late final Stream<List<StockItem>> _stockStream;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _inOrderOnly = false;

  String orderType = 'dineIn';
  bool _checkingOut = false;

  // Keep this ID after a failed request so retrying the same cart
  // cannot accidentally create a second bill.
  String? _pendingCheckoutId;

  @override
  void initState() {
    super.initState();
    service = widget.cafeService ?? CafeService(cafeId: widget.cafeId);
    _stockStream = widget.stockStream ?? service.watchStock();
    _customerPhoneController.text = widget.initialCustomerPhone ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerPhoneController.dispose();
    _redeemPointsController.dispose();
    super.dispose();
  }

  int get itemCount =>
      cart.values.fold(0, (total, quantity) => total + quantity);

  int _unitPricePaise(StockItem item) => (item.sellingPrice * 100).round();

  int _lineTotalPaise(StockItem item, int quantity) =>
      _unitPricePaise(item) * quantity;

  int get _totalPaise => cart.entries.fold(0, (amount, entry) {
        final item = _findProduct(entry.key);
        return item == null
            ? amount
            : amount + _lineTotalPaise(item, entry.value);
      });

  double get total => _totalPaise / 100;

  int get _estimatedLoyaltyDiscountPaise {
    final settings = _loyaltySettings;
    if (_loyaltyCustomer == null ||
        settings == null ||
        settings['enabled'] != true) {
      return 0;
    }
    final requested = int.tryParse(_redeemPointsController.text.trim()) ?? 0;
    final available = _loyaltyCustomer?['pointsBalance'];
    final pointValue = settings['pointValueMinor'];
    final capPercent = settings['maxRedemptionPercent'];
    if (requested <= 0 ||
        available is! int ||
        pointValue is! int ||
        pointValue <= 0 ||
        capPercent is! int) {
      return 0;
    }
    final cap = _totalPaise * capPercent ~/ 100;
    return (requested.clamp(0, available) * pointValue).clamp(0, cap);
  }

  int get _estimatedNetPaise => _totalPaise - _estimatedLoyaltyDiscountPaise;

  StockItem? _findProduct(String id) {
    for (final item in _products) {
      if (item.id == id) return item;
    }

    return null;
  }

  void _addItem(StockItem item) {
    if (_checkingOut) return;

    setState(() {
      cart[item.id] = (cart[item.id] ?? 0) + 1;
      _pendingCheckoutId = null;
    });
  }

  void _removeItem(StockItem item) {
    if (_checkingOut) return;

    setState(() {
      final current = cart[item.id] ?? 0;

      if (current <= 1) {
        cart.remove(item.id);
      } else {
        cart[item.id] = current - 1;
      }

      _pendingCheckoutId = null;
    });
  }

  Future<void> _checkout() async {
    if (_checkingOut || cart.isEmpty) return;

    final redeemedPoints =
        int.tryParse(_redeemPointsController.text.trim()) ?? 0;
    if (redeemedPoints < 0 ||
        redeemedPoints > ((_loyaltyCustomer?['pointsBalance'] as int?) ?? 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Enter a valid point amount within the customer balance.')),
      );
      return;
    }

    final cartSnapshot = Map<String, int>.from(cart);
    final orderTypeSnapshot = orderType;
    final customerPhoneSnapshot =
        _loyaltyCustomer == null ? null : _customerPhoneController.text.trim();

    setState(() {
      _checkingOut = true;
      _pendingCheckoutId ??=
          FirebaseFirestore.instance.collection('bills').doc().id;
    });

    final checkoutId = _pendingCheckoutId!;

    late final String billId;
    try {
      billId = await service.checkout(
        checkoutId: checkoutId,
        cart: cartSnapshot,
        orderType: orderTypeSnapshot,
        customerPhone: customerPhoneSnapshot,
        redeemPoints: redeemedPoints,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _checkingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text(
            'Checkout failed. No successful bill was confirmed.\n$error',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      cart.clear();
      _pendingCheckoutId = null;
      _checkingOut = false;
      _loyaltyCustomer = null;
      _customerPhoneController.clear();
      _redeemPointsController.text = '0';
    });

    Map<String, dynamic>? savedBill;
    try {
      savedBill = await service.loadBill(billId);
    } catch (_) {
      // Checkout is already committed; receipt lookup must not report it failed.
    }
    if (!mounted) return;
    final rawItems = savedBill?['items'];
    final receiptItems = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final rawTotal = savedBill?['total'];
    final receiptTotal = rawTotal is num ? rawTotal.toDouble() : null;
    final rawDiscount = savedBill?['discount'];
    final receiptDiscount = rawDiscount is num ? rawDiscount.toDouble() : 0.0;
    final receiptAvailable = receiptItems.isNotEmpty &&
        receiptTotal != null &&
        receiptTotal.isFinite;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: cardColor,
        content: Text(_checkoutMessage(billId, savedBill)),
        duration: const Duration(seconds: 7),
        action: receiptAvailable
            ? SnackBarAction(
                label: 'PRINT RECEIPT',
                textColor: caramel,
                onPressed: () => _openPrinterDialog(
                  billId: billId,
                  orderType: orderTypeSnapshot,
                  items: receiptItems,
                  total: receiptTotal,
                  discount: receiptDiscount,
                ),
              )
            : null,
      ),
    );
  }

  String _checkoutMessage(String billId, Map<String, dynamic>? savedBill) {
    final loyalty = savedBill?['loyalty'];
    if (loyalty is Map) {
      final earned =
          loyalty['pointsEarned'] is int ? loyalty['pointsEarned'] as int : 0;
      final redeemed = loyalty['pointsRedeemed'] is int
          ? loyalty['pointsRedeemed'] as int
          : 0;
      final balance = loyalty['pointsBalanceAfter'] is int
          ? loyalty['pointsBalanceAfter'] as int
          : 0;
      return 'Bill saved · $earned points earned · $redeemed used · $balance balance · $billId';
    }
    return 'Bill saved successfully! Bill ID: $billId';
  }

  Future<void> _lookupLoyaltyCustomer() async {
    if (widget.cafeId == null || _lookingUpCustomer || _checkingOut) return;
    final phone = _customerPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a customer phone number first.')),
      );
      return;
    }
    setState(() {
      _lookingUpCustomer = true;
      _loyaltyCustomer = null;
      _pendingCheckoutId = null;
    });
    try {
      final customer = await service.lookupLoyaltyCustomer(phoneNumber: phone);
      final settings = await service.getLoyaltySettings();
      if (!mounted) return;
      setState(() {
        _loyaltyCustomer = customer;
        _loyaltySettings = settings;
        _redeemPointsController.text = '0';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(customer['found'] == true
              ? 'Customer found · ${customer['pointsBalance']} points available.'
              : 'New loyalty customer · points will be earned on this sale.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not look up customer: $error')),
      );
    } finally {
      if (mounted) setState(() => _lookingUpCustomer = false);
    }
  }

  Future<void> _openPrinterDialog({
    required String billId,
    required String orderType,
    required List<Map<String, dynamic>> items,
    required double total,
    required double discount,
  }) async {
    if (!mounted) return;
    var cafeName = 'BREWVERSE CAFE';
    try {
      cafeName = await service.loadCafeName() ?? cafeName;
    } catch (_) {
      // Printing remains available if café profile lookup is unavailable.
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => ThermalPrinterDialog(
        cafeName: cafeName,
        billNumber: billId,
        orderType: orderType,
        items: items,
        total: total,
        discount: discount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          backgroundColor: AppTheme.paper,
          appBar: AppBar(
            toolbarHeight: 52,
            leadingWidth: 42,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 21),
            ),
            titleSpacing: 0,
            title: const Text('Create Bill',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            actions: [
              IconButton(
                tooltip: 'View current bill',
                onPressed: _showCart,
                icon: const Icon(Icons.receipt_long_outlined, size: 22),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      style: const TextStyle(fontSize: 13, color: AppTheme.ink),
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                        fillColor: const Color(0xFFEEEDE6),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _menuFilter('All products', !_inOrderOnly,
                              () => setState(() => _inOrderOnly = false)),
                          const SizedBox(width: 7),
                          _menuFilter('In order', _inOrderOnly,
                              () => setState(() => _inOrderOnly = true)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: StreamBuilder<List<StockItem>>(
                      stream: _stockStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _menuState(
                            Icons.cloud_off_outlined,
                            'Menu unavailable',
                            'Could not load inventory.\n${snapshot.error}',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        _products = snapshot.data!
                            .where((item) => item.category == 'finished')
                            .toList();
                        final existingIds =
                            _products.map((item) => item.id).toSet();
                        // Keep in-flight checkout cart intact.
                        if (!_checkingOut) {
                          cart.removeWhere(
                              (id, _) => !existingIds.contains(id));
                        }
                        if (_products.isEmpty) {
                          return _menuState(
                            Icons.local_cafe_outlined,
                            'Your menu starts here',
                            'No finished products yet. Add your products in Inventory to create a bill.',
                            action: TextButton.icon(
                              onPressed: () => _selectTab(1),
                              icon: const Icon(Icons.inventory_2_outlined,
                                  size: 17),
                              label: const Text('Open Inventory'),
                            ),
                          );
                        }
                        final visibleProducts = _products
                            .where((item) =>
                                item.name.toLowerCase().contains(
                                    _searchQuery.trim().toLowerCase()) &&
                                (!_inOrderOnly || cart.containsKey(item.id)))
                            .toList(growable: false);
                        if (visibleProducts.isEmpty) {
                          return _menuState(
                            Icons.search_off_rounded,
                            _inOrderOnly && cart.isEmpty
                                ? 'Your order is empty'
                                : 'No matching products',
                            _inOrderOnly && cart.isEmpty
                                ? 'Choose All products to start your order.'
                                : 'Try another search or choose All products.',
                          );
                        }
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final largeText =
                                MediaQuery.textScalerOf(context).scale(13) > 17;
                            final columns = constraints.maxWidth >= 900
                                ? 5
                                : constraints.maxWidth >= 620
                                    ? 4
                                    : constraints.maxWidth >= 278 && !largeText
                                        ? 3
                                        : 2;
                            final width = (constraints.maxWidth -
                                    24 -
                                    8 * (columns - 1)) /
                                columns;
                            final textScale =
                                MediaQuery.textScalerOf(context).scale(13) / 13;
                            return GridView.builder(
                              key: const ValueKey('billing-product-grid'),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                mainAxisExtent:
                                    width * 0.88 + 72 * textScale.clamp(1, 2),
                              ),
                              itemCount: visibleProducts.length,
                              itemBuilder: (context, index) =>
                                  _productCard(visibleProducts[index]),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SafeArea(
                top: false,
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 6),
                      child: Material(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(19),
                        child: InkWell(
                          onTap: _showCart,
                          borderRadius: BorderRadius.circular(19),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Row(
                              children: [
                                Container(
                                  height: 44,
                                  width: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.emerald,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                      Icons.shopping_cart_outlined,
                                      color: Colors.white,
                                      size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                            color: AppTheme.mutedInk,
                                            fontSize: 11),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '₹${(_estimatedNetPaise / 100).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppTheme.ink,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Review order',
                                  onPressed: _showCart,
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.orange,
                                    foregroundColor: AppTheme.forest,
                                    minimumSize: const Size(48, 48),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              CafeBottomNavigation(
                selectedIndex: 2,
                onDestinationSelected: _selectTab,
              ),
            ],
          ),
        ),
      );

  Widget _menuFilter(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
          selectedColor: AppTheme.emerald,
          backgroundColor: const Color(0xFFEEEDE6),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppTheme.ink,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _menuState(IconData icon, String title, String message,
          {Widget? action}) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: AppTheme.softGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.emerald, size: 32),
              ),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 7),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.mutedInk, fontSize: 12, height: 1.5)),
              if (action != null) ...[const SizedBox(height: 10), action],
            ],
          ),
        ),
      );

  Widget _productImage(StockItem item, {double iconSize = 27}) => ColoredBox(
        color: AppTheme.softGreen,
        child: item.photoUrl.isEmpty
            ? Center(
                child: Icon(Icons.local_cafe_outlined,
                    color: AppTheme.emerald, size: iconSize))
            : Image.network(
                item.photoUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: AppTheme.mutedInk, size: iconSize),
                ),
              ),
      );

  Widget _productCard(StockItem item) {
    final quantity = cart[item.id] ?? 0;
    final price = _unitPricePaise(item);
    final priceLabel = price % 100 == 0
        ? '₹${price ~/ 100}'
        : '₹${(price / 100).toStringAsFixed(2)}';
    return Semantics(
      button: true,
      enabled: !_checkingOut,
      excludeSemantics: true,
      label:
          'Add ${item.name}, $priceLabel${quantity > 0 ? ', $quantity in order' : ''}',
      onTap: _checkingOut ? null : () => _addItem(item),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _checkingOut ? null : () => _addItem(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: quantity > 0 ? AppTheme.emerald : AppTheme.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _productImage(item),
                    if (quantity > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Tooltip(
                          message: 'In order · $quantity',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.emerald,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text('$quantity',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 0),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          priceLabel,
                          style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      height: 38,
                      child: IconButton(
                        tooltip: 'Add ${item.name}',
                        onPressed: _checkingOut ? null : () => _addItem(item),
                        padding: const EdgeInsets.all(5),
                        icon: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: Color(0xFFCBECD3), shape: BoxShape.circle),
                          child: const Icon(Icons.add_rounded,
                              size: 19, color: AppTheme.emerald),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.forest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => Theme(
        data: AppTheme.emeraldLight,
        child: SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 1,
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
              builder: (context, setSheetState) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 7, 12, 7),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Continue shopping',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 21),
                        ),
                        const Expanded(
                          child: Text('Your order',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Text('$itemCount item${itemCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.card,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 16, 14, 10),
                              children: [
                                if (cart.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 28),
                                    child: _menuState(
                                      Icons.shopping_bag_outlined,
                                      'Your order is empty',
                                      'Add a product to start this bill.',
                                    ),
                                  )
                                else
                                  for (final entry in cart.entries)
                                    if (_findProduct(entry.key)
                                        case final item?)
                                      _cartItem(
                                          item, entry.value, setSheetState),
                                const SizedBox(height: 16),
                                const Text('Order type',
                                    style: TextStyle(
                                        color: AppTheme.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 9),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  style: SegmentedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                  segments: const [
                                    ButtonSegment(
                                        value: 'dineIn',
                                        label: Text('Dine-in'),
                                        icon: Icon(Icons.restaurant_outlined,
                                            size: 17)),
                                    ButtonSegment(
                                        value: 'takeaway',
                                        label: Text('Takeaway'),
                                        icon: Icon(
                                            Icons.takeout_dining_outlined,
                                            size: 17)),
                                  ],
                                  selected: {orderType},
                                  onSelectionChanged: _checkingOut
                                      ? null
                                      : (selection) {
                                          setState(() {
                                            orderType = selection.first;
                                            _pendingCheckoutId = null;
                                          });
                                          setSheetState(() {});
                                        },
                                ),
                                if (widget.cafeId != null) ...[
                                  const SizedBox(height: 18),
                                  _loyaltyControls(sheetContext, setSheetState),
                                ],
                                const SizedBox(height: 22),
                                _cartAmountRow('Subtotal', _totalPaise),
                                if (_estimatedLoyaltyDiscountPaise > 0) ...[
                                  const SizedBox(height: 10),
                                  _cartAmountRow('Loyalty discount',
                                      -_estimatedLoyaltyDiscountPaise,
                                      color: AppTheme.emerald),
                                ],
                                const SizedBox(height: 10),
                                const Divider(color: AppTheme.line),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16,
                                10 + MediaQuery.viewInsetsOf(context).bottom),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Total',
                                          style: TextStyle(
                                              color: AppTheme.ink,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    Flexible(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '₹${(_estimatedNetPaise / 100).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                color: AppTheme.ink,
                                                fontSize: 24,
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: cart.isEmpty || _checkingOut
                                        ? null
                                        : () {
                                            Navigator.pop(sheetContext);
                                            _checkout();
                                          },
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                            child: Text('Complete checkout')),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded,
                                            size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (MediaQuery.viewInsetsOf(context).bottom == 0)
                    CafeBottomNavigation(
                      selectedIndex: 2,
                      onDestinationSelected: (index) {
                        Navigator.pop(sheetContext);
                        _selectTab(index);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartItem(StockItem item, int quantity, StateSetter setSheetState) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child:
                  SizedBox(width: 55, height: 64, child: _productImage(item)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      '₹${(_unitPricePaise(item) / 100).toStringAsFixed(2)} each',
                      style: const TextStyle(
                          color: AppTheme.mutedInk, fontSize: 11)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '₹${(_lineTotalPaise(item, quantity) / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove one ${item.name}',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 40),
                        onPressed: _checkingOut
                            ? null
                            : () {
                                _removeItem(item);
                                setSheetState(() {});
                              },
                        icon: const Icon(Icons.remove_circle_outline, size: 21),
                      ),
                      Text('$quantity',
                          style: const TextStyle(
                              color: AppTheme.ink, fontSize: 12)),
                      IconButton(
                        tooltip: 'Add one ${item.name}',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 40),
                        onPressed: _checkingOut
                            ? null
                            : () {
                                _addItem(item);
                                setSheetState(() {});
                              },
                        icon: const Icon(Icons.add_circle_outline, size: 21),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _loyaltyControls(
          BuildContext sheetContext, StateSetter setSheetState) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer loyalty',
              style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          TextField(
            controller: _customerPhoneController,
            enabled: !_checkingOut && !_lookingUpCustomer,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppTheme.ink, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Customer phone (+country code)',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
              isDense: true,
            ),
            onChanged: (_) {
              setState(() {
                _loyaltyCustomer = null;
                _loyaltySettings = null;
                _pendingCheckoutId = null;
                _redeemPointsController.text = '0';
              });
              setSheetState(() {});
            },
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _checkingOut || _lookingUpCustomer
                  ? null
                  : () async {
                      final lookup = _lookupLoyaltyCustomer();
                      setSheetState(() {});
                      await lookup;
                      if (sheetContext.mounted) setSheetState(() {});
                    },
              icon: _lookingUpCustomer
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_search_outlined, size: 18),
              label: const Text('Find customer'),
            ),
          ),
          if (_loyaltyCustomer != null) ...[
            Text('${_loyaltyCustomer!['pointsBalance']} points available',
                style: const TextStyle(
                    color: AppTheme.emerald, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _redeemPointsController,
              enabled: !_checkingOut,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.ink),
              onChanged: (_) {
                setState(() {});
                setSheetState(() {});
              },
              decoration: const InputDecoration(
                  labelText: 'Redeem points', isDense: true),
            ),
          ],
        ],
      );

  Widget _cartAmountRow(String label, int amountPaise,
          {Color color = AppTheme.mutedInk}) =>
      Row(
        children: [
          Expanded(
              child: Text(label, style: TextStyle(color: color, fontSize: 12))),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${amountPaise < 0 ? '- ' : ''}₹${(amountPaise.abs() / 100).toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ),
        ],
      );

  HomeScreen _homePage() => HomeScreen(
        cafeId: widget.cafeId,
        cafeRole: widget.cafeRole,
        cafeService: service,
        stockStream: service.watchStock(),
      );

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _selectTab(0);
    }
  }

  void _selectTab(int index) {
    if (index == 2) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _homePage()));
      if (index == 0) return;
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => cafeTabPage(index,
            cafeId: widget.cafeId,
            cafeRole: widget.cafeRole,
            cafeService: service),
      ));
      return;
    }
    selectCafeTab(
      context: context,
      currentIndex: 2,
      nextIndex: index,
      pageForIndex: (index) => cafeTabPage(index,
          cafeId: widget.cafeId,
          cafeRole: widget.cafeRole,
          cafeService: service),
    );
  }
}
