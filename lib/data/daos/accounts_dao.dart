import 'package:drift/drift.dart';

import '../../core/date.dart';
import '../../features/accounts/validation.dart';
import '../../features/investments/cost_basis.dart';
import '../database.dart';
import '../investment_mapping.dart';
import '../sync_metadata.dart';
import '../tables/accounts.dart';
import '../tables/budget_groups.dart';
import '../tables/investments.dart';
import '../tables/recurring_transactions.dart';
import '../tables/transactions.dart';

part 'accounts_dao.g.dart';

/// SPEC §3.1 / §3.9 / §4.2 — 자산 조회·잔액 계산·CRUD.

/// 자산 + 계산된 현재 잔액. = Tauri AccountBalance.
class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.name,
    required this.kind,
    required this.color,
    required this.initialBalance,
    required this.cardLimit,
    required this.excludeFromTotal,
    required this.isInvestment,
    required this.balance,
  });

  final int accountId;
  final String name;
  final String kind;
  final String color;
  final int initialBalance;
  final int? cardLimit;
  final bool excludeFromTotal;
  final bool isInvestment;
  final int balance;
}

@DriftAccessor(
  tables: [
    Accounts,
    Transactions,
    Investments,
    BudgetGroups,
    RecurringTransactions,
  ],
)
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  /// 활성 자산 (보관 제외). sortOrder, id 순.
  Future<List<Account>> getActiveAccounts() {
    return (select(accounts)
          ..where((a) => a.archivedAt.isNull())
          ..orderBy([
            (a) => OrderingTerm(expression: a.sortOrder),
            (a) => OrderingTerm(expression: a.id),
          ]))
        .get();
  }

  Stream<List<Account>> watchActiveAccounts() {
    return (select(accounts)
          ..where((a) => a.archivedAt.isNull())
          ..orderBy([
            (a) => OrderingTerm(expression: a.sortOrder),
            (a) => OrderingTerm(expression: a.id),
          ]))
        .watch();
  }

  /// 보관된 자산. archivedAt 순.
  Future<List<Account>> getArchivedAccounts() {
    return (select(accounts)
          ..where((a) => a.archivedAt.isNotNull())
          ..orderBy([(a) => OrderingTerm(expression: a.archivedAt)]))
        .get();
  }

  /// 활성 자산 + 자산 현황 잔액 (거래 합산 SQL + 투자 손익). SPEC §3.9.
  ///
  /// 현금/은행은 [asOf] 당일까지, 카드는 [asOf]가 속한 달의 말일까지
  /// 입력된 거래를 반영한다. 그 외 계좌 유형은 기존처럼 날짜 제한이 없다.
  Future<List<AccountBalance>> getAccountBalances({DateTime? asOf}) async {
    final localAsOf = asOf ?? DateTime.now();
    final today = toDateKey(localAsOf);
    final currentMonthEnd = monthRange(toMonthKey(localAsOf)).end;
    final rows = await customSelect(
      '''
      WITH active_accounts AS (
        SELECT
          a.*,
          CASE
            WHEN a.kind = 'card' THEN ?
            WHEN a.kind IN ('cash', 'bank') THEN ?
            ELSE NULL
          END AS balance_cutoff
        FROM accounts a
        WHERE a.archived_at IS NULL
      )
      SELECT
        a.id AS id, a.name AS name, a.kind AS kind, a.color AS color,
        a.initial_balance AS initial_balance,
        a.card_limit AS card_limit,
        a.exclude_from_total AS exclude_from_total,
        a.is_investment AS is_investment,
        a.initial_balance
        + COALESCE((SELECT SUM(amount) FROM transactions WHERE type = 'income'     AND account_id      = a.id AND (a.balance_cutoff IS NULL OR occurred_on <= a.balance_cutoff)), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions WHERE type = 'expense'    AND account_id      = a.id AND (a.balance_cutoff IS NULL OR occurred_on <= a.balance_cutoff)), 0)
        + COALESCE((SELECT SUM(amount) FROM transactions WHERE type = 'transfer'   AND to_account_id   = a.id AND (a.balance_cutoff IS NULL OR occurred_on <= a.balance_cutoff)), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions WHERE type = 'transfer'   AND from_account_id = a.id AND (a.balance_cutoff IS NULL OR occurred_on <= a.balance_cutoff)), 0)
        + COALESCE((SELECT SUM(amount) FROM transactions WHERE type = 'adjustment' AND account_id      = a.id AND (a.balance_cutoff IS NULL OR occurred_on <= a.balance_cutoff)), 0)
        AS balance
      FROM active_accounts a
      ORDER BY a.sort_order, a.id
      ''',
      variables: [Variable<String>(currentMonthEnd), Variable<String>(today)],
      readsFrom: {accounts, transactions},
    ).get();

    final impact = await _investmentImpactByAccount();

    return rows.map((r) {
      final id = r.read<int>('id');
      return AccountBalance(
        accountId: id,
        name: r.read<String>('name'),
        kind: r.read<String>('kind'),
        color: r.read<String>('color'),
        initialBalance: r.read<int>('initial_balance'),
        cardLimit: r.readNullable<int>('card_limit'),
        excludeFromTotal: r.read<int>('exclude_from_total') != 0,
        isInvestment: r.read<int>('is_investment') != 0,
        balance: r.read<int>('balance') + (impact[id] ?? 0),
      );
    }).toList();
  }

  Future<AccountBalance?> getAccountBalance(int id) async {
    for (final b in await getAccountBalances()) {
      if (b.accountId == id) return b;
    }
    return null;
  }

  /// 투자 손익을 자산별로 합산. 전체 투자기록을 한 번만 walk. SPEC §3.10.
  Future<Map<int, int>> _investmentImpactByAccount() async {
    final all = await select(investments).get();
    final events = computeInvestmentEvents(all.map(toInvestmentEntry).toList());
    final map = <int, int>{};
    for (final e in events) {
      final aid = e.accountId;
      if (aid != null) map[aid] = (map[aid] ?? 0) + e.balanceImpact;
    }
    return map;
  }

  /// 자산이 다른 기록에서 참조되는 총 횟수. 0 이면 hard delete 가능. SPEC §4.2.
  Future<int> getAccountUsageCount(int id) async {
    final row = await customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM transactions
           WHERE account_id = ? OR from_account_id = ? OR to_account_id = ?)
        + (SELECT COUNT(*) FROM investments WHERE account_id = ?)
        + (SELECT COUNT(*) FROM budget_groups WHERE account_id = ?)
        + (SELECT COUNT(*) FROM recurring_transactions
           WHERE account_id = ? OR from_account_id = ? OR to_account_id = ?)
        AS n
      ''',
      variables: List.filled(8, Variable<int>(id)),
      readsFrom: {
        transactions,
        investments,
        budgetGroups,
        recurringTransactions,
      },
    ).getSingle();
    return row.read<int>('n');
  }

  /// 자산 저장. SPEC §4.2.
  ///   신규: currentBalance 가 initial_balance 로 저장.
  ///   편집: initial_balance 불변. 잔액 차이는 adjustment 거래로 기록.
  ///   isInvestment=true 면 다른 모든 자산을 false 로 강제 (단일 투자 자산).
  Future<void> saveAccount({
    int? id,
    required AccountDraft draft,
    required int currentBalance,
  }) async {
    await transaction(() async {
      if (draft.isInvestment) {
        final clearOthers = update(accounts);
        if (id != null) clearOthers.where((a) => a.id.isNotValue(id));
        await clearOthers.write(
          AccountsCompanion(
            isInvestment: const Value(false),
            updatedAt: Value(sqlNow()),
            syncStatus: const Value(syncStatusPending),
          ),
        );
      }

      if (id != null) {
        final before = await getAccountBalance(id);
        final delta = currentBalance - (before?.balance ?? 0);

        await (update(accounts)..where((a) => a.id.equals(id))).write(
          AccountsCompanion(
            name: Value(draft.name),
            kind: Value(draft.kind),
            cardLimit: Value(draft.cardLimit),
            color: Value(draft.color),
            excludeFromTotal: Value(draft.excludeFromTotal),
            isInvestment: Value(draft.isInvestment),
            updatedAt: Value(sqlNow()),
            syncStatus: const Value(syncStatusPending),
            // initialBalance 는 의도적으로 건드리지 않음.
          ),
        );

        if (delta != 0) {
          await into(transactions).insert(
            TransactionsCompanion.insert(
              type: 'adjustment',
              occurredOn: currentDateKey(),
              occurredTime: Value(nowTime()),
              amount: delta,
              accountId: Value(id),
              memo: const Value('잔액 조정'),
            ),
          );
        }
      } else {
        await into(accounts).insert(
          AccountsCompanion.insert(
            name: draft.name,
            kind: draft.kind,
            initialBalance: Value(currentBalance),
            cardLimit: Value(draft.cardLimit),
            color: Value(draft.color),
            excludeFromTotal: Value(draft.excludeFromTotal),
            isInvestment: Value(draft.isInvestment),
          ),
        );
      }
    });
  }

  Future<void> archiveAccount(int id) async {
    await customUpdate(
      "UPDATE accounts SET archived_at = datetime('now'), updated_at = datetime('now'), sync_status = '$syncStatusPending' WHERE id = ?",
      variables: [Variable<int>(id)],
      updates: {accounts},
    );
  }

  Future<void> restoreAccount(int id) async {
    await (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        archivedAt: const Value(null),
        updatedAt: Value(sqlNow()),
        syncStatus: const Value(syncStatusPending),
      ),
    );
  }

  /// 참조 0건일 때만 영구 삭제. 사용 중이면 에러 메시지 반환, 성공 시 null. SPEC §4.2.
  Future<String?> deleteAccount(int id) async {
    final usage = await getAccountUsageCount(id);
    if (usage > 0) {
      return '이 자산은 $usage건의 기록에 사용 중이라 삭제할 수 없습니다. '
          '먼저 해당 기록을 정리해주세요.';
    }
    await (delete(accounts)..where((a) => a.id.equals(id))).go();
    return null;
  }

  Future<void> updateAccountOrder(List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(
          accounts,
        )..where((a) => a.id.equals(orderedIds[i]))).write(
          AccountsCompanion(
            sortOrder: Value(i),
            updatedAt: Value(sqlNow()),
            syncStatus: const Value(syncStatusPending),
          ),
        );
      }
    });
  }
}
