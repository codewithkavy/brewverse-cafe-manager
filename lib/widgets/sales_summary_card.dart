import 'package:flutter/material.dart';

import '../services/cafe_functions_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_sales_metrics.dart';

enum SalesReportMetric { sales, orders, items }

const dashboardSalesGradient = LinearGradient(
  colors: [Color(0xFF173E2D), Color(0xFF092E27)],
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
);

/// A tenant-scoped report generated from saved completed bills.
class SalesSummaryCard extends StatefulWidget {
  const SalesSummaryCard({
    required this.cafeId,
    this.rangeDays = 7,
    this.compact = false,
    this.showDashboardMetrics = false,
    this.functionsService,
    this.metric = SalesReportMetric.sales,
    super.key,
  });

  final String cafeId;
  final int rangeDays;
  final bool compact;
  final bool showDashboardMetrics;
  final CafeFunctionsService? functionsService;
  final SalesReportMetric metric;

  @override
  State<SalesSummaryCard> createState() => _SalesSummaryCardState();
}

class _SalesSummaryCardState extends State<SalesSummaryCard> {
  late CafeFunctionsService _functions =
      widget.functionsService ?? CafeFunctionsService();
  late Future<Map<String, dynamic>> _report = _load();

  Future<Map<String, dynamic>> _load() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _functions.getSalesSummary(
      cafeId: widget.cafeId,
      startAt: today.subtract(Duration(days: widget.rangeDays - 1)),
      endAt: today.add(const Duration(days: 1)),
    );
  }

  @override
  void didUpdateWidget(covariant SalesSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serviceChanged =
        oldWidget.functionsService != widget.functionsService;
    if (serviceChanged) {
      _functions = widget.functionsService ?? CafeFunctionsService();
    }
    if (oldWidget.rangeDays != widget.rangeDays ||
        oldWidget.cafeId != widget.cafeId ||
        serviceChanged) {
      _report = _load();
    }
  }

  void _refresh() {
    setState(() {
      _report = _load();
    });
  }

  Widget _compactPresentation(Widget surface,
      {Map<String, dynamic>? report, bool loading = false}) {
    if (!widget.showDashboardMetrics) return surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        surface,
        const SizedBox(height: 12),
        DashboardSalesMetrics(report: report, loading: loading),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final contents = FutureBuilder<Map<String, dynamic>>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          if (widget.compact) {
            return _compactPresentation(
              const _CompactReportStatus(
                message: 'Loading saved sales…',
                loading: true,
              ),
              loading: true,
            );
          }
          return SalesReportView(
            rangeDays: widget.rangeDays,
            metric: widget.metric,
            loading: true,
          );
        }
        if (snapshot.hasError) {
          if (widget.compact) {
            return _compactPresentation(_CompactReportStatus(
              message: 'Sales summary is unavailable right now.',
              onRefresh: _refresh,
            ));
          }
          return SalesReportView(
            rangeDays: widget.rangeDays,
            metric: widget.metric,
            statusMessage: 'Sales summary is unavailable right now.',
            onRefresh: _refresh,
          );
        }
        if (!snapshot.hasData) {
          if (widget.compact) {
            return _compactPresentation(
                const _CompactReportStatus(
                  message: 'Loading saved sales…',
                  loading: true,
                ),
                loading: true);
          }
          return SalesReportView(
            rangeDays: widget.rangeDays,
            metric: widget.metric,
            loading: true,
          );
        }
        if (widget.compact) {
          return _compactPresentation(
              _CompactReportContents(
                report: snapshot.data!,
                onRefresh: _refresh,
                showInlineMetrics: !widget.showDashboardMetrics,
              ),
              report: snapshot.data!);
        }
        return SalesReportView(
          report: snapshot.data!,
          onRefresh: _refresh,
          rangeDays: widget.rangeDays,
          metric: widget.metric,
        );
      },
    );
    return contents;
  }
}

/// Shared Analytics presentation for saved reports and explicit unavailable states.
class SalesReportView extends StatefulWidget {
  const SalesReportView({
    super.key,
    this.report,
    this.metric = SalesReportMetric.sales,
    this.rangeDays = 7,
    this.statusMessage,
    this.loading = false,
    this.onRefresh,
  });

