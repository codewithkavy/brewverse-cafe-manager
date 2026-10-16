import 'dart:async';
import 'package:flutter/material.dart';
import '../models/stock_item.dart';
import '../services/cafe_service.dart';
import 'inventory_screen.dart';
import 'billing_screen.dart';

const _bg = Color(0xFF171210);
const _panel = Color(0xFF241B17);
const _card = Color(0xFF30231D);
const _caramel = Color(0xFFE5A365);
const _copper = Color(0xFFC7794D);
const _cream = Color(0xFFF5E9DD);
const _muted = Color(0xFFBDA99A);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, animation, secondaryAnimation) => page,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.035, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = CafeService();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.coffee_rounded, color: _caramel, size: 27),
            SizedBox(width: 10),
            Text('BrewVerse'),
          ],
        ),
      ),
      body: StreamBuilder<List<StockItem>>(
        stream: service.watchStock(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _Message(
              icon: Icons.cloud_off_rounded,
              title: 'Inventory unavailable',
              message: 'Check your connection and Firebase settings.',
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _caramel),
            );
          }

          final items = snapshot.data!;
          final lowItems = items.where((item) => item.isLow).toList();
          final ingredients =
              items.where((item) => item.category == 'ingredient').length;
          final finished =
              items.where((item) => item.category == 'finished').length;
          final wide = MediaQuery.sizeOf(context).width > 700;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  _Entrance(
                    delay: 0,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF593624),
                            Color(0xFF302019),
                            Color(0xFF241B17),
                          ],
                        ),
                        border: Border.all(
                          color: _caramel.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR CAFE, YOUR CRAFT',
                            style: TextStyle(
                              color: _caramel,
                              letterSpacing: 2,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Good coffee.\nGreat business.',
                            style: TextStyle(
                              color: _cream,
                              fontSize: 29,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                          SizedBox(height: 9),
                          Text(
                            'Everything you need, without the clutter.',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel(
                    title: 'YOUR CAFE AT A GLANCE',
                    trailing: 'LIVE STOCK',
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: wide ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: wide ? 1.7 : 1.45,
                    children: [
                      _StatCard(
                        label: 'Total items',
                        value: items.length,
                        icon: Icons.inventory_2_outlined,
                        accent: _caramel,
                        delay: 80,
                      ),
                      _StatCard(
                        label: 'Low stock',
                        value: lowItems.length,
                        icon: Icons.warning_amber_rounded,
                        accent: lowItems.isEmpty
                            ? const Color(0xFF91B99A)
                            : _copper,
                        delay: 140,
                      ),
                      _StatCard(
                        label: 'Ingredients',
                        value: ingredients,
                        icon: Icons.grass_rounded,
                        accent: const Color(0xFF91B99A),
                        delay: 200,
                      ),
                      _StatCard(
                        label: 'Finished goods',
                        value: finished,
                        icon: Icons.coffee_rounded,
                        accent: const Color(0xFFD9B5E8),
                        delay: 260,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _SectionLabel(
                    title: 'QUICK ACCESS',
                    trailing: 'CHOOSE A WORKSPACE',
                  ),
                  const SizedBox(height: 12),
                  if (wide)
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            title: 'Inventory',
                            description: 'Manage stock and ingredients',
                            icon: Icons.inventory_2_rounded,
                            onTap: () =>
                                _open(context, const InventoryScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionCard(
                            title: 'Billing',
                            description: 'Create a bill and checkout',
                            icon: Icons.point_of_sale_rounded,
                            onTap: () => _open(context, const BillingScreen()),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _ActionCard(
                          title: 'Inventory',
                          description: 'Manage stock and ingredients',
                          icon: Icons.inventory_2_rounded,
                          onTap: () => _open(context, const InventoryScreen()),
                        ),
                        const SizedBox(height: 12),
                        _ActionCard(
                          title: 'Billing',
                          description: 'Create a bill and checkout',
                          icon: Icons.point_of_sale_rounded,
                          onTap: () => _open(context, const BillingScreen()),
                        ),
                      ],
                    ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionLabel(title: 'NEEDS ATTENTION'),
                      ),
                      if (lowItems.isNotEmpty)
                        Text(
                          '${lowItems.length} ${lowItems.length == 1 ? 'ITEM' : 'ITEMS'}',
                          style: const TextStyle(
                            color: _copper,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (lowItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF91B99A),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'All stock levels look healthy.',
                              style: TextStyle(color: _cream),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...lowItems.take(3).map(
                          (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _copper.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: _copper,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        color: _cream,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Remaining: ${item.quantity} ${item.unit}',
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                'LOW',
                                style: TextStyle(
                                  color: _copper,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(
            color: _caramel,
            fontSize: 9,
            letterSpacing: 0.8,
          ),
        ),
    ],
  );
}

class _Entrance extends StatefulWidget {
  const _Entrance({required this.child, required this.delay});

  final Widget child;
  final int delay;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.07),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _timer = Timer(
      Duration(milliseconds: widget.delay),
          () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.delay,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  final int delay;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _count;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _count = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _timer = Timer(
      Duration(milliseconds: widget.delay),
          () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _hovered ? const Color(0xFF3A2920) : _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _hovered
              ? widget.accent.withValues(alpha: 0.55)
              : Colors.white10,
        ),
        boxShadow: _hovered
            ? [
          BoxShadow(
            color: widget.accent.withValues(alpha: 0.08),
            blurRadius: 18,
          ),
        ]
            : [],
      ),
      child: FadeTransition(
        opacity: _fade,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(widget.icon, color: widget.accent, size: 22),
            AnimatedBuilder(
              animation: _count,
              builder: (_, __) => Text(
                (widget.value * _count.value).round().toString(),
                style: const TextStyle(
                  color: _cream,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() {
      _hovered = false;
      _pressed = false;
    }),
    child: GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            0,
            _hovered ? -3 : 0,
            0,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF3A2920) : _panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered
                  ? _caramel.withValues(alpha: 0.65)
                  : Colors.white12,
            ),
            boxShadow: _hovered
                ? [
              BoxShadow(
                color: _caramel.withValues(alpha: 0.09),
                blurRadius: 22,
              ),
            ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _caramel.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(widget.icon, color: _caramel, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: _caramel,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _caramel, size: 45),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: _cream,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}