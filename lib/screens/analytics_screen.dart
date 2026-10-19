import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_functions_service.dart';
import '../services/cafe_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import '../widgets/sales_summary_card.dart';
import 'home_screen.dart';

/// Sales analytics from the existing saved-bill report. Changing the displayed
/// metric does not request another report or fabricate daily trend data.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    this.cafeId,
    this.cafeRole,
    this.cafeService,
    this.functionsService,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final CafeService? cafeService;
  final CafeFunctionsService? functionsService;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _rangeDays = 7;
  SalesReportMetric _metric = SalesReportMetric.sales;

  HomeScreen _homePage() => HomeScreen(
        cafeId: widget.cafeId,
        cafeRole: widget.cafeRole,
        cafeService: widget.cafeService,
        stockStream: widget.cafeService?.watchStock(),
        salesFunctionsService: widget.functionsService,
      );

  void _goHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => _homePage(),
    ));
  }

  void _selectDestination(int index) {
    if (index == 0) {
      _goHome();
      return;
    }
    final navigator = Navigator.of(context);
    Widget pageForIndex(int selected) => cafeTabPage(
          selected,
          cafeId: widget.cafeId,
          cafeRole: widget.cafeRole,
          cafeService: widget.cafeService,
        );
    if (!navigator.canPop()) {
      // Standalone previews and direct routes need the same Home root as the app.
      navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _homePage()));
      navigator
          .push(MaterialPageRoute<void>(builder: (_) => pageForIndex(index)));
      return;
    }
    selectCafeTab(
      context: context,
      currentIndex: -1,
      nextIndex: index,
      pageForIndex: pageForIndex,
    );
  }

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _goHome();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          backgroundColor: AppTheme.forest,
          appBar: AppBar(
            backgroundColor: AppTheme.forest,
            foregroundColor: Colors.white,
            toolbarHeight: 52,
            leadingWidth: 42,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 21),
            ),
            titleSpacing: 0,
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            title: const Text('Analytics'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.11),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _rangeDays,
                      isDense: true,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: AppTheme.card,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 18),
                      iconEnabledColor: Colors.white,
                      iconDisabledColor: AppTheme.softGreen,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedItemBuilder: (context) => [
                        for (final days in const [7, 30])
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '$days days',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                      ],
                      onChanged: widget.cafeId == null
                          ? null
                          : (value) {
                              if (value != null && value != _rangeDays) {
                                setState(() => _rangeDays = value);
                              }
                            },
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 22),
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        for (final entry in const {
                          SalesReportMetric.sales: 'Sales',
                          SalesReportMetric.orders: 'Orders',
                          SalesReportMetric.items: 'Items',
                        }.entries)
                          Expanded(
                            child: _MetricTab(
                              label: entry.value,
                              selected: _metric == entry.key,
                              onTap: () => setState(() => _metric = entry.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.cafeId == null)
                    SalesReportView(
                      metric: _metric,
                      rangeDays: _rangeDays,
                      statusMessage: 'No café report connected',
                    )
                  else
                    SalesSummaryCard(
                      cafeId: widget.cafeId!,
                      rangeDays: _rangeDays,
                      metric: _metric,
                      functionsService: widget.functionsService,
                    ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: CafeBottomNavigation(
            selectedIndex: 0,
            onDestinationSelected: _selectDestination,
          ),
        ),
      );
}

class _MetricTab extends StatelessWidget {
  const _MetricTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: selected ? AppTheme.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppTheme.forest : AppTheme.softGreen,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
}
