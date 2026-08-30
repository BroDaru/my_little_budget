import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/features/transactions/validation.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> expenseCat([int idx = 0]) async =>
      (await db.categoriesDao.getActiveCategories('expense'))[idx].id;
  Future<int> firstAccount() async =>
      (await db.accountsDao.getActiveAccounts()).first.id;

  Future<void> addExpense(int accId, int catId, int amount, String on) {
    return db.transactionsDao.saveTransaction(
      draft: TransactionDraft(
        type: 'expense',
        amount: amount,
        occurredOn: on,
        occurredTime: '00:00',
        accountId: accId,
        categoryId: catId,
      ),
    );
  }

  group('카테고리 기반 예산 (SPEC §4.4)', () {
    test('고정 예산 vs 사용액·사용률', () async {
      final accId = await firstAccount();
      final catId = await expenseCat();
      await addExpense(accId, catId, 30000, '2025-05-03');
      await addExpense(accId, catId, 20000, '2025-05-20');

      await db.budgetDao.createBudgetGroup(
        name: '식비예산',
        month: '2025-05',
        amount: 100000,
        categoryIds: [catId],
      );

      final result = await db.budgetDao.budgetGroupVsActual('2025-05');
      expect(result.length, 1);
      expect(result.first.budgetAmount, 100000);
      expect(result.first.spentAmount, 50000);
      expect(result.first.usagePercent, 50);
    });

    test('거래 저장 후 예산 80% 도달과 초과를 경고한다', () async {
      final accId = await firstAccount();
      final catId = await expenseCat();
      await db.budgetDao.createBudgetGroup(
        name: '식비',
        month: '2025-05',
        amount: 100000,
        categoryIds: [catId],
      );

      final belowThreshold = TransactionDraft(
        type: 'expense',
        amount: 79999,
        occurredOn: '2025-05-03',
        occurredTime: '00:00',
        accountId: accId,
        categoryId: catId,
      );
      await db.transactionsDao.saveTransaction(draft: belowThreshold);
      expect(
        await db.budgetDao.budgetLimitWarningsFor(belowThreshold),
        isEmpty,
      );

      final reachesThreshold = TransactionDraft(
        type: 'expense',
        amount: 1,
        occurredOn: '2025-05-04',
        occurredTime: '00:00',
        accountId: accId,
        categoryId: catId,
      );
      await db.transactionsDao.saveTransaction(draft: reachesThreshold);
      final warning = (await db.budgetDao.budgetLimitWarningsFor(
        reachesThreshold,
      )).single;
      expect(warning.groupName, '식비');
      expect(warning.budgetAmount, 100000);
      expect(warning.spentAmount, 80000);
      expect(warning.remaining, 20000);
      expect(warning.exceeded, isFalse);

      final exceedsBudget = TransactionDraft(
        type: 'expense',
        amount: 25000,
        occurredOn: '2025-05-05',
        occurredTime: '00:00',
        accountId: accId,
        categoryId: catId,
      );
      await db.transactionsDao.saveTransaction(draft: exceedsBudget);
      final exceeded = (await db.budgetDao.budgetLimitWarningsFor(
        exceedsBudget,
      )).single;
      expect(exceeded.remaining, -5000);
      expect(exceeded.exceeded, isTrue);
    });

    test('% 모드: base = 예상소득 × % / 100', () async {
      await db.budgetDao.setMonthlyExpectedIncome('2025-05', 3000000);
      final catId = await expenseCat();
      await db.budgetDao.createBudgetGroup(
        name: '저축',
        month: '2025-05',
        amount: 0,
        categoryIds: [catId],
        percentage: 30,
      );

      final result = await db.budgetDao.budgetGroupVsActual('2025-05');
      expect(result.first.budgetAmount, 900000); // 3,000,000 × 30%
      expect(result.first.incomePercentage, 30);
      expect(result.first.expectedIncome, 3000000);
    });

    test(
      'category mappings can be added and removed for existing groups',
      () async {
        final accId = await firstAccount();
        final catA = await expenseCat(0);
        final catB = await expenseCat(1);
        await addExpense(accId, catA, 10000, '2025-05-03');
        await addExpense(accId, catB, 20000, '2025-05-04');

        final groupId = await db.budgetDao.createBudgetGroup(
          name: 'category-edit',
          month: '2025-05',
          amount: 100000,
          categoryIds: [catA],
        );
        expect(
          (await db.budgetDao.budgetGroupVsActual(
            '2025-05',
          )).single.spentAmount,
          10000,
        );

        await db.budgetDao.addCategoryToGroup(groupId, catB);
        expect(
          (await db.budgetDao.budgetGroupVsActual(
            '2025-05',
          )).single.spentAmount,
          30000,
        );

        await db.budgetDao.removeCategoryFromGroup(groupId, catA);
        final result = await db.budgetDao.budgetGroupVsActual('2025-05');
        expect(result.single.spentAmount, 20000);
        expect(result.single.categories.map((category) => category.id), [catB]);
      },
    );
  });

  group('이전 달 복사 + 이월 (SPEC §4.4)', () {
    test('carryForward 그룹은 잔금을 다음 달 조정액으로 이월', () async {
      final accId = await firstAccount();
      final catId = await expenseCat();
      // 4월: 예산 100000, 사용 70000 → 잔금 30000
      await db.budgetDao.createBudgetGroup(
        name: '식비',
        month: '2025-04',
        amount: 100000,
        categoryIds: [catId],
        carryForward: true,
      );
      await addExpense(accId, catId, 70000, '2025-04-10');

      final copied = await db.budgetDao.copyBudgetGroupsWithCarryforward(
        '2025-04',
        '2025-05',
      );
      expect(copied, 1);

      final may = await db.budgetDao.budgetGroupVsActual('2025-05');
      expect(may.first.baseAmount, 100000);
      expect(may.first.adjustment, 30000); // 이월된 잔금
      expect(may.first.budgetAmount, 130000); // base + adj
    });

    test('이미 같은 이름 그룹이 있으면 복사 건너뜀', () async {
      final catId = await expenseCat();
      await db.budgetDao.createBudgetGroup(
        name: '식비',
        month: '2025-04',
        amount: 100000,
        categoryIds: [catId],
      );
      await db.budgetDao.createBudgetGroup(
        name: '식비',
        month: '2025-05',
        amount: 50000,
        categoryIds: [catId],
      );
      final copied = await db.budgetDao.copyBudgetGroupsWithCarryforward(
        '2025-04',
        '2025-05',
      );
      expect(copied, 0);
    });
  });

  group('자산 연동 예산 (SPEC §4.4)', () {
    test('available = max(0, 월초잔액) + 월입금, spent = 월출금', () async {
      final accId = await firstAccount();
      final catId = await expenseCat();
      // 5월 지출 40000 (이 자산에서) → 월 출금 40000, 월초 잔액 0
      await addExpense(accId, catId, 40000, '2025-05-05');

      await db.budgetDao.createBudgetGroup(
        name: '생활비계좌',
        month: '2025-05',
        amount: 0,
        accountId: accId,
      );

      final result = await db.budgetDao.budgetGroupVsActual('2025-05');
      expect(result.first.accountId, accId);
      expect(result.first.spentAmount, 40000);
      expect(result.first.budgetAmount, 0); // 월초 0 + 입금 0
    });

    test('자산 연동 예산도 80% 도달 경고에 포함한다', () async {
      final accId = await firstAccount();
      final expenseCatId = await expenseCat();
      final incomeCatId = (await db.categoriesDao.getActiveCategories(
        'income',
      )).first.id;
      await db.transactionsDao.saveTransaction(
        draft: TransactionDraft(
          type: 'income',
          amount: 100000,
          occurredOn: '2025-05-01',
          occurredTime: '00:00',
          accountId: accId,
          categoryId: incomeCatId,
        ),
      );
      await db.budgetDao.createBudgetGroup(
        name: '생활비계좌',
        month: '2025-05',
        amount: 0,
        accountId: accId,
      );
      final expense = TransactionDraft(
        type: 'expense',
        amount: 80000,
        occurredOn: '2025-05-05',
        occurredTime: '00:00',
        accountId: accId,
        categoryId: expenseCatId,
      );
      await db.transactionsDao.saveTransaction(draft: expense);

      final warning = (await db.budgetDao.budgetLimitWarningsFor(
        expense,
      )).single;
      expect(warning.groupName, '생활비계좌');
      expect(warning.budgetAmount, 100000);
      expect(warning.spentAmount, 80000);
      expect(warning.remaining, 20000);
    });

    test('account-linked group account can be changed', () async {
      final accounts = await db.accountsDao.getActiveAccounts();
      final fromId = accounts[0].id;
      final toId = accounts[1].id;
      final catId = await expenseCat();

      await db.transactionsDao.saveTransaction(
        draft: TransactionDraft(
          type: 'income',
          amount: 50000,
          occurredOn: '2025-05-01',
          occurredTime: '00:00',
          accountId: toId,
          categoryId: catId,
        ),
      );

      final groupId = await db.budgetDao.createBudgetGroup(
        name: 'account-linked-edit',
        month: '2025-05',
        amount: 0,
        accountId: fromId,
      );

      await db.budgetDao.updateBudgetGroupAccount(groupId, toId);
      final result = await db.budgetDao.budgetGroupVsActual('2025-05');

      expect(result.single.accountId, toId);
      expect(result.single.budgetAmount, 50000);
    });
  });
}
