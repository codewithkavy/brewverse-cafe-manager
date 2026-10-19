import 'package:flutter/material.dart';

import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/analytics_screen.dart';
import 'package:brewverse_cafe_manager/screens/billing_screen.dart';
import 'package:brewverse_cafe_manager/screens/cafe_team_screen.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/screens/inventory_screen.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_screen.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_customer_details_screen.dart';
import 'package:brewverse_cafe_manager/screens/more_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/theme/app_theme.dart';

/// Local visual preview for the dashboard with an honest empty-data state.
/// This entrypoint does not initialize Firebase or connect to a backend.
void main() {
  runApp(const EmeraldDashboardPreviewApp());
}

class EmeraldDashboardPreviewApp extends StatelessWidget {
  const EmeraldDashboardPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BrewVerse Emerald UI Preview',
        theme: AppTheme.emeraldLight,
        debugShowCheckedModeBanner: false,
        home: _screen,
      );

  Widget get _screen {
    final service = _PreviewCafeService();
    return switch (Uri.base.queryParameters['screen']) {
      'billing' => BillingScreen(
          stockStream: service.watchStock(),
          cafeService: service,
        ),
      'inventory' => InventoryScreen(cafeService: service),
      'analytics' => AnalyticsScreen(cafeService: service),
      'loyalty' => LoyaltyScreen(cafeId: null, cafeService: service),
      'customer' => Builder(
          builder: (context) => LoyaltyCustomerDetailsScreen(
            customer: const {},
            phoneNumber: '',
            pointValueMinor: null,
            onStartBill: null,
            onBack: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) =>
                  LoyaltyScreen(cafeId: null, cafeService: service)),
            ),
          ),
        ),
      'more' => MoreScreen(cafeId: null, cafeService: service),
      'team' => CafeTeamScreen(
          cafeId: 'preview-cafe',
          callerRole: CafeRole.owner,
          currentUid: 'preview-owner',
          functionsService: CafeFunctionsService(
            invoker: (name, data) async {
              if (name == 'listCafeMemberships') {
                return {
                  'memberships': <Map<String, dynamic>>[],
                  'hasMore': false,
                  'nextPageToken': null,
                };
              }
              throw StateError('Team preview is read-only.');
            },
          ),
        ),
      'dashboard' => HomeScreen(
          stockStream: service.watchStock(),
          cafeService: service,
        ),
      _ => HomeScreen(
          stockStream: service.watchStock(),
          cafeService: service,
        ),
    };
  }
}

class _PreviewCafeService implements CafeService {
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const <StockItem>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
