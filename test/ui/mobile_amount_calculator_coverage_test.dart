import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/data/providers.dart';
import 'package:my_little_budget/features/recurring/validation.dart';
import 'package:my_little_budget/ui/mobile/investments/mobile_investments_screen.dart';
import 'package:my_little_budget/ui/mobile/settings/mobile_recurring_screen.dart';

void main() {
  testWidgets('recurring transaction amount opens the arithmetic calculator', (
    tester,
  ) async {
    final db = await _pumpScreen(
      tester,
      const MobileRecurringScreen(),
      prepare: (db) async {
        final account = (await db.accountsDao.getActiveAccounts()).first;
        final category = (await db.categoriesDao.getActiveCategories(
          'expense',
        )).first;
        await db.recurringDao.saveRecurring(
          draft: RecurringDraft(
            name: 'calculator recurring',
            type: 'expense',
            amount: 1000,
            frequency: 'monthly',
            occurredTime: '09:00',
            startDate: '2026-08-24',
            dayOfMonth: 24,
            accountId: account.id,
            categoryId: category.id,
          ),
        );
      },
    );
    addTearDown(db.close);

    await tester.tap(find.text('calculator recurring'));
    await tester.pumpAndSettle();

    final amountField = _amountField();
    expect(amountField, findsOneWidget);
    await tester.tap(amountField);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-amount-calculator-page')),
      findsOneWidget,
    );
    await _calculate(tester);
    expect(tester.widget<TextField>(_amountField()).controller?.text, '7000');
  });

  testWidgets('investment amount opens the arithmetic calculator', (
    tester,
  ) async {
    final db = await _pumpScreen(tester, const MobileInvestmentsScreen());
    addTearDown(db.close);

    await tester.tap(find.byTooltip('매수 추가'));
    await tester.pumpAndSettle();

    final amountField = _amountField();
    expect(amountField, findsOneWidget);
    await tester.tap(amountField);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-amount-calculator-page')),
      findsOneWidget,
    );
    await _calculate(tester);
    expect(tester.widget<TextField>(_amountField()).controller?.text, '7000');
  });
}

Finder _amountField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == '금액',
  description: 'amount TextField',
);

Future<void> _calculate(WidgetTester tester) async {
  for (final label in ['C', '1', '0', '00', '+', '2', '0', '00', '×', '3']) {
    await tester.tap(find.byKey(ValueKey('mobile-transaction-keypad-$label')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('mobile-transaction-keypad-=')));
  await tester.pumpAndSettle();
}

Future<AppDatabase> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Future<void> Function(AppDatabase db)? prepare,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await prepare?.call(db);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
