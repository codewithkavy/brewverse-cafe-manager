import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/widgets/cafe_tab_page_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreviewCafeService implements CafeService {
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('secondary tabs build with an injected preview service',
      (tester) async {
    final service = _PreviewCafeService();
    const titles = ['Inventory', 'Create Bill', 'Loyalty', 'More'];

    for (var index = 1; index <= 4; index++) {
      await tester.pumpWidget(MaterialApp(
        home: cafeTabPage(
          index,
          cafeId: null,
          cafeRole: null,
          cafeService: service,
        ),
      ));
      await tester.pump();

      expect(find.text(titles[index - 1]), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });
}