  final Map<String, dynamic>? report;
  final SalesReportMetric metric;
  final int rangeDays;
  final String? statusMessage;
  final bool loading;
  final VoidCallback? onRefresh;

  @override
  State<SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<SalesReportView> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final revenue = report?['grossRevenue'];
    final bills = report?['completedBillCount'];
    final itemsSold = report?['itemsSold'];
    final bestSellers = report?['bestSellingProducts'];
    final valid = revenue is num &&
        revenue.isFinite &&
        bills is int &&
        bills >= 0 &&
        itemsSold is int &&
        itemsSold >= 0 &&
        bestSellers is List;
    final products = valid
        ? bestSellers
            .whereType<Map>()
            .where((product) =>
                product['name'] is String &&
                product['quantitySold'] is int &&
                product['revenue'] is num)
            .toList()
        : <Map>[];
    final peakQuantity = products.fold<int>(
      0,
      (peak, product) => (product['quantitySold'] as int) > peak
          ? product['quantitySold'] as int
          : peak,
    );
    final title = switch (widget.metric) {
      SalesReportMetric.sales => 'Total sales',
      SalesReportMetric.orders => 'Total orders',
      SalesReportMetric.items => 'Items sold',
    };
    final metricNote = switch (widget.metric) {
      SalesReportMetric.sales => 'After refunds',
      SalesReportMetric.orders => 'Completed bills',
      SalesReportMetric.items => 'Billed quantities',
    };
    final value = !valid
        ? '—'
        : switch (widget.metric) {
            SalesReportMetric.sales => '₹${revenue.toStringAsFixed(2)}',
            SalesReportMetric.orders => '$bills',
            SalesReportMetric.items => '$itemsSold',
          };
    final status = widget.loading
        ? 'Loading saved sales…'
        : widget.statusMessage ??
            (report == null
                ? 'No café report connected'
                : 'Saved sales data could not be read.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnalyticsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: AppTheme.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 7),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(value,
                                style: const TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 28,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onRefresh != null)
                    IconButton(
                      tooltip: 'Refresh sales summary',
                      onPressed: widget.onRefresh,
                      icon: const _ReportBadge(),
                    )
                  else
                    const _ReportBadge(),
                ],
              ),
              const SizedBox(height: 7),
              if (widget.loading)
                Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                        child: Text(status,
                            style: const TextStyle(
                                color: AppTheme.mutedInk, fontSize: 10))),
                  ],
                )
              else
                Text(
                  valid
                      ? 'Last ${widget.rangeDays} days · $metricNote'
                      : status,
                  style: const TextStyle(
                      color: AppTheme.mutedInk, fontSize: 10, height: 1.3),
                ),
              const SizedBox(height: 11),
              const _UnavailableTrend(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AnalyticsMetric(
                label: 'Total orders',
                value: valid ? '$bills' : '—',
                icon: Icons.shopping_cart_outlined,
                accent: AppTheme.orangeDeep,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _AnalyticsMetric(
                label: 'Avg. order',
                value: valid && bills > 0
                    ? '₹${(revenue / bills).toStringAsFixed(2)}'
                    : '—',
                icon: Icons.query_stats_rounded,
                accent: AppTheme.emerald,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AnalyticsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Best-selling items',
                        style: TextStyle(
                            color: AppTheme.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (products.length > 4)
                    TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.orangeDeep,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        textStyle: const TextStyle(fontSize: 10),
                      ),
                      child: Text(_showAll ? 'Show less' : 'View all'),
                    ),
                ],
              ),
              if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 13, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.emoji_events_outlined,
                          color: AppTheme.orangeDeep, size: 23),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          valid
                              ? 'No completed sales in this period.'
                              : widget.loading
                                  ? 'Loading best sellers…'
                                  : report == null && widget.onRefresh == null
                                      ? 'Select a café to see its best sellers.'
                                      : 'Best sellers are unavailable right now.',
                          style: const TextStyle(
                              color: AppTheme.mutedInk,
                              fontSize: 11,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final entry
                    in products.take(_showAll ? products.length : 4).indexed)
                  _BestSellerRow(
                    product: entry.$2,
                    rank: entry.$1 + 1,
                    peakQuantity: peakQuantity,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsSurface extends StatelessWidget {
  const _AnalyticsSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: child,
      );
}

