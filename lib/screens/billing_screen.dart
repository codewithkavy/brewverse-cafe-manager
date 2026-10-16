import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../services/cafe_service.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const Color espresso = Color(0xFF171210);
  static const Color coffee = Color(0xFF241B17);
  static const Color cardColor = Color(0xFF30231D);
  static const Color caramel = Color(0xFFE5A365);
  static const Color copper = Color(0xFFC7794D);
  static const Color cream = Color(0xFFF5E9DD);
  static const Color mutedCream = Color(0xFFBDA99A);

  final CafeService service = CafeService();
  final Map<String, int> cart = {};

  List<StockItem> _products = [];

  String orderType = 'dineIn';
  bool _checkingOut = false;

  // Keep this ID after a failed request so retrying the same cart
  // cannot accidentally create a second bill.
  String? _pendingCheckoutId;

  int get itemCount =>
      cart.values.fold(0, (total, quantity) => total + quantity);

  double get total {
    double amount = 0;

    for (final entry in cart.entries) {
      final item = _findProduct(entry.key);

      if (item != null) {
        amount += item.sellingPrice * entry.value;
      }
    }

    return amount;
  }

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

    final cartSnapshot = Map<String, int>.from(cart);

    setState(() {
      _checkingOut = true;
      _pendingCheckoutId ??=
          FirebaseFirestore.instance.collection('bills').doc().id;
    });

    final checkoutId = _pendingCheckoutId!;

    try {
      final billId = await service.checkout(
        checkoutId: checkoutId,
        cart: cartSnapshot,
        orderType: orderType,
      );

      if (!mounted) return;

      setState(() {
        cart.clear();
        _pendingCheckoutId = null;
        _checkingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: cardColor,
          content: Text(
            'Bill saved successfully! Bill ID: $billId',
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      // Printing will be connected after checkout is tested.
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: espresso,
      appBar: AppBar(
        backgroundColor: espresso,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Bill'),
            Text(
              'BrewVerse Cafe Manager',
              style: TextStyle(
                fontSize: 12,
                color: mutedCream,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'View current bill',
            onPressed: _showCart,
            icon: const Icon(Icons.receipt_long),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<StockItem>>(
        stream: service.watchStock(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load inventory.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: cream),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: caramel),
            );
          }

          _products = snapshot.data!
              .where((item) => item.category == 'finished')
              .toList();

          final existingIds = _products.map((item) => item.id).toSet();

          // Do not silently delete cart items while checkout is running.
          if (!_checkingOut) {
            cart.removeWhere((id, _) => !existingIds.contains(id));
          }

          if (_products.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.coffee_outlined,
                      size: 56,
                      color: caramel,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No finished products yet',
                      style: TextStyle(
                        color: cream,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Add finished products in Manage Inventory.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedCream),
                    ),
                  ],
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _products.length,
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.70,
            ),
            itemBuilder: (context, index) {
              final item = _products[index];
              final quantity = cart[item.id] ?? 0;

              return Card(
                color: cardColor,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        color: coffee,
                        child: item.photoUrl.isNotEmpty
                            ? Image.network(
                          item.photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(
                            Icons.coffee,
                            size: 54,
                            color: caramel,
                          ),
                        )
                            : const Icon(
                          Icons.coffee,
                          size: 54,
                          color: caramel,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: cream,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${item.sellingPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: caramel,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Recipe stock checked at checkout',
                            maxLines: 2,
                            style: TextStyle(
                              color: mutedCream,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: 'Remove one',
                            onPressed: quantity == 0 || _checkingOut
                                ? null
                                : () => _removeItem(item),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              '$quantity',
                              style: const TextStyle(color: cream),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add one',
                            onPressed: _checkingOut
                                ? null
                                : () => _addItem(item),
                            style: IconButton.styleFrom(
                              backgroundColor: copper,
                              foregroundColor: espresso,
                            ),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: coffee,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            border: Border(
              top: BorderSide(color: Colors.white10),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'Order type',
                    style: TextStyle(
                      color: cream,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'dineIn',
                        label: Text('Dine-in'),
                        icon: Icon(Icons.restaurant),
                      ),
                      ButtonSegment(
                        value: 'takeaway',
                        label: Text('Takeaway'),
                        icon: Icon(Icons.takeout_dining),
                      ),
                    ],
                    selected: {orderType},
                    onSelectionChanged: _checkingOut
                        ? null
                        : (selection) {
                      setState(() {
                        orderType = selection.first;
                        _pendingCheckoutId = null;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: cream),
                  ),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: caramel,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                  itemCount == 0 || _checkingOut ? null : _checkout,
                  icon: _checkingOut
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.shopping_cart_checkout),
                  label: Text(
                    _checkingOut
                        ? 'Saving bill...'
                        : 'Checkout · ₹${total.toStringAsFixed(2)}',
                  ),
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
      backgroundColor: coffee,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Bill',
                      style: TextStyle(
                        color: cream,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (cart.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Your bill is empty. Add products first.',
                          style: TextStyle(color: mutedCream),
                        ),
                      )
                    else
                      ...cart.entries.map((entry) {
                        final item = _findProduct(entry.key);

                        if (item == null) {
                          return const SizedBox.shrink();
                        }

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.name,
                            style: const TextStyle(color: cream),
                          ),
                          subtitle: Text(
                            '₹${item.sellingPrice.toStringAsFixed(2)} each',
                            style: const TextStyle(color: mutedCream),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: copper,
                            foregroundColor: espresso,
                            child: Text('${entry.value}'),
                          ),
                          trailing: Text(
                            '₹${(item.sellingPrice * entry.value).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: caramel,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }),
                    const Divider(color: Colors.white24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: cream,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: caramel,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: cart.isEmpty || _checkingOut
                            ? null
                            : () {
                          Navigator.pop(sheetContext);
                          _checkout();
                        },
                        child: const Text('Complete checkout'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Continue shopping'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}