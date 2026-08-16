import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:my_little_budget/app.dart';
import 'package:my_little_budget/core/date.dart';
import 'package:my_little_budget/core/money.dart';
import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/data/providers.dart';
import 'package:my_little_budget/features/accounts/validation.dart';
import 'package:my_little_budget/features/investments/validation.dart';
import 'package:my_little_budget/features/transactions/validation.dart';
import 'package:my_little_budget/ui/desktop/settings/data_management_screen.dart';
import 'package:my_little_budget/features/stats/providers.dart';

void main() {
  Future<AppDatabase> pumpAppAt(WidgetTester tester, String route) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('my_little_budget'));
    GoRouter.of(context).go(route);
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('Budget MVP renders group modes and refreshes expected income', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedBudget(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('my_little_budget'))).go('/budget');
    await tester.pumpAndSettle();

    expect(find.text('Food Fixed'), findsOneWidget);
    expect(find.text('Needs Percent'), findsOneWidget);
    expect(find.text('Cash Flow'), findsOneWidget);
    expect(find.text(formatKRW(3000000)), findsWidgets);
    expect(find.text(formatKRW(600000)), findsWidgets);
    expect(find.text(formatKRW(1500000)), findsWidgets);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3500000');
    await tester.tap(find.widgetWithText(FilledButton, '저장').last);
    await tester.pumpAndSettle();

    expect(find.text(formatKRW(3500000)), findsWidgets);
    expect(find.text(formatKRW(700000)), findsWidgets);
  });

  testWidgets(
    'Investments MVP renders rows, inline forms, precision, and PnL',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedInvestments(db);

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.text('my_little_budget')),
      ).go('/investments');
      await tester.pumpAndSettle();

      expect(find.text('BUY'), findsWidgets);
      expect(find.text('SELL'), findsWidgets);
      expect(find.text('DIVIDEND'), findsWidgets);
      expect(find.text('0.3333'), findsOneWidget);
      expect(find.text('0.1111'), findsWidgets);
      expect(find.text('0.2222'), findsOneWidget);
      expect(find.text(formatKRW(15000)), findsWidgets);
      expect(find.text(formatKRW(500)), findsWidgets);

      final ticker = find.text('ABCD').first;
      await tester.ensureVisible(ticker);
      await tester.tap(ticker);
      await tester.pumpAndSettle();

      expect(find.textContaining('0.2222'), findsAtLeastNWidgets(2));
      expect(find.byIcon(Icons.north_east), findsWidgets);
      expect(find.byIcon(Icons.payments_outlined), findsWidgets);
      final inlineSellTotal = find.byKey(
        const ValueKey('holding-sell-total-amount-field'),
      );
      expect(inlineSellTotal, findsOneWidget);
      expect(
        tester.widget<TextField>(inlineSellTotal).decoration?.labelText,
        '매도 총액',
      );
    },
  );

  testWidgets(
    'Desktop investment buy and sell use quantity with direct total amount',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final seeded = await _seedInvestments(db);

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.text('my_little_budget')),
      ).go('/investments');
      await tester.pumpAndSettle();

      await _openInvestmentEdit(tester, seeded.buyId);
      expect(
        find.byKey(const ValueKey('investment-unit-price-field')),
        findsNothing,
      );
      final buyTotal = find.byKey(
        const ValueKey('investment-total-amount-field'),
      );
      expect(buyTotal, findsOneWidget);
      expect(tester.widget<TextField>(buyTotal).controller?.text, '30000');
      expect(tester.widget<TextField>(buyTotal).decoration?.labelText, '구매 총액');
      await tester.tap(find.byKey(const ValueKey('investment-save-button')));
      await tester.pumpAndSettle();
      expect(
        (await db.investmentsDao.getInvestmentById(seeded.buyId))?.totalAmount,
        30000,
      );

      await _openInvestmentEdit(tester, seeded.sellId);
      final sellTotal = find.byKey(
        const ValueKey('investment-total-amount-field'),
      );
      expect(sellTotal, findsOneWidget);
      expect(tester.widget<TextField>(sellTotal).controller?.text, '15000');
      expect(
        tester.widget<TextField>(sellTotal).decoration?.labelText,
        '매도 총액',
      );
    },
  );

  testWidgets('Desktop holding actions include prefilled add buy', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedInvestments(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/investments');
    await tester.pumpAndSettle();

    final ticker = find.text('ABCD').first;
    await tester.ensureVisible(ticker);
    await tester.tap(ticker);
    await tester.pumpAndSettle();

    final addBuy = find.byKey(const ValueKey('holding-add-buy-ABCD'));
    expect(addBuy, findsOneWidget);
    await tester.tap(addBuy);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('investment-dialog')), findsOneWidget);
    final tickerField = find.byKey(const ValueKey('investment-name-field'));
    expect(tester.widget<TextField>(tickerField).controller?.text, 'ABCD');
    expect(tester.widget<TextField>(tickerField).enabled, isFalse);
    expect(
      find.byKey(const ValueKey('investment-total-amount-field')),
      findsOneWidget,
    );
  });

  testWidgets('Desktop investments switches from monthly to yearly data', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedInvestments(db);
    final now = DateTime.now();
    final otherMonth = now.month == 1 ? 2 : 1;
    final yearlyId = await db.investmentsDao.saveInvestment(
      draft: InvestmentDraft(
        side: 'buy',
        occurredOn: '${now.year}-${otherMonth.toString().padLeft(2, '0')}-15',
        occurredTime: '12:00',
        ticker: 'YEARLY',
        quantity: 1,
        totalAmount: 10000,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/investments');
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('investment-edit-$yearlyId')), findsNothing);
    expect(find.text('월간 투자 거래'), findsOneWidget);

    await tester.tap(find.text('연'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('investment-edit-$yearlyId')), findsOneWidget);
    expect(find.text('연간 투자 거래'), findsOneWidget);
    expect(find.text('연간 실현손익'), findsOneWidget);
  });

  testWidgets('Stats monthly category detail panel renders transactions', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final seeded = await _seedStats(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('my_little_budget'))).go('/stats');
    await tester.pumpAndSettle();

    await tester.tap(find.text(seeded.categoryName).first);
    await tester.pumpAndSettle();

    expect(find.text('카테고리별'), findsOneWidget);
    expect(find.text('태그별'), findsOneWidget);
    expect(find.text('Stats lunch'), findsWidgets);
    expect(find.text(seeded.accountName), findsWidgets);
    expect(find.text('#stats-tag'), findsWidgets);
    expect(find.text(formatKRW(12345)), findsWidgets);
    expect(find.text('Previous month stats lunch'), findsNothing);

    await tester.tap(find.byTooltip('상세 닫기'));
    await tester.pumpAndSettle();

    expect(find.text('Stats lunch'), findsNothing);
  });

  testWidgets('Stats yearly renders tables, categories, and empty states', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final seeded = await _seedYearlyStats(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/stats/yearly');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('yearly-stats-year-dropdown')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('yearly-monthly-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('yearly-category-list')), findsOneWidget);
    expect(find.text(formatKRW(1200000)), findsWidgets);
    expect(find.text(formatKRW(345000)), findsWidgets);
    expect(find.text(formatKRW(855000)), findsWidgets);
    expect(find.text(seeded.expenseCategoryName), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.text('my_little_budget')),
    );
    container.read(statsYearProvider.notifier).state = seeded.emptyYear;
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yearly-monthly-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('yearly-category-empty')), findsOneWidget);
  });

  testWidgets('Transactions search debounces and can be cleared', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedTransactionSearch(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/transactions');
    await tester.pumpAndSettle();

    await tester.tap(find.text('검색·필터').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transactions-search-field')),
      'Alpha',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alpha memo target'), findsOneWidget);
    expect(find.textContaining('Beta memo hidden'), findsNothing);
    expect(find.textContaining('검색 중'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transactions-search-clear')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alpha memo target'), findsOneWidget);
    expect(find.textContaining('Beta memo hidden'), findsOneWidget);
  });

  testWidgets('Investments ticker filter keeps state and shows empty result', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedInvestments(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/investments');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('investment-ticker-filter')),
      'NOPE',
    );
    await tester.pumpAndSettle();

    expect(find.text('필터 결과가 없습니다.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'NOPE'), findsOneWidget);
  });

  testWidgets('Investments edit dialogs prefill, save, and delete refreshes', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final seeded = await _seedInvestments(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/investments');
    await tester.pumpAndSettle();

    await _openInvestmentEdit(tester, seeded.buyId);
    expect(find.text('BUY'), findsWidgets);
    expect(find.widgetWithText(TextField, 'ABCD'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0.3333'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('investment-cancel-button')));
    await tester.pumpAndSettle();

    await _openInvestmentEdit(tester, seeded.sellId);
    expect(find.text('SELL'), findsWidgets);
    expect(find.widgetWithText(TextField, '0.1111'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('investment-cancel-button')));
    await tester.pumpAndSettle();

    await _openInvestmentEdit(tester, seeded.dividendId);
    expect(find.text('DIVIDEND'), findsWidgets);
    expect(find.widgetWithText(TextField, '500'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('investment-total-amount-field')),
      '700',
    );
    await tester.tap(find.byKey(const ValueKey('investment-save-button')));
    await tester.pumpAndSettle();

    expect(find.text(formatKRW(700)), findsWidgets);

    await tester.tap(
      find.byKey(ValueKey('investment-delete-${seeded.sellId}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('investment-delete-confirm-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('investment-delete-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('investment-delete-${seeded.sellId}')),
      findsNothing,
    );
    expect(find.text(formatKRW(15000)), findsNothing);
    expect(find.text(formatKRW(700)), findsWidgets);
  });

  testWidgets('Account detail filters transactions by category and tag', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final seeded = await _seedAccountDetailFilters(db);

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/accounts/${seeded.accountId}');
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('account-category-filter-${seeded.categoryId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('account-tag-filter-${seeded.tagId}')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Account filter target'), findsOneWidget);
    expect(find.textContaining('Account filter other'), findsNothing);
  });

  testWidgets(
    'Accounts archive, restore, delete guard, and virtual row filter',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final seeded = await _seedAccountEdgeCases(db);

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.text('my_little_budget')),
      ).go('/accounts');
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Archive Candidate')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('account-edit-${seeded.archiveId}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-archive-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('account-archive-confirm-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('account-archive-confirm-button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('보관된').first);
      await tester.pumpAndSettle();

      expect(find.text('Archive Candidate'), findsOneWidget);
      expect(
        find.byKey(ValueKey('account-restore-${seeded.archiveId}')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(ValueKey('account-restore-${seeded.archiveId}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('account-restore-${seeded.archiveId}')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(ValueKey('account-delete-${seeded.guardedId}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('account-delete-confirm-dialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('account-delete-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Guarded Archive'), findsOneWidget);

      GoRouter.of(
        tester.element(find.text('my_little_budget')),
      ).go('/accounts/${seeded.investmentAccountId}');
      await tester.pumpAndSettle();

      expect(find.text('VIRT'), findsWidgets);
      expect(find.textContaining('Virtual filter normal'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('account-category-filter-${seeded.categoryId}')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Virtual filter normal'), findsOneWidget);
      expect(find.text('VIRT'), findsNothing);
    },
  );

  testWidgets('Settings MVP renders theme and backup surfaces', (tester) async {
    await pumpAppAt(tester, '/settings/theme');

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    GoRouter.of(
      tester.element(find.text('my_little_budget')),
    ).go('/settings/backup');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-backup-export-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-backup-import-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-data-reset-button')),
      findsOneWidget,
    );
    await tester.tap(find.text('자동 동기화'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-supabase-url-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-save-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-test-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-upload-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-restore-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-status-panel')),
      findsOneWidget,
    );
    expect(find.text('데이터 백업 / 복원'), findsOneWidget);
  });

  testWidgets('Settings backup import confirmation warns full replacement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showImportConfirmationDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('백업 데이터 복원'), findsOneWidget);
    expect(
      find.text('현재 데이터를 모두 덮어쓰고 백업 데이터를 복원합니다. 되돌릴 수 없습니다.'),
      findsOneWidget,
    );
    expect(find.text('복원'), findsOneWidget);
  });

  testWidgets('Settings reset confirmation warns destructive reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showResetConfirmationDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('데이터 초기화'), findsOneWidget);
    expect(
      find.text('현재 데이터를 모두 삭제하고 기본 자산과 카테고리를 복구합니다. 되돌릴 수 없습니다.'),
      findsOneWidget,
    );
    expect(find.text('초기화'), findsOneWidget);
  });
}

Future<({String categoryName, String accountName})> _seedStats(
  AppDatabase db,
) async {
  final month = currentMonthKey();
  final day = '$month-01';
  final previousMonth = shiftMonth(month, -1);
  final account = (await db.accountsDao.getActiveAccounts()).first;
  final category = (await db.categoriesDao.getActiveCategories(
    'expense',
  )).first;

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 12345,
      occurredOn: day,
      occurredTime: '12:30',
      accountId: account.id,
      categoryId: category.id,
      memo: 'Stats lunch',
    ),
    tagNames: const ['stats-tag'],
  );

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 99999,
      occurredOn: '$previousMonth-01',
      occurredTime: '12:30',
      accountId: account.id,
      categoryId: category.id,
      memo: 'Previous month stats lunch',
    ),
  );

  return (categoryName: category.name, accountName: account.name);
}

Future<({String expenseCategoryName, int emptyYear})> _seedYearlyStats(
  AppDatabase db,
) async {
  final year = DateTime.now().year;
  final account = (await db.accountsDao.getActiveAccounts()).first;
  final incomeCategory = (await db.categoriesDao.getActiveCategories(
    'income',
  )).first;
  final expenseCategory = (await db.categoriesDao.getActiveCategories(
    'expense',
  )).first;

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'income',
      amount: 1200000,
      occurredOn: '$year-03-01',
      occurredTime: '09:00',
      accountId: account.id,
      categoryId: incomeCategory.id,
      memo: 'Yearly income',
    ),
  );
  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 345000,
      occurredOn: '$year-03-02',
      occurredTime: '10:00',
      accountId: account.id,
      categoryId: expenseCategory.id,
      memo: 'Yearly expense',
    ),
  );

  return (expenseCategoryName: expenseCategory.name, emptyYear: year - 1);
}