class _ReportBadge extends StatelessWidget {
  const _ReportBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppTheme.softOrange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.bar_chart_rounded,
            size: 19, color: AppTheme.orangeDeep),
      );
}

class _UnavailableTrend extends StatelessWidget {
  const _UnavailableTrend();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.softGreen.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart_rounded, size: 22, color: AppTheme.emerald),
            SizedBox(height: 4),
            Text('Daily trend unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.emerald,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => _AnalyticsSurface(
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.1)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.mutedInk, fontSize: 9, height: 1.1)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CompactReportContents extends StatelessWidget {
  const _CompactReportContents({
    required this.report,
    required this.onRefresh,
    this.showInlineMetrics = true,
  });

  final Map<String, dynamic> report;
  final VoidCallback onRefresh;
  final bool showInlineMetrics;

  @override
  Widget build(BuildContext context) {
    final revenue = report['grossRevenue'];
    final bills = report['completedBillCount'];
    final itemsSold = report['itemsSold'];
    if (revenue is! num ||
        !revenue.isFinite ||
        revenue < 0 ||
        bills is! int ||
        bills < 0 ||
        itemsSold is! int ||
        itemsSold < 0) {
      return _CompactReportStatus(
        message: 'Saved sales data could not be read.',
        onRefresh: onRefresh,
      );
    }

    return _CompactSalesSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's sales",
                  style: TextStyle(
                    color: DashboardPalette.softGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh sales summary',
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: DashboardPalette.orange),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '₹${revenue.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: DashboardPalette.orange,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.coffee_outlined,
                    color: DashboardPalette.forest, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (showInlineMetrics)
            Row(
              children: [
                Expanded(
                    child: _CompactMetric(label: 'Bills', value: '$bills')),
                Expanded(
                  child:
                      _CompactMetric(label: 'Items sold', value: '$itemsSold'),
                ),
                Expanded(
                  child: _CompactMetric(
                    label: 'Avg. bill',
                    value: bills == 0
                        ? '—'
                        : '₹${(revenue / bills).toStringAsFixed(0)}',
                  ),
                ),
              ],
            )
          else
            const Text('Daily chart unavailable',
                style:
                    TextStyle(color: DashboardPalette.softGreen, fontSize: 10)),
        ],
      ),
    );
  }
}

class _CompactSalesSurface extends StatelessWidget {
  const _CompactSalesSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 138),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: dashboardSalesGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class _CompactReportStatus extends StatelessWidget {
  const _CompactReportStatus({
    required this.message,
    this.loading = false,
    this.onRefresh,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => _CompactSalesSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TODAY'S SALES",
              style: TextStyle(
                color: DashboardPalette.softGreen,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DashboardPalette.softGreen,
                    ),
                  )
                else
                  const Icon(Icons.cloud_off_rounded,
                      size: 20, color: DashboardPalette.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: DashboardPalette.softGreen,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Retry sales summary',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded,
                        color: DashboardPalette.orange, size: 20),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 9,
            ),
          ),
        ],
      );
}

class _BestSellerRow extends StatelessWidget {
  const _BestSellerRow({
    required this.product,
    required this.rank,
    required this.peakQuantity,
  });

  final Map product;
  final int rank;
  final int peakQuantity;

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String;
    final quantity = product['quantitySold'] as int;
    final revenue = product['revenue'] as num;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: rank == 1 ? AppTheme.orangeDeep : AppTheme.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          const SizedBox(width: 7),
          Container(
            width: 34,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.softOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.restaurant_menu_rounded,
                size: 18, color: AppTheme.orangeDeep),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('$quantity sold',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppTheme.mutedInk, fontSize: 10)),
                    ),
                  ],
                ),
                Text('₹${revenue.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppTheme.mutedInk, fontSize: 10)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: peakQuantity <= 0
                        ? 0
                        : (quantity / peakQuantity).clamp(0, 1).toDouble(),
                    minHeight: 4,
                    backgroundColor: AppTheme.softOrange,
                    color: AppTheme.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
