import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/features/accounts/validation.dart';
import 'package:my_little_budget/features/transactions/validation.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> createAccount({
    required String name,
    required String kind,
    required int balance,
  }) async {
    await db.accountsDao.saveAccount(
      draft: AccountDraft(
        name: name,
        kind: kind,
        initialBalance: balance,
        color: '#000000',
        excludeFromTotal: false,
        isInvestment: false,
      ),
      currentBalance: balance,
    );
    return (await db.accountsDao.getActiveAccounts())
        .singleWhere((account) => account.name == name)
        .id;
  }

  Future<void> addTransaction({
    required String type,
    required int amount,
    required String occurredOn,
    required int accountId,
  }) async {
    final categoryId = (await db.categoriesDao.getActiveCategories(
      type,
    )).first.id;
    await db.transactionsDao.saveTransaction(
      draft: TransactionDraft(
        type: type,
        amount: amount,
        occurredOn: occurredOn,
        occurredTime: '12:00',
        accountId: accountId,
        categoryId: categoryId,
      ),
    );
  }

  Future<int> balanceAsOf(int accountId) async {
    final balances = await db.accountsDao.getAccountBalances(
      asOf: DateTime(2026, 8, 16),
    );
    return balances.singleWhere((row) => row.accountId == accountId).balance;
  }

  test('A: future bank expense does not reduce today balance', () async {
    final bankId = await createAccount(
      name: 'scenario-a-bank',
      kind: 'bank',
      balance: 1000000,
    );
    await addTransaction(
      type: 'expense',
      amount: 300000,
      occurredOn: '2026-08-20',
      accountId: bankId,
    );

    expect(await balanceAsOf(bankId), 1000000);
  });

  test('B: future bank income does not increase today balance', () async {
    final bankId = await createAccount(
      name: 'scenario-b-bank',
      kind: 'bank',
      balance: 1000000,
    );
    await addTransaction(
      type: 'income',
      amount: 500000,
      occurredOn: '2026-08-20',
      accountId: bankId,
    );

    expect(await balanceAsOf(bankId), 1000000);
  });

  test('cash accounts also exclude future transactions', () async {
    final cashId = await createAccount(
      name: 'date-policy-cash',
      kind: 'cash',
      balance: 1000000,
    );
    await addTransaction(
      type: 'income',
      amount: 500000,
      occurredOn: '2026-08-20',
      accountId: cashId,
    );

    expect(await balanceAsOf(cashId), 1000000);
  });

  test(
    'C/D: card includes this month future but excludes next month',
    () async {
      final cardId = await createAccount(
        name: 'scenario-cd-card',
        kind: 'card',
        balance: 0,
      );
      await addTransaction(
        type: 'expense',
        amount: 200000,
        occurredOn: '2026-08-10',
        accountId: cardId,
      );
      await addTransaction(
        type: 'expense',
        amount: 100000,
        occurredOn: '2026-08-20',
        accountId: cardId,
      );
      await addTransaction(
        type: 'expense',
        amount: 400000,
        occurredOn: '2026-09-01',
        accountId: cardId,
      );

      expect(await balanceAsOf(cardId), -300000);
    },
  );
}
