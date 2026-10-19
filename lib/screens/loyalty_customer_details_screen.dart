import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoyaltyCustomerDetailsScreen extends StatelessWidget {
  const LoyaltyCustomerDetailsScreen({
    required this.customer,
    required this.phoneNumber,
    required this.pointValueMinor,
    required this.onStartBill,
    this.onBack,
    super.key,
  });

  final Map<String, dynamic> customer;
  final String phoneNumber;
  final int? pointValueMinor;
  final VoidCallback? onStartBill;
  final VoidCallback? onBack;

  int? get _balance {
    final value = customer['pointsBalance'];
    return customer['found'] == true && value is int && value >= 0
        ? value
        : null;
  }

  String get _maskedPhone {
    final canonical = customer['phoneNumber'];
    final normalized = canonical is String && canonical.trim().isNotEmpty
        ? canonical.trim()
        : phoneNumber.trim();
    if (normalized.length <= 4) return normalized;
    return '${'•' * (normalized.length - 4)}${normalized.substring(normalized.length - 4)}';
  }

  BigInt? get _availableMinor {
    final balance = _balance;
    final value = pointValueMinor;
    return balance == null || value == null || value <= 0
        ? null
        : BigInt.from(balance) * BigInt.from(value);
  }

  String _money(BigInt amount) {
    final hundred = BigInt.from(100);
    final whole = amount ~/ hundred;
    final remainder = (amount % hundred).toInt();
    return '₹$whole${remainder == 0 ? '' : '.${remainder.toString().padLeft(2, '0')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balance;
    final confirmed = balance != null;
    final available = _availableMinor;
    final pointsLabel = confirmed ? '$balance' : '—';
    final valueLabel = available == null ? '—' : _money(available);
    final canEarn = confirmed && onStartBill != null;
    final canRedeem = canEarn && balance > 0 && available != null;
    final canGoBack = onBack != null || Navigator.of(context).canPop();

    return Theme(
      data: AppTheme.emeraldLight,
      child: Scaffold(
        backgroundColor: AppTheme.forest,
        appBar: AppBar(
          toolbarHeight: 52,
          backgroundColor: AppTheme.forest,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          leadingWidth: 42,
          leading: canGoBack
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 21),
                )
              : null,
          titleSpacing: canGoBack ? 0 : 14,
          title: const Text('Customer details',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _CustomerIdentity(
                    confirmed: confirmed,
                    phone: _maskedPhone,
                  ),
                ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppTheme.card,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cards = [
                                _BalanceCard(
                                    label: 'Total points',
                                    value: pointsLabel,
                                    icon: Icons.card_giftcard_rounded,
                                    accent: AppTheme.emerald),
                                _BalanceCard(
                                    label: 'Available value',
                                    value: valueLabel,
                                    icon: Icons.account_balance_wallet_outlined,
                                    accent: AppTheme.emerald),
                              ];
                              final stacked = constraints.maxWidth < 230 ||
                                  MediaQuery.textScalerOf(context).scale(13) >
                                      17 ||
                                  pointsLabel.length > 7 ||
                                  valueLabel.length > 9;
                              if (stacked) {
                                return Column(children: [
                                  cards[0],
                                  const SizedBox(height: 9),
                                  cards[1]
                                ]);
                              }
                              return Row(children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 10),
                                Expanded(child: cards[1]),
                              ]);
                            },
                          ),
                          if (confirmed && available == null) ...[
                            const SizedBox(height: 8),
                            const Text('Point value unavailable',
                                style: TextStyle(
                                    color: AppTheme.orangeDeep, fontSize: 11)),
                          ],
                          const SizedBox(height: 12),
                          _CheckoutActions(
                            onEarn: canEarn ? onStartBill : null,
                            onRedeem: canRedeem ? onStartBill : null,
                          ),
                          const SizedBox(height: 9),
                          Text(
                            confirmed
                                ? 'Checkout applies your café’s rewards policy. No points are changed here.'
                                : 'Look up a member in Loyalty to use checkout.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppTheme.mutedInk,
                                fontSize: 11,
                                height: 1.4),
                          ),
                          const SizedBox(height: 21),
                          const Text('Points history',
                              style: TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 9),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                                color: AppTheme.paper,
                                borderRadius: BorderRadius.circular(15)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    width: 33,
                                    height: 33,
                                    decoration: BoxDecoration(
                                        color: AppTheme.softOrange,
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: const Icon(Icons.history_rounded,
                                        color: AppTheme.orangeDeep, size: 20)),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Transaction history unavailable',
                                          style: TextStyle(
                                              color: AppTheme.ink,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                      SizedBox(height: 5),
                                      Text(
                                          'Points history is not available here yet. No transactions are shown.',
                                          style: TextStyle(
                                              color: AppTheme.mutedInk,
                                              fontSize: 11,
                                              height: 1.4)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (confirmed) ...[
                            const SizedBox(height: 12),
                            const Text('Balance from your latest lookup',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.mutedInk, fontSize: 10)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: ColoredBox(color: AppTheme.card),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerIdentity extends StatelessWidget {
  const _CustomerIdentity({required this.confirmed, required this.phone});
  final bool confirmed;
  final String phone;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _ProfileCurve(),
              child: const ColoredBox(color: AppTheme.card),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 17),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppTheme.emeraldBright, AppTheme.forest],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.card, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: AppTheme.forest.withValues(alpha: 0.16),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Icon(Icons.person_outline_rounded,
                        color: Colors.white, size: 33),
                  ),
                  const SizedBox(height: 12),
                  Text(confirmed ? 'Loyalty member' : 'No customer selected',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15)),
                  const SizedBox(height: 5),
                  Text(
                      confirmed
                          ? phone.isEmpty
                              ? 'Phone unavailable'
                              : phone
                          : 'Look up a customer in Loyalty.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.mutedInk, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ProfileCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 86)
    ..quadraticBezierTo(size.width / 2, -2, size.width, 86)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant _ProfileCurve oldClipper) => false;
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
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
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.line),
          boxShadow: [
            BoxShadow(
                color: AppTheme.forest.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: accent, size: 19),
              const SizedBox(width: 7),
              Expanded(
                  child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(value,
                          style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800)))),
            ]),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.mutedInk, fontSize: 10, height: 1.3)),
          ],
        ),
      );
}

class _CheckoutActions extends StatelessWidget {
  const _CheckoutActions({required this.onEarn, required this.onRedeem});
  final VoidCallback? onEarn;
  final VoidCallback? onRedeem;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          Widget action(String label, IconData icon, VoidCallback? onPressed,
                  {required bool redeem}) =>
              FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      redeem ? AppTheme.orange : AppTheme.softGreen,
                  foregroundColor: AppTheme.forest,
                  disabledBackgroundColor:
                      redeem ? AppTheme.softOrange : AppTheme.softGreen,
                  disabledForegroundColor: AppTheme.mutedInk,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 17),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700))),
                  ],
                ),
              );
          final earn = action('Earn at checkout', Icons.add_rounded, onEarn,
              redeem: false);
          final redeem = action(
              'Redeem at checkout', Icons.arrow_forward_rounded, onRedeem,
              redeem: true);
          if (MediaQuery.textScalerOf(context).scale(13) > 17 ||
              constraints.maxWidth < 230) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [earn, const SizedBox(height: 9), redeem]);
          }
          return Row(children: [
            Expanded(child: earn),
            const SizedBox(width: 10),
            Expanded(child: redeem)
          ]);
        },
      );
}
