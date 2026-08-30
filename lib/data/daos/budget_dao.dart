import 'package:drift/drift.dart';

import '../../core/date.dart';
import '../../core/validation.dart';
import '../../features/budget/logic.dart';
import '../../features/transactions/validation.dart';
import '../database.dart';
import '../sync_metadata.dart';
import '../tables/accounts.dart';
import '../tables/budget_groups.dart';
import '../tables/categories.dart';
import '../tables/monthly_income.dart';
import '../tables/transactions.dart';

part 'budget_dao.g.dart';

/// SPEC §3.4 / §4.4 — 예산 그룹 조회·계산·CRUD.

class CategoryRef {
  const CategoryRef({
    required this.id,
    required this.name,
    required this.color,
  });
  final int id;
  final String name;
  final String color;
}

class BudgetGroupRow {
  const BudgetGroupRow({
    required this.id,
    required this.name,
    required this.month,
    required this.amount,
    required this.adjustment,
    required this.carryForward,
    required this.accountId,
    required this.accountName,
    required this.accountColor,
    required this.percentage,
    required this.categories,
  });
  final int id;
  final String name;
  final String month;
  final int amount;
  final int adjustment;
  final bool carryForward;
  final int? accountId;
  final String? accountName;
  final String? accountColor;
  final int? percentage; // % 모드 비율. null=고정금액
  final List<CategoryRef> categories;
}

/// 예산 vs 실제 한 줄. = Tauri BudgetGroupVsActualRow.
class BudgetVsActual {
  const BudgetVsActual({
    required this.groupId,
    required this.groupName,
    required this.budgetAmount,
    required this.baseAmount,
    required this.adjustment,
    required this.carryForward,
    required this.spentAmount,
    required this.usagePercent,
    required this.incomePercentage,
    required this.expectedIncome,
    required this.accountId,
    required this.accountName,
    required this.accountColor,
    required this.categories,
  });
  final int groupId;
  final String groupName;
  final int budgetAmount;
  final int baseAmount;
  final int adjustment;
  final bool carryForward;
  final int spentAmount;
  final int usagePercent; // 사용률 %
  final int? incomePercentage; // % 모드 비율
  final int? expectedIncome; // % 모드일 때 사용된 예상 소득
  final int? accountId;
  final String? accountName;
  final String? accountColor;
  final List<CategoryRef> categories;
}

class BudgetLimitWarning {
  const BudgetLimitWarning({
    required this.groupId,
    required this.groupName,
    required this.budgetAmount,
    required this.spentAmount,
    required this.remaining,
    required this.thresholdPercent,
  });

  final int groupId;
  final String groupName;
  final int budgetAmount;
  final int spentAmount;
  final int remaining;
  final int thresholdPercent;

  bool get exceeded => remaining < 0;
}

