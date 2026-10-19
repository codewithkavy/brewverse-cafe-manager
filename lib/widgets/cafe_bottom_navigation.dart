import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CafeBottomNavigation extends StatelessWidget {
  const CafeBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.referenceStyle = false,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool referenceStyle;

  @override
  Widget build(BuildContext context) {
    if (referenceStyle) {
      return _ReferenceNavigation(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      );
    }
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2_rounded),
          label: 'Inventory',
        ),
        NavigationDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale_rounded),
          label: 'Billing',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_border_rounded),
          selectedIcon: Icon(Icons.favorite_rounded),
          label: 'Loyalty',
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_rounded),
          selectedIcon: Icon(Icons.menu_rounded),
          label: 'More',
        ),
      ],
    );
  }
}

class _ReferenceNavigation extends StatelessWidget {
  const _ReferenceNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _labels = ['Home', 'Inventory', 'Billing', 'Loyalty', 'More'];
  static const _icons = [
    Icons.home_outlined,
    Icons.inventory_2_outlined,
    Icons.point_of_sale_outlined,
    Icons.favorite_border_rounded,
    Icons.menu_rounded,
  ];
  static const _selectedIcons = [
    Icons.home_rounded,
    Icons.inventory_2_rounded,
    Icons.point_of_sale_rounded,
    Icons.favorite_rounded,
    Icons.menu_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final extraTextHeight =
        (MediaQuery.textScalerOf(context).scale(9) - 9).clamp(0.0, 30.0);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48 + extraTextHeight * 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_labels.length, (index) {
              final selected = selectedIndex == index;
              void select() => onDestinationSelected(index);
              return Expanded(
                child: Semantics(
                  label: _labels[index],
                  button: true,
                  selected: selected,
                  onTap: select,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: select,
                    excludeFromSemantics: true,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      child: Align(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(minWidth: 48, maxWidth: 48),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFFFE7BD)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  selected
                                      ? _selectedIcons[index]
                                      : _icons[index],
                                  size: 18,
                                  color: AppTheme.ink,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _labels[index],
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.ink,
                                    fontSize: 9,
                                    height: 1.1,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Shared route behavior for tabs: the home route remains as the root, and
/// switching among secondary tabs replaces only the current tab route.
void selectCafeTab({
  required BuildContext context,
  required int currentIndex,
  required int nextIndex,
  required Widget Function(int index) pageForIndex,
}) {
  if (nextIndex == currentIndex) return;
  final navigator = Navigator.of(context);
  if (nextIndex == 0) {
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  final page = pageForIndex(nextIndex);
  if (currentIndex == 0) {
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  } else {
    navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
  }
}
