import 'package:flutter/material.dart';

import '../models/cafe_membership.dart';
import '../services/cafe_service.dart';
import '../screens/billing_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/loyalty_screen.dart';
import '../screens/more_screen.dart';

Widget cafeTabPage(
  int index, {
  required String? cafeId,
  required CafeRole? cafeRole,
  CafeService? cafeService,
}) =>
    switch (index) {
      1 => InventoryScreen(
          cafeId: cafeId,
          cafeRole: cafeRole,
          cafeService: cafeService,
          canManageInventory:
              cafeId == null || (cafeRole?.canManageInventory ?? false),
        ),
      2 => BillingScreen(
          cafeId: cafeId,
          cafeRole: cafeRole,
          cafeService: cafeService,
          stockStream: cafeService?.watchStock(),
        ),
      3 => LoyaltyScreen(
          cafeId: cafeId,
          cafeRole: cafeRole,
          cafeService: cafeService,
        ),
      4 => MoreScreen(
          cafeId: cafeId,
          cafeRole: cafeRole,
          cafeService: cafeService,
        ),
      _ => const SizedBox.shrink(),
    };