Future<void> _seedTransactionSearch(AppDatabase db) async {
  final month = currentMonthKey();
  final account = (await db.accountsDao.getActiveAccounts()).first;
  final category = (await db.categoriesDao.getActiveCategories(
    'expense',
  )).first;

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 1111,
      occurredOn: '$month-01',
      occurredTime: '09:00',
      accountId: account.id,
      categoryId: category.id,
      memo: 'Alpha memo target',
    ),
  );
  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 2222,
      occurredOn: '$month-02',
      occurredTime: '10:00',
      accountId: account.id,
      categoryId: category.id,
      memo: 'Beta memo hidden',
    ),
  );
}

Future<
  ({int archiveId, int guardedId, int investmentAccountId, int categoryId})
>
_seedAccountEdgeCases(AppDatabase db) async {
  final month = currentMonthKey();
  final expenseCategory = (await db.categoriesDao.getActiveCategories(
    'expense',
  )).first;

  await db.accountsDao.saveAccount(
    draft: const AccountDraft(
      name: 'Archive Candidate',
      kind: 'bank',
      initialBalance: 0,
      color: '#64748b',
      excludeFromTotal: false,
      isInvestment: false,
    ),
    currentBalance: 1000,
  );
  await db.accountsDao.saveAccount(
    draft: const AccountDraft(
      name: 'Guarded Archive',
      kind: 'bank',
      initialBalance: 0,
      color: '#64748b',
      excludeFromTotal: false,
      isInvestment: false,
    ),
    currentBalance: 1000,
  );
  await db.accountsDao.saveAccount(
    draft: const AccountDraft(
      name: 'Virtual Invest Account',
      kind: 'bank',
      initialBalance: 0,
      color: '#64748b',
      excludeFromTotal: false,
      isInvestment: true,
    ),
    currentBalance: 1000,
  );

  final accounts = await db.accountsDao.getActiveAccounts();
  final archiveId = accounts
      .firstWhere((account) => account.name == 'Archive Candidate')
      .id;
  final guardedId = accounts
      .firstWhere((account) => account.name == 'Guarded Archive')
      .id;
  final investmentAccountId = accounts
      .firstWhere((account) => account.name == 'Virtual Invest Account')
      .id;

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 1234,
      occurredOn: '$month-01',
      occurredTime: '09:00',
      accountId: guardedId,
      categoryId: expenseCategory.id,
      memo: 'Guarded usage',
    ),
  );
  await db.accountsDao.archiveAccount(guardedId);

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 2345,
      occurredOn: '$month-02',
      occurredTime: '10:00',
      accountId: investmentAccountId,
      categoryId: expenseCategory.id,
      memo: 'Virtual filter normal',
    ),
  );
  await db.investmentsDao.saveInvestment(
    draft: InvestmentDraft(
      side: 'buy',
      occurredOn: '$month-03',
      occurredTime: '11:00',
      ticker: 'VIRT',
      quantity: 1,
      totalAmount: 10000,
    ),
  );

  return (
    archiveId: archiveId,
    guardedId: guardedId,
    investmentAccountId: investmentAccountId,
    categoryId: expenseCategory.id,
  );
}