@DriftAccessor(
  tables: [
    BudgetGroups,
    BudgetGroupCategories,
    Categories,
    Accounts,
    Transactions,
    MonthlyIncome,
  ],
)
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  // ── 월 예상 소득 ──────────────────────────────────────────────
  Future<int> getMonthlyExpectedIncome(String month) async {
    final row = await (select(
      monthlyIncome,
    )..where((m) => m.month.equals(month))).getSingleOrNull();
    return row?.expectedIncome ?? 0;
  }

  Future<void> setMonthlyExpectedIncome(String month, int income) async {
    await into(monthlyIncome).insert(
      MonthlyIncomeCompanion.insert(
        month: month,
        expectedIncome: Value(income),
        updatedAt: Value(sqlNow()),
        syncStatus: const Value(syncStatusPending),
      ),
      onConflict: DoUpdate(
        (_) => MonthlyIncomeCompanion(
          expectedIncome: Value(income),
          updatedAt: Value(sqlNow()),
          syncStatus: const Value(syncStatusPending),
        ),
        target: [monthlyIncome.month],
      ),
    );
  }

  // ── 그룹 조회 ────────────────────────────────────────────────
  Future<List<BudgetGroupRow>> listBudgetGroups(String month) async {
    final rows = await customSelect(
      '''
      SELECT g.id, g.name, g.month, g.amount, g.adjustment, g.carry_forward,
        g.account_id, g.percentage, a.name AS account_name, a.color AS account_color
      FROM budget_groups g
      LEFT JOIN accounts a ON a.id = g.account_id
      WHERE g.month = ?
      ''',
      variables: [Variable<String>(month)],
      readsFrom: {budgetGroups, accounts},
    ).get();

    if (rows.isEmpty) return [];

    final groupIds = rows.map((r) => r.read<int>('id')).toList();
    final memberships = await customSelect(
      'SELECT bgc.group_id AS gid, c.id AS id, c.name AS name, c.color AS color '
      'FROM budget_group_categories bgc '
      'JOIN categories c ON c.id = bgc.category_id '
      'WHERE bgc.group_id IN (${_placeholders(groupIds.length)})',
      variables: groupIds.map(Variable<int>.new).toList(),
      readsFrom: {budgetGroupCategories, categories},
    ).get();

    final catsByGroup = <int, List<CategoryRef>>{};
    for (final m in memberships) {
      (catsByGroup[m.read<int>('gid')] ??= []).add(
        CategoryRef(
          id: m.read<int>('id'),
          name: m.read<String>('name'),
          color: m.read<String>('color'),
        ),
      );
    }

    return rows.map((r) {
      final id = r.read<int>('id');
      return BudgetGroupRow(
        id: id,
        name: r.read<String>('name'),
        month: r.read<String>('month'),
        amount: r.read<int>('amount'),
        adjustment: r.read<int>('adjustment'),
        carryForward: r.read<int>('carry_forward') != 0,
        accountId: r.readNullable<int>('account_id'),
        accountName: r.readNullable<String>('account_name'),
        accountColor: r.readNullable<String>('account_color'),
        percentage: r.readNullable<int>('percentage'),
        categories: catsByGroup[id] ?? const [],
      );
    }).toList();
  }

  // ── 그룹 CRUD ────────────────────────────────────────────────
  /// SPEC §4.4. % 모드면 amount 0 으로 저장, 자산 연동이면 carryForward 강제 false.
  Future<int> createBudgetGroup({
    required String name,
    required String month,
    required int amount,
    List<int> categoryIds = const [],
    int? accountId,
    int? percentage,
    bool carryForward = false,
  }) async {
    return transaction(() async {
      final storedAmount = percentage != null ? 0 : amount;
      final effectiveCarry = accountId != null ? false : carryForward;
      final groupId = await into(budgetGroups).insert(
        BudgetGroupsCompanion.insert(
          name: name,
          month: month,
          amount: storedAmount,
          accountId: Value(accountId),
          percentage: Value(percentage),
          carryForward: Value(effectiveCarry),
        ),
      );
      if (accountId == null) {
        for (final c in categoryIds) {
          await into(budgetGroupCategories).insert(
            BudgetGroupCategoriesCompanion.insert(
              groupId: groupId,
              categoryId: c,
            ),
          );
        }
      }
      return groupId;
    });
  }

  Future<void> updateBudgetGroupAmount(int groupId, int amount) =>
      _patch(groupId, BudgetGroupsCompanion(amount: Value(amount)));

  Future<void> updateBudgetGroupAdjustment(int groupId, int adjustment) =>
      _patch(groupId, BudgetGroupsCompanion(adjustment: Value(adjustment)));

  Future<void> updateBudgetGroupPercentage(int groupId, int? percentage) =>
      _patch(groupId, BudgetGroupsCompanion(percentage: Value(percentage)));

  Future<void> updateBudgetGroupAccount(int groupId, int accountId) =>
      _patch(groupId, BudgetGroupsCompanion(accountId: Value(accountId)));

  Future<void> updateBudgetGroupAccountLink(int groupId, int? accountId) =>
      _patch(
        groupId,
        BudgetGroupsCompanion(
          accountId: Value(accountId),
          carryForward: accountId == null
              ? const Value.absent()
              : const Value(false),
          percentage: accountId == null
              ? const Value.absent()
              : const Value(null),
        ),
      );

  Future<void> updateBudgetGroupCarryForward(int groupId, bool carryForward) =>
      _patch(groupId, BudgetGroupsCompanion(carryForward: Value(carryForward)));

  Future<void> _patch(int groupId, BudgetGroupsCompanion patch) async {
    await (update(budgetGroups)..where((g) => g.id.equals(groupId))).write(
      patch.copyWith(
        updatedAt: Value(sqlNow()),
        syncStatus: const Value(syncStatusPending),
      ),
    );
  }

  Future<void> addCategoryToGroup(int groupId, int categoryId) async {
    await transaction(() async {
      await into(budgetGroupCategories).insert(
        BudgetGroupCategoriesCompanion.insert(
          groupId: groupId,
          categoryId: categoryId,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await _markBudgetGroupPending(groupId);
    });
  }

  Future<void> removeCategoryFromGroup(int groupId, int categoryId) async {
    await transaction(() async {
      await (delete(budgetGroupCategories)..where(
            (m) => m.groupId.equals(groupId) & m.categoryId.equals(categoryId),
          ))
          .go();
      await _markBudgetGroupPending(groupId);
    });
  }

  Future<void> _markBudgetGroupPending(int groupId) async {
    await (update(budgetGroups)..where((g) => g.id.equals(groupId))).write(
      BudgetGroupsCompanion(
        updatedAt: Value(sqlNow()),
        syncStatus: const Value(syncStatusPending),
      ),
    );
  }

  Future<void> deleteBudgetGroup(int groupId) async {
    await (delete(budgetGroups)..where((g) => g.id.equals(groupId))).go();
  }

  // ── 예산 vs 실제 ─────────────────────────────────────────────
  /// SPEC §4.4. 그룹별로 유효 예산·사용액·사용률 계산.
  Future<List<BudgetVsActual>> budgetGroupVsActual(String month) async {
    final groups = await listBudgetGroups(month);
    if (groups.isEmpty) return [];

    final bounds = monthRange(month);
    final expectedIncome = await getMonthlyExpectedIncome(month);

    final result = <BudgetVsActual>[];
    for (final g in groups) {
      int budgetAmount;
      int baseAmount = g.amount;
      int adjustment = g.adjustment;
      int spentAmount;
      int? usedExpectedIncome;

      if (g.accountId != null) {
        // 자산 연동 예산
        final flow = await _accountBudget(
          g.accountId!,
          bounds.start,
          bounds.end,
        );
        budgetAmount = flow.available;
        spentAmount = flow.spent;
        baseAmount = flow.available;
        adjustment = 0;
      } else {
        // 카테고리 기반 (고정금액 또는 % 모드)
        spentAmount = 0;
        final categoryIds = g.categories.map((c) => c.id).toList();
        if (categoryIds.isNotEmpty) {
          final row = await customSelect(
            'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions '
            "WHERE occurred_on BETWEEN ? AND ? AND type = 'expense' "
            'AND category_id IN (${_placeholders(categoryIds.length)})',
            variables: [
              Variable<String>(bounds.start),
              Variable<String>(bounds.end),
              ...categoryIds.map(Variable<int>.new),
            ],
            readsFrom: {transactions},
          ).getSingle();
          spentAmount = row.read<int>('total');
        }

        if (g.percentage != null) {
          baseAmount = percentageBase(
            expectedIncome: expectedIncome,
            percentage: g.percentage!,
          );
          usedExpectedIncome = expectedIncome;
        }
        budgetAmount = effectiveBudget(
          base: baseAmount,
          adjustment: adjustment,
        );
      }

      result.add(
        BudgetVsActual(
          groupId: g.id,
          groupName: g.name,
          budgetAmount: budgetAmount,
          baseAmount: baseAmount,
          adjustment: adjustment,
          carryForward: g.carryForward,
          spentAmount: spentAmount,
          usagePercent: usagePercent(spent: spentAmount, budget: budgetAmount),
          incomePercentage: g.percentage,
          expectedIncome: usedExpectedIncome,
          accountId: g.accountId,
          accountName: g.accountName,
          accountColor: g.accountColor,
          categories: g.categories,
        ),
      );
    }
    return result;
  }

  Future<List<BudgetLimitWarning>> budgetLimitWarningsFor(
    TransactionDraft draft, {
    int thresholdPercent = 80,
  }) async {
    if (draft.type != 'expense' ||
        !isDateKey(draft.occurredOn) ||
        thresholdPercent < 1 ||
        thresholdPercent > 100) {
      return const [];
    }

    final month = draft.occurredOn.substring(0, 7);
    final rows = await budgetGroupVsActual(month);
    return [
      for (final row in rows)
        if (_isAffectedBudget(row, draft) &&
            row.budgetAmount > 0 &&
            row.spentAmount * 100 >= row.budgetAmount * thresholdPercent)
          BudgetLimitWarning(
            groupId: row.groupId,
            groupName: row.groupName,
            budgetAmount: row.budgetAmount,
            spentAmount: row.spentAmount,
            remaining: row.budgetAmount - row.spentAmount,
            thresholdPercent: thresholdPercent,
          ),
    ];
  }

  bool _isAffectedBudget(BudgetVsActual row, TransactionDraft draft) {
    final accountId = row.accountId;
    if (accountId != null) return accountId == draft.accountId;
    final categoryId = draft.categoryId;
    return categoryId != null &&
        row.categories.any((category) => category.id == categoryId);
  }

  /// SPEC §4.4 — 자산 연동 예산: 월초 잔액 + 월 입금/출금.
  Future<({int available, int spent})> _accountBudget(
    int accountId,
    String monthStart,
    String monthEnd,
  ) async {
    final acc = await (select(
      accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    final initial = acc?.initialBalance ?? 0;

    final beforeVars = [
      ...List.filled(5, Variable<int>(accountId)),
      Variable<String>(monthStart),
    ];
    final before = await customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN (type = 'income'   AND account_id      = ?) OR (type = 'transfer' AND to_account_id   = ?) THEN amount ELSE 0 END), 0) AS inflow,
        COALESCE(SUM(CASE WHEN (type = 'expense'  AND account_id      = ?) OR (type = 'transfer' AND from_account_id = ?) THEN amount ELSE 0 END), 0) AS outflow,
        COALESCE(SUM(CASE WHEN  type = 'adjustment' AND account_id    = ? THEN amount ELSE 0 END), 0) AS adjust
      FROM transactions WHERE occurred_on < ?
      ''',
      variables: beforeVars,
      readsFrom: {transactions},
    ).getSingle();

    final startBalance =
        initial +
        before.read<int>('inflow') -
        before.read<int>('outflow') +
        before.read<int>('adjust');

    final withinVars = [
      ...List.filled(4, Variable<int>(accountId)),
      Variable<String>(monthStart),
      Variable<String>(monthEnd),
    ];
    final within = await customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN (type = 'income'  AND account_id      = ?) OR (type = 'transfer' AND to_account_id   = ?) THEN amount ELSE 0 END), 0) AS inflow,
        COALESCE(SUM(CASE WHEN (type = 'expense' AND account_id      = ?) OR (type = 'transfer' AND from_account_id = ?) THEN amount ELSE 0 END), 0) AS outflow
      FROM transactions WHERE occurred_on BETWEEN ? AND ?
      ''',
      variables: withinVars,
      readsFrom: {transactions},
    ).getSingle();

    return accountBudgetFlow(
      startBalance: startBalance,
      monthInflow: within.read<int>('inflow'),
      monthOutflow: within.read<int>('outflow'),
    );
  }

  Future<({int available, int spent})> accountLinkedBudgetPreview(
    int accountId,
    String month,
  ) {
    final bounds = monthRange(month);
    return _accountBudget(accountId, bounds.start, bounds.end);
  }

  // ── 이전 달 복사 ─────────────────────────────────────────────
  /// SPEC §4.4 — 이전 달 그룹을 대상 월로 복사. carryForward 면 잔금을 조정액으로 이월.
  Future<int> copyBudgetGroupsWithCarryforward(
    String sourceMonth,
    String targetMonth,
  ) async {
    final sourceGroups = await budgetGroupVsActual(sourceMonth);
    var copied = 0;

    return transaction(() async {
      final targetIncome = await getMonthlyExpectedIncome(targetMonth);
      if (targetIncome == 0) {
        final sourceIncome = await getMonthlyExpectedIncome(sourceMonth);
        if (sourceIncome > 0) {
          await setMonthlyExpectedIncome(targetMonth, sourceIncome);
        }
      }

      for (final sg in sourceGroups) {
        final existing =
            await (select(budgetGroups)..where(
                  (g) =>
                      g.name.equals(sg.groupName) & g.month.equals(targetMonth),
                ))
                .getSingleOrNull();
        if (existing != null) continue;

        if (sg.accountId != null) {
          await into(budgetGroups).insert(
            BudgetGroupsCompanion.insert(
              name: sg.groupName,
              month: targetMonth,
              amount: 0,
              adjustment: const Value(0),
              carryForward: const Value(false),
              accountId: Value(sg.accountId),
            ),
          );
          copied++;
          continue;
        }

        final isPercent = sg.incomePercentage != null;
        final newAmount = isPercent ? 0 : sg.baseAmount;
        final newAdjustment = carryForwardAdjustment(
          carryForward: sg.carryForward,
          budget: sg.budgetAmount,
          spent: sg.spentAmount,
        );

        final groupId = await into(budgetGroups).insert(
          BudgetGroupsCompanion.insert(
            name: sg.groupName,
            month: targetMonth,
            amount: newAmount,
            adjustment: Value(newAdjustment),
            carryForward: Value(sg.carryForward),
            percentage: Value(sg.incomePercentage),
          ),
        );
        for (final c in sg.categories) {
          await into(budgetGroupCategories).insert(
            BudgetGroupCategoriesCompanion.insert(
              groupId: groupId,
              categoryId: c.id,
            ),
          );
        }
        copied++;
      }
      return copied;
    });
  }
}

String _placeholders(int n) => List.filled(n, '?').join(', ');
