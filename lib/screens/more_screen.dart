import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cafe_bottom_navigation.dart';
import '../widgets/cafe_tab_page_factory.dart';
import 'cafe_team_screen.dart';
import 'loyalty_settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.cafeId,
    this.cafeRole,
    this.cafeService,
  });

  final String? cafeId;
  final CafeRole? cafeRole;
  final CafeService? cafeService;

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.emeraldLight,
        child: Scaffold(
          appBar: AppBar(title: const Text('More')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _MoreTile(
                    icon: Icons.groups_2_rounded,
                    title: 'Café team',
                    subtitle: cafeId == null
                        ? 'Select a café workspace first'
                        : 'Manage staff access and roles',
                    enabled: cafeId != null &&
                        (cafeRole == CafeRole.owner ||
                            cafeRole == CafeRole.manager),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CafeTeamScreen(
                          cafeId: cafeId!,
                          callerRole: cafeRole!,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MoreTile(
                    icon: Icons.favorite_rounded,
                    title: 'Loyalty settings',
                    subtitle: cafeId == null
                        ? 'Select a café workspace first'
                        : 'Point earning, redemption, and expiry',
                    enabled: cafeId != null && cafeRole != null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LoyaltySettingsScreen(
                          cafeId: cafeId!,
                          role: cafeRole!,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const _MoreTile(
                    icon: Icons.print_rounded,
                    title: 'Printer settings',
                    subtitle:
                        'Connect a printer from a saved receipt after checkout',
                    enabled: false,
                  ),
                  const SizedBox(height: 6),
                  _MoreTile(
                    icon: Icons.storefront_rounded,
                    title: 'Café profile',
                    subtitle: 'Profile editing is not available in this build',
                    enabled: false,
                    onTap: () => _showInfo(
                      context,
                      'Café profile editing is not available in the current app.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MoreTile(
                    icon: Icons.palette_outlined,
                    title: 'App preferences',
                    subtitle: 'Emerald Café appearance',
                    onTap: () => _showInfo(
                      context,
                      'The current Emerald appearance is shared across the app. Theme preferences are not saved yet.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MoreTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & support',
                    subtitle: 'Get help using BrewVerse',
                    onTap: () => _showInfo(
                      context,
                      'For help, contact your café administrator. In-app support contact is not configured.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MoreTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About BrewVerse',
                    subtitle: 'Cafe Manager',
                    onTap: () => _showInfo(
                      context,
                      'BrewVerse Cafe Manager',
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: CafeBottomNavigation(
            selectedIndex: 4,
            onDestinationSelected: (index) => _selectTab(context, index),
          ),
        ),
      );

  void _selectTab(BuildContext context, int index) {
    selectCafeTab(
      context: context,
      currentIndex: 4,
      nextIndex: index,
      pageForIndex: (index) => cafeTabPage(
        index,
        cafeId: cafeId,
        cafeRole: cafeRole,
        cafeService: cafeService,
      ),
    );
  }

  void _showInfo(BuildContext context, String message) {
    showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('BrewVerse'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          dense: true,
          minVerticalPadding: 0,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.softOrange,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppTheme.orangeDeep, size: 21),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: enabled,
          onTap: enabled ? onTap : null,
        ),
      );
}