Future<({int accountId, int categoryId, int tagId})> _seedAccountDetailFilters(
  AppDatabase db,
) async {
  final month = currentMonthKey();
  final account = (await db.accountsDao.getActiveAccounts()).first;
  final categories = await db.categoriesDao.getActiveCategories('expense');

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 3333,
      occurredOn: '$month-01',
      occurredTime: '09:00',
      accountId: account.id,
      categoryId: categories[0].id,
      memo: 'Account filter target',
    ),
    tagNames: const ['account-filter-tag'],
  );
  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 4444,
      occurredOn: '$month-02',
      occurredTime: '10:00',
      accountId: account.id,
      categoryId: categories[1].id,
      memo: 'Account filter other',
    ),
    tagNames: const ['account-other-tag'],
  );

  final tag = (await db.tagsDao.getTags()).firstWhere(
    (tag) => tag.name == 'account-filter-tag',
  );
  return (accountId: account.id, categoryId: categories[0].id, tagId: tag.id);
}

Future<void> _seedBudget(AppDatabase db) async {
  final month = currentMonthKey();
  final day = '$month-01';
  final accounts = await db.accountsDao.getActiveAccounts();
  final accountId = accounts.first.id;
  final categories = await db.categoriesDao.getActiveCategories('expense');

  await db.budgetDao.setMonthlyExpectedIncome(month, 3000000);
  await db.budgetDao.createBudgetGroup(
    name: 'Food Fixed',
    month: month,
    amount: 600000,
    categoryIds: [categories[0].id],
  );
  await db.budgetDao.createBudgetGroup(
    name: 'Needs Percent',
    month: month,
    amount: 0,
    percentage: 20,
    categoryIds: [categories[1].id],
  );
  await db.budgetDao.createBudgetGroup(
    name: 'Cash Flow',
    month: month,
    amount: 0,
    accountId: accountId,
  );

  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'income',
      amount: 1500000,
      occurredOn: day,
      occurredTime: '09:00',
      accountId: accountId,
      categoryId: (await db.categoriesDao.getActiveCategories(
        'income',
      )).first.id,
    ),
  );
  await db.transactionsDao.saveTransaction(
    draft: TransactionDraft(
      type: 'expense',
      amount: 100000,
      occurredOn: day,
      occurredTime: '10:00',
      accountId: accountId,
      categoryId: categories[0].id,
    ),
  );
}

