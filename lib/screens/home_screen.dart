import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stock_item.dart';
import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../services/cafe_functions_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import '../widgets/sales_summary_card.dart';
import '../widgets/dashboard_sales_metrics.dart';
import 'analytics_screen.dart';
import 'billing_screen.dart';
import 'bill_adjustment_screen.dart';
import 'cafe_team_screen.dart';
import 'inventory_screen.dart';

enum _DashboardAction { adjustBill, team, switchCafe }

const _dashboardHeading = Color(0xFF202822);
const _dashboardPaper = Color(0xFFFBF8F3);

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.cafeId,
    this.cafeRole,
    this.onSwitchCafe,
    this.stockStream,
    this.cafeService,
    this.salesFunctionsService,
    this.currentTime,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final VoidCallback? onSwitchCafe;
  final Stream<List<StockItem>>? stockStream;
  final CafeService? cafeService;
  final CafeFunctionsService? salesFunctionsService;
  final DateTime? currentTime;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 360),
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
                begin: const Offset(0.025, 0),
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
    final service = cafeService ??
        (stockStream == null ? CafeService(cafeId: cafeId) : null);
    final canManageCafe = cafeId != null &&
        (cafeRole == CafeRole.owner || cafeRole == CafeRole.manager);

    return Theme(
      data: AppTheme.emeraldLight.copyWith(
        scaffoldBackgroundColor: _dashboardPaper,
        appBarTheme: AppTheme.emeraldLight.appBarTheme.copyWith(
          backgroundColor: _dashboardPaper,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Open café menu',
            onPressed: () => _open(
              context,
              cafeTabPage(4,
                  cafeId: cafeId, cafeRole: cafeRole, cafeService: service),
            ),
            icon: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: DashboardPalette.forest,
                borderRadius: BorderRadius.circular(7),
              ),
              child:
                  const Icon(Icons.menu_rounded, color: Colors.white, size: 17),
            ),
          ),
          titleSpacing: 0,
          title: const Row(
            children: [
              Icon(
                Icons.coffee_rounded,
                color: DashboardPalette.orangeDeep,
                size: 25,
              ),
              SizedBox(width: 7),
              Flexible(
                child: Text(
                  'BrewVerse',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _dashboardHeading, fontSize: 18),
                ),
              ),
            ],
          ),
          actions: [
            if (canManageCafe || onSwitchCafe != null)
              PopupMenuButton<_DashboardAction>(
                tooltip: 'Café actions',
                onSelected: (action) {
                  switch (action) {
                    case _DashboardAction.adjustBill:
                      _open(
                          context,
                          BillAdjustmentScreen(
                              cafeId: cafeId!, role: cafeRole!));
                    case _DashboardAction.team:
                      _open(
                          context,
                          CafeTeamScreen(
                              cafeId: cafeId!, callerRole: cafeRole!));
                    case _DashboardAction.switchCafe:
                      onSwitchCafe?.call();
                  }
                },
                itemBuilder: (_) => [
                  if (canManageCafe) ...[
                    const PopupMenuItem(
                      value: _DashboardAction.adjustBill,
                      child: Text('Refund or void bill'),
                    ),
                    const PopupMenuItem(
                      value: _DashboardAction.team,
                      child: Text('Café team'),
                    ),
                  ],
                  if (onSwitchCafe != null)
                    const PopupMenuItem(
                      value: _DashboardAction.switchCafe,
                      child: Text('Switch café'),
                    ),
                ],
              ),
          ],
        ),
        body: StreamBuilder<List<StockItem>>(
          stream: stockStream ?? service!.watchStock(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Inventory unavailable',
                message: 'Check your connection and Firebase settings.',
              );
            }

            if (!snapshot.hasData) {
              return const _LoadingDashboard();
            }

            final items = snapshot.data!;
            final lowItems = items.where((item) => item.isLow).toList();
            final ingredients =
                items.where((item) => item.category == 'ingredient').length;
            final finished =
                items.where((item) => item.category == 'finished').length;

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final wide = width >= 760;
                final columns = width >= 980 ? 4 : 2;
                final horizontalPadding = width < 400 ? 16.0 : 24.0;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        8,
                        horizontalPadding,
                        24,
                      ),
                      children: [
                        _Entrance(
                          child: _WelcomePanel(
                            now: currentTime ?? DateTime.now(),
                            cafeRole: cafeRole,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (cafeId != null)
                          SalesSummaryCard(
                            cafeId: cafeId!,
                            rangeDays: 1,
                            compact: true,
                            showDashboardMetrics: true,
                            functionsService: salesFunctionsService,
                          )
                        else
                          const Column(
                            children: [
                              _SalesUnavailableCard(),
                              SizedBox(height: 12),
                              DashboardSalesMetrics(),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Quick actions',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    color: _dashboardHeading,
                                  ),
                        ),
                        const SizedBox(height: 7),
                        if (wide)
                          Row(
                            children: [
                              Expanded(
                                child: _ActionCard(
                                  title: 'Inventory',
                                  description: 'Manage ingredients and stock',
                                  detail: 'STOCK & RECIPES',
                                  icon: Icons.inventory_2_rounded,
                                  onTap: () => _open(
                                    context,
                                    InventoryScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                      canManageInventory: cafeId == null ||
                                          (cafeRole?.canManageInventory ??
                                              false),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _ActionCard(
                                  title: 'Analytics',
                                  description: 'Review saved sales reports',
                                  detail: 'SALES INSIGHTS',
                                  icon: Icons.query_stats_rounded,
                                  onTap: () => _open(
                                    context,
                                    AnalyticsScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _ActionCard(
                                  title: 'Billing',
                                  description: 'Build a bill and check out',
                                  detail: 'NEW ORDER',
                                  icon: Icons.point_of_sale_rounded,
                                  onTap: () => _open(
                                    context,
                                    BillingScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                      stockStream: service?.watchStock(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _QuickActionTile(
                                  title: 'New bill',
                                  primary: true,
                                  icon: Icons.point_of_sale_rounded,
                                  onTap: () => _open(
                                    context,
                                    BillingScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                      stockStream: service?.watchStock(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _QuickActionTile(
                                  title: 'Inventory',
                                  icon: Icons.inventory_2_rounded,
                                  onTap: () => _open(
                                    context,
                                    InventoryScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                      canManageInventory: cafeId == null ||
                                          (cafeRole?.canManageInventory ??
                                              false),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _QuickActionTile(
                                  title: cafeId == null ||
                                          (cafeRole?.canManageInventory ??
                                              false)
                                      ? 'Add stock'
                                      : 'Stock',
                                  icon: Icons.add_box_rounded,
                                  onTap: () => _open(
                                    context,
                                    InventoryScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                      openAddItemOnStart: cafeId == null ||
                                          (cafeRole?.canManageInventory ??
                                              false),
                                      canManageInventory: cafeId == null ||
                                          (cafeRole?.canManageInventory ??
                                              false),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: _QuickActionTile(
                                  title: 'Analytics',
                                  icon: Icons.query_stats_rounded,
                                  onTap: () => _open(
                                    context,
                                    AnalyticsScreen(
                                      cafeId: cafeId,
                                      cafeRole: cafeRole,
                                      cafeService: service,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 14),
                        _SectionHeader(
                          eyebrow: 'STOCK HEALTH',
                          title: lowItems.isEmpty
                              ? 'Stock overview'
                              : 'Needs attention',
                          trailing: items.isEmpty
                              ? 'No items yet'
                              : lowItems.isEmpty
                                  ? 'All clear'
                                  : '${lowItems.length} ${lowItems.length == 1 ? 'item' : 'items'}',
                        ),
                        const SizedBox(height: 14),
                        GridView(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 72 +
                                (MediaQuery.textScalerOf(context).scale(14) -
                                        14) *
                                    2.8,
                          ),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _StatCard(
                              label: 'Total items',
                              value: items.length,
                              icon: Icons.inventory_2_outlined,
                              accent: DashboardPalette.orange,
                              delay: 60,
                            ),
                            _StatCard(
                              label: 'Low stock',
                              value: lowItems.length,
                              icon: Icons.warning_amber_rounded,
                              accent: lowItems.isEmpty
                                  ? DashboardPalette.emerald
                                  : DashboardPalette.orangeDeep,
                              delay: 120,
                            ),
                            _StatCard(
                              label: 'Ingredients',
                              value: ingredients,
                              icon: Icons.grass_rounded,
                              accent: DashboardPalette.emerald,
                              delay: 180,
                            ),
                            _StatCard(
                              label: 'Finished goods',
                              value: finished,
                              icon: Icons.coffee_rounded,
                              accent: DashboardPalette.orangeDeep,
                              delay: 240,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (items.isEmpty)
                          const _EmptyInventoryCard()
                        else if (lowItems.isEmpty)
                          const _HealthyStockCard()
                        else
                          ...lowItems.take(3).map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _LowStockCard(item: item),
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        bottomNavigationBar: CafeBottomNavigation(
          referenceStyle: true,
          selectedIndex: 0,
          onDestinationSelected: (index) => selectCafeTab(
            context: context,
            currentIndex: 0,
            nextIndex: index,
            pageForIndex: (index) => cafeTabPage(
              index,
              cafeId: cafeId,
              cafeRole: cafeRole,
              cafeService: service,
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.now, required this.cafeRole});

  final DateTime now;
  final CafeRole? cafeRole;

  @override
  Widget build(BuildContext context) {
    final greeting = _greeting(now);
    final title = cafeRole == CafeRole.owner ? 'Cafe Owner!' : 'Cafe team!';
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting,',
                  style: const TextStyle(
                    color: _dashboardHeading,
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: const TextStyle(
                    color: _dashboardHeading,
                    fontSize: 24,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.55,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Great coffee. Greater days ahead.',
                  style: TextStyle(
                    color: DashboardPalette.mutedInk,
                    fontSize: MediaQuery.sizeOf(context).width < 320 ? 10 : 11,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: DashboardPalette.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: DashboardPalette.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 12, color: DashboardPalette.emerald),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Today, ${_formatDashboardDate(now)}',
                          style: const TextStyle(
                            color: DashboardPalette.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: SizedBox(
              width: 76,
              height: 104,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.wb_sunny_rounded,
                          color: DashboardPalette.orange, size: 27),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scale: 1.2,
                      alignment: Alignment.bottomRight,
                      child: Image.asset(
                        'assets/images/dashboard-coffee.png',
                        width: 76,
                        height: 77,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String _formatDashboardDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.trailing,
  });

  final String eyebrow;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: DashboardPalette.orangeDeep,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.45,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 19,
                        letterSpacing: -0.25,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.33,
            ),
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      );
}

class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

class _SalesUnavailableCard extends StatelessWidget {
  const _SalesUnavailableCard();

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 138),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: dashboardSalesGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's sales",
                    style: TextStyle(
                      color: DashboardPalette.softGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Sales report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Choose a café to view saved totals.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: DashboardPalette.softGreen,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: DashboardPalette.orange,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.coffee_outlined,
                  color: DashboardPalette.forest, size: 20),
            ),
          ],
        ),
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
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _count = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _timer = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                _hovered ? DashboardPalette.softGreen : DashboardPalette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.42)
                  : DashboardPalette.line,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.07),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(widget.icon, color: widget.accent, size: 15),
              ),
              const SizedBox(height: 3),
              AnimatedBuilder(
                animation: _count,
                builder: (_, __) => Text(
                  (widget.value * _count.value).round().toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DashboardPalette.ink,
                    fontSize: 21,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DashboardPalette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      );
}

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Material(
          color: widget.primary
              ? DashboardPalette.emerald
              : DashboardPalette.softGreen,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DashboardPalette.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon,
                      color: widget.primary
                          ? Colors.white
                          : DashboardPalette.emerald,
                      size: 20),
                  const SizedBox(height: 3),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          widget.primary ? Colors.white : DashboardPalette.ink,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final String detail;
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
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
            decoration: BoxDecoration(
              color:
                  _hovered ? DashboardPalette.softGreen : DashboardPalette.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _hovered
                    ? DashboardPalette.orange.withValues(alpha: 0.42)
                    : DashboardPalette.line,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color:
                            DashboardPalette.orangeDeep.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTapUp: (_) => setState(() => _pressed = false),
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              DashboardPalette.softOrange,
                              DashboardPalette.orange.withValues(alpha: 0.16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: DashboardPalette.line,
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color: DashboardPalette.orange,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.detail,
                              style: const TextStyle(
                                color: DashboardPalette.orangeDeep,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: DashboardPalette.orange,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _HealthyStockCard extends StatelessWidget {
  const _HealthyStockCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: DashboardPalette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: DashboardPalette.emerald.withValues(alpha: 0.16)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: DashboardPalette.emerald, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'All stock levels look healthy.',
                style: TextStyle(
                  color: DashboardPalette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'ALL CLEAR',
              style: TextStyle(
                color: DashboardPalette.emerald,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: DashboardPalette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: DashboardPalette.orangeDeep.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            _StockThumbnail(item: item),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: DashboardPalette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Remaining: ${item.quantity} ${item.unit}',
                    style: const TextStyle(
                      color: DashboardPalette.mutedInk,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: DashboardPalette.orangeDeep.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'LOW',
                style: TextStyle(
                  color: DashboardPalette.orangeDeep,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
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
              Icon(icon, color: DashboardPalette.orange, size: 45),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
}

class _StockThumbnail extends StatelessWidget {
  const _StockThumbnail({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final photoUrl = item.photoUrl.trim();
    final placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: DashboardPalette.softOrange,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.warning_amber_rounded,
        color: DashboardPalette.orangeDeep,
        size: 21,
      ),
    );
    if (photoUrl.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        photoUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _EmptyInventoryCard extends StatelessWidget {
  const _EmptyInventoryCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DashboardPalette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DashboardPalette.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.inventory_2_outlined,
                color: DashboardPalette.emerald, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory is ready for your first item',
                    style: TextStyle(
                      color: DashboardPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add stock to start tracking café operations.',
                    style: TextStyle(color: DashboardPalette.mutedInk),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _LoadingDashboard extends StatelessWidget {
  const _LoadingDashboard();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text(
              'Loading your live café data…',
              style: TextStyle(color: DashboardPalette.mutedInk),
            ),
          ],
        ),
      );
}
