import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dashboard totals from the existing saved-sales report, without another fetch.
class DashboardSalesMetrics extends StatelessWidget {
  const DashboardSalesMetrics({super.key, this.report, this.loading = false});

  final Map<String, dynamic>? report;
  final bool loading;

  static const _customersUnavailable =
      'New customer totals are unavailable in the current sales report.';

  @override
  Widget build(BuildContext context) {
    final orders = report?['completedBillCount'];
    final items = report?['itemsSold'];
    final revenue = report?['grossRevenue'];
    final validOrders = !loading && orders is int && orders >= 0;
    final validItems = !loading && items is int && items >= 0;
    final validRevenue =
        !loading && revenue is num && revenue.isFinite && revenue >= 0;
    final average = validOrders && orders > 0 && validRevenue
        ? _averageMoney(revenue, orders)
        : null;
    final metrics = [
      _Metric(
        id: 'orders',
        label: 'Orders',
        value: validOrders ? '$orders' : '—',
        icon: Icons.receipt_long_outlined,
        accent: AppTheme.orangeDeep,
        background: AppTheme.softOrange,
      ),
      const _Metric(
        id: 'customers',
        label: 'New customers',
        value: '—',
        icon: Icons.person_outline_rounded,
        accent: AppTheme.emerald,
        background: AppTheme.softGreen,
        explanation: _customersUnavailable,
      ),
      _Metric(
        id: 'items',
        label: 'Items sold',
        value: validItems ? '$items' : '—',
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFF3E79C2),
        background: const Color(0xFFEBF2FC),
      ),
      _Metric(
        id: 'average',
        label: 'Avg. order value',
        value: average ?? '—',
        icon: Icons.bar_chart_rounded,
        accent: AppTheme.orangeDeep,
        background: AppTheme.softOrange,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 980 ? 4 : 2;
      const gap = 8.0;
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Semantics(
        label: loading ? 'Loading saved sales metrics' : null,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(metric: metric),
              ),
          ],
        ),
      );
    });
  }

  // Use the decimal representation of the stored amount so an average retains
  // its paise instead of silently rounding to whole rupees or losing precision
  // when the report contains a large finite amount.
  static String _averageMoney(num revenue, int orders) {
    final parts = revenue.toString().toLowerCase().split('e');
    final decimal = parts.first.split('.');
    final fractional = decimal.length == 2 ? decimal[1] : '';
    final exponent = parts.length == 2 ? int.parse(parts[1]) : 0;
    var numerator =
        BigInt.parse('${decimal.first}$fractional') * BigInt.from(100);
    var denominator = BigInt.from(orders);
    final scale = fractional.length - exponent;
    if (scale > 0) {
      denominator *= BigInt.from(10).pow(scale);
    } else if (scale < 0) {
      numerator *= BigInt.from(10).pow(-scale);
    }
    final minor =
        (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    final whole = minor ~/ BigInt.from(100);
    final paise = (minor % BigInt.from(100)).toString().padLeft(2, '0');
    return '₹$whole${paise == '00' ? '' : '.$paise'}';
  }
}

class _Metric {
  const _Metric({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.background,
    this.explanation,
  });

  final String id;
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Color background;
  final String? explanation;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 12;
    final label = Text(
      metric.label,
      style: const TextStyle(
        color: AppTheme.mutedInk,
        fontSize: 9,
        height: 1.2,
      ),
    );
    final value = SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          metric.value,
          key: ValueKey('dashboard-${metric.id}-value'),
          style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 20,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
      ),
    );
    final card = Semantics(
      label: '${metric.label}: '
          '${metric.value == '—' ? 'Unavailable' : metric.value}'
          '${metric.explanation == null ? '' : '. ${metric.explanation}'}',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('dashboard-${metric.id}-card'),
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.line.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.forest.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  color: metric.background,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(metric.icon, color: metric.accent, size: 17),
              ),
              const SizedBox(height: 6),
              if (largeText) ...[
                value,
                const SizedBox(height: 3),
                label,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(flex: 5, child: value),
                    const SizedBox(width: 5),
                    Flexible(flex: 6, child: label),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    return metric.explanation == null
        ? card
        : Tooltip(message: metric.explanation!, child: card);
  }
}