Future<({int buyId, int sellId, int dividendId})> _seedInvestments(
  AppDatabase db,
) async {
  final month = currentMonthKey();
  final day = '$month-01';
  await db.accountsDao.saveAccount(
    draft: const AccountDraft(
      name: 'Invest Test',
      kind: 'bank',
      initialBalance: 0,
      color: '#64748b',
      excludeFromTotal: false,
      isInvestment: true,
    ),
    currentBalance: 0,
  );

  final buyId = await db.investmentsDao.saveInvestment(
    draft: InvestmentDraft(
      side: 'buy',
      occurredOn: day,
      occurredTime: '09:00',
      ticker: 'ABCD',
      quantity: 0.3333,
      totalAmount: 30000,
    ),
  );
  final sellId = await db.investmentsDao.saveInvestment(
    draft: InvestmentDraft(
      side: 'sell',
      occurredOn: day,
      occurredTime: '10:00',
      ticker: 'ABCD',
      quantity: 0.1111,
      totalAmount: 15000,
    ),
  );
  final dividendId = await db.investmentsDao.saveInvestment(
    draft: InvestmentDraft(
      side: 'dividend',
      occurredOn: day,
      occurredTime: '11:00',
      ticker: 'ABCD',
      quantity: 0,
      totalAmount: 500,
    ),
  );

  return (buyId: buyId, sellId: sellId, dividendId: dividendId);
}

Future<void> _openInvestmentEdit(WidgetTester tester, int id) async {
  final button = find.byKey(ValueKey('investment-edit-$id'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('investment-dialog')), findsOneWidget);
}
