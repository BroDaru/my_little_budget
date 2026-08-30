import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/ui/desktop/transactions/widgets/form_fields.dart';

void main() {
  testWidgets(
    'account search ranks matches first and keeps the other choices visible',
    (tester) async {
      final accounts = [
        _account(1, '은행'),
        _account(2, '네이버페이'),
        _account(3, '카드'),
      ];
      int? selectedId = 2;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AccountDropdown(
                hint: '자산',
                accounts: accounts,
                value: selectedId,
                onChanged: (value) => setState(() => selectedId = value),
              ),
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, '네이버');
      await tester.pumpAndSettle();

      expect(find.text('네이버페이'), findsOneWidget);
      expect(find.text('은행'), findsOneWidget);
      expect(find.text('카드'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('네이버페이')).dy,
        lessThan(tester.getTopLeft(find.text('은행')).dy),
      );

      await tester.tap(find.text('카드'));
      await tester.pumpAndSettle();

      expect(selectedId, 3);
      expect(tester.widget<TextField>(field).controller!.text, '카드');
    },
  );

  testWidgets(
    'clicking a selected category exposes every category without clearing it',
    (tester) async {
      final categories = [
        _category(1, '식비'),
        _category(2, '취미생활'),
        _category(3, '교통'),
      ];
      int? selectedId = 2;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CategoryDropdown(
                categories: categories,
                value: selectedId,
                onChanged: (value) => setState(() => selectedId = value),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('취미생활'), findsNWidgets(2));
      expect(find.text('식비'), findsOneWidget);
      expect(find.text('교통'), findsOneWidget);

      await tester.tap(find.text('식비'));
      await tester.pumpAndSettle();

      expect(selectedId, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '식비',
      );
    },
  );
}

Account _account(int id, String name) => Account(
  id: id,
  uuid: 'account-$id',
  name: name,
  kind: 'bank',
  initialBalance: 0,
  color: '#000000',
  excludeFromTotal: false,
  isInvestment: false,
  sortOrder: id,
  createdAt: '2026-08-24T00:00:00.000',
  updatedAt: '2026-08-24T00:00:00.000',
  syncStatus: 'synced',
);

Category _category(int id, String name) => Category(
  id: id,
  uuid: 'category-$id',
  name: name,
  type: 'expense',
  color: '#f97316',
  sortOrder: id,
  createdAt: '2026-08-24T00:00:00.000',
  updatedAt: '2026-08-24T00:00:00.000',
  syncStatus: 'synced',
);
