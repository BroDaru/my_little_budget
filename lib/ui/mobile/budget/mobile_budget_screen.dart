import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/daos/budget_dao.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../../../features/budget/validation.dart';
import 'package:my_little_budget/features/budget/providers.dart';
import '../mobile_widgets.dart';

class MobileBudgetScreen extends ConsumerWidget {
  const MobileBudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final income = ref.watch(monthlyExpectedIncomeProvider);
    final rows = ref.watch(budgetRowsProvider);

    return MobilePageScaffold(
      title: '예산',
      onAdd: () => _BudgetGroupSheet.show(context, month: month),
      addTooltip: '예산 추가',
      children: [
        MobileMonthNav(
          month: month,
          onChanged: (value) =>
              ref.read(budgetMonthProvider.notifier).state = value,
        ),
        _CopyPreviousMonthAction(month: month),
        MobileAsync(
          value: income,
          builder: (value) => MobileCard(
            child: Row(
              children: [
                Expanded(
                  child: AmountLine(label: '예상 수입', value: formatKRW(value)),
                ),
                IconButton(
                  onPressed: () => _ExpectedIncomeSheet.show(
                    context,
                    month: month,
                    income: value,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '예상 수입 수정',
                ),
              ],
            ),
          ),
        ),
        MobileAsync(
          value: rows,
          builder: (value) {
            return Column(
              children: [
                _BudgetTotal(rows: value),
                if (value.isEmpty)
                  const EmptyMobileCard('이번 달 예산 그룹이 없습니다.')
                else
                  for (final row in value) _BudgetCard(row: row),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CopyPreviousMonthAction extends ConsumerStatefulWidget {
  const _CopyPreviousMonthAction({required this.month});

  final String month;

  @override
  ConsumerState<_CopyPreviousMonthAction> createState() =>
      _CopyPreviousMonthActionState();
}

class _CopyPreviousMonthActionState
    extends ConsumerState<_CopyPreviousMonthAction> {
  bool _busy = false;

  Future<void> _copy() async {
    setState(() => _busy = true);
    try {
      final sourceMonth = shiftMonth(widget.month, -1);
      final copied = await ref
          .read(budgetDaoProvider)
          .copyBudgetGroupsWithCarryforward(sourceMonth, widget.month);
      if (!mounted) return;
      refreshBudget(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$sourceMonth 예산에서 $copied개 그룹을 복사했습니다.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('예산 복사에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('mobile-budget-copy-previous-button'),
          onPressed: _busy ? null : _copy,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.copy_all_outlined),
          label: const Text('이전 달에서 복사'),
        ),
      ),
    );
  }
}

class _BudgetTotal extends StatelessWidget {
  const _BudgetTotal({required this.rows});

  final List<BudgetVsActual> rows;

  @override
  Widget build(BuildContext context) {
    final budget = rows.fold<int>(0, (sum, row) => sum + row.budgetAmount);
    final spent = rows.fold<int>(0, (sum, row) => sum + row.spentAmount);
    final remain = budget - spent;
    final income = context.appIncome;
    final expense = context.appExpense;

    return MobileCard(
      child: Column(
        children: [
          AmountLine(label: '총 예산', value: formatKRW(budget)),
          AmountLine(label: '총 사용', value: formatKRW(spent)),
          AmountLine(
            label: '남은 금액',
            value: formatKRW(remain),
            valueColor: remain < 0 ? expense : income,
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.row});

  final BudgetVsActual row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = row.spentAmount > row.budgetAmount;
    final danger = context.appExpense;
    final positive = context.appIncome;
    final progress = row.budgetAmount <= 0
        ? 0.0
        : (row.spentAmount / row.budgetAmount).clamp(0.0, 1.0);

    return MobileCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: InkWell(
        onTap: () => _BudgetGroupSheet.show(context, row: row),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.groupName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _BudgetGroupSheet.show(context, row: row),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '예산 수정',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatKRW(row.budgetAmount)} · ${formatKRW(row.spentAmount)} 사용 · ${row.usagePercent}%',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: over
                    ? danger
                    : theme.colorScheme.onSurface.withValues(alpha: 0.78),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: over ? danger : positive,
              backgroundColor: theme.dividerColor,
            ),
            if (row.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final category in row.categories)
                    Chip(
                      label: Text(category.name),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetGroupSheet extends ConsumerStatefulWidget {
  const _BudgetGroupSheet({this.month, this.row});

  final String? month;
  final BudgetVsActual? row;

  static Future<void> show(
    BuildContext context, {
    String? month,
    BudgetVsActual? row,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BudgetGroupSheet(month: month, row: row),
    );
  }

  @override
  ConsumerState<_BudgetGroupSheet> createState() => _BudgetGroupSheetState();
}

class _BudgetGroupSheetState extends ConsumerState<_BudgetGroupSheet> {
  late final _name = TextEditingController(text: widget.row?.groupName ?? '');
  late final _amount = TextEditingController(
    text: widget.row?.baseAmount.toString() ?? '',
  );
  late final _adjustment = TextEditingController(
    text: widget.row?.adjustment.toString() ?? '0',
  );
  late final _percentage = TextEditingController(
    text: widget.row?.incomePercentage?.toString() ?? '',
  );
  late final Set<int> _categoryIds =
      widget.row?.categories.map((category) => category.id).toSet() ?? <int>{};
  late int? _accountId = widget.row?.accountId;
  late bool _accountLinked = widget.row?.accountId != null;
  late bool _carryForward = widget.row?.carryForward ?? false;
  bool _busy = false;

  bool get _isEdit => widget.row != null;
  bool get _isAccountLinked => _accountLinked;
  bool get _isPercentage => widget.row?.incomePercentage != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _adjustment.dispose();
    _percentage.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final dao = ref.read(budgetDaoProvider);
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        final row = widget.row!;
        if (_isAccountLinked) {
          if (_accountId == null) {
            _showSnack('연결할 자산을 선택해주세요.');
            return;
          }
          await dao.updateBudgetGroupAccountLink(row.groupId, _accountId);
        } else {
          await dao.updateBudgetGroupAccountLink(row.groupId, null);
          if (_isPercentage) {
            final percentage = int.tryParse(_percentage.text.trim());
            if (percentage == null || percentage <= 0 || percentage > 1000) {
              _showSnack('비율은 1~1000 사이 숫자로 입력해주세요.');
              return;
            }
            await dao.updateBudgetGroupPercentage(row.groupId, percentage);
          } else {
            await dao.updateBudgetGroupAmount(
              row.groupId,
              parseKRW(_amount.text),
            );
          }
          await dao.updateBudgetGroupAdjustment(
            row.groupId,
            parseKRW(_adjustment.text),
          );
          await dao.updateBudgetGroupCarryForward(row.groupId, _carryForward);
          await _syncCategories(dao, row, _categoryIds);
        }
      } else {
        final result = validateBudgetGroup(
          name: _name.text,
          month: widget.month!,
          amount: parseKRW(_amount.text),
          categoryIds: _categoryIds.toList(),
          accountId: _isAccountLinked ? _accountId : null,
          carryForward: _carryForward,
        );
        if (result.isFail) {
          _showSnack(result.errors.values.first);
          return;
        }
        final draft = result.value!;
        await dao.createBudgetGroup(
          name: draft.name,
          month: draft.month,
          amount: draft.amount,
          categoryIds: draft.categoryIds,
          accountId: draft.accountId,
          carryForward: draft.carryForward,
        );
      }

      if (!mounted) return;
      refreshBudget(ref);
      Navigator.pop(context);
      _showSnack(_isEdit ? '예산을 수정했습니다.' : '예산을 추가했습니다.');
    } catch (e) {
      if (mounted) _showSnack('예산 저장에 실패했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final row = widget.row;
    if (row == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('예산 삭제'),
        content: Text("'${row.groupName}' 예산을 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(budgetDaoProvider).deleteBudgetGroup(row.groupId);
      if (!mounted) return;
      refreshBudget(ref);
      Navigator.pop(context);
      _showSnack('예산을 삭제했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(budgetExpenseCategoriesProvider);
    final accounts = ref.watch(budgetActiveAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: mobileBottomPadding(context, spacing: 16),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? '예산 수정' : '예산 추가',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (!_isEdit)
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '예산 이름',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Text(
                widget.row!.groupName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _accountLinked,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _accountLinked = value;
                      if (value) {
                        _carryForward = false;
                      } else {
                        _accountId = null;
                      }
                    }),
              contentPadding: EdgeInsets.zero,
              title: const Text('자산 연동'),
              subtitle: const Text('선택한 자산의 월 가용/사용 금액으로 예산을 계산합니다.'),
            ),
            const SizedBox(height: 8),
            if (_isAccountLinked)
              _AccountSelector(
                accounts: accounts,
                value: _accountId,
                enabled: !_busy,
                onChanged: (value) => setState(() => _accountId = value),
              )
            else ...[
              if (_isPercentage)
                TextField(
                  controller: _percentage,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '예상 수입 대비 비율',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                MobileAmountField(
                  controller: _amount,
                  enabled: !_busy,
                  label: '예산 금액',
                ),
              const SizedBox(height: 12),
              MobileAmountField(
                controller: _adjustment,
                enabled: !_busy && _isEdit,
                label: '조정액',
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _carryForward,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _carryForward = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('남은 금액 이월'),
              ),
              const SizedBox(height: 8),
              _CategorySelector(
                categories: categories,
                selectedIds: _categoryIds,
                enabled: !_busy,
                onChanged: () => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('삭제'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.appExpense,
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedIds,
    required this.enabled,
    required this.onChanged,
  });

  final AsyncValue<List<Category>> categories;
  final Set<int> selectedIds;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return categories.when(
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('연결 카테고리', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              '사용 가능한 지출 카테고리가 없습니다.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in items)
                  FilterChip(
                    label: Text(category.name),
                    selected: selectedIds.contains(category.id),
                    onSelected: enabled
                        ? (selected) {
                            if (selected) {
                              selectedIds.add(category.id);
                            } else {
                              selectedIds.remove(category.id);
                            }
                            onChanged();
                          }
                        : null,
                  ),
              ],
            ),
        ],
      ),
      loading: () => const LinearProgressIndicator(minHeight: 3),
      error: (error, _) =>
          Text(error.toString(), style: TextStyle(color: context.appExpense)),
    );
  }
}

class _AccountSelector extends StatelessWidget {
  const _AccountSelector({
    required this.accounts,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AsyncValue<List<Account>> accounts;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return accounts.when(
      data: (items) => DropdownButtonFormField<int>(
        initialValue: items.any((account) => account.id == value)
            ? value
            : null,
        items: [
          for (final account in items)
            DropdownMenuItem(value: account.id, child: Text(account.name)),
        ],
        onChanged: enabled ? onChanged : null,
        decoration: const InputDecoration(
          labelText: '연결 자산',
          border: OutlineInputBorder(),
        ),
      ),
      loading: () => const LinearProgressIndicator(minHeight: 3),
      error: (error, _) =>
          Text(error.toString(), style: TextStyle(color: context.appExpense)),
    );
  }
}

class _ExpectedIncomeSheet extends ConsumerStatefulWidget {
  const _ExpectedIncomeSheet({required this.month, required this.income});

  final String month;
  final int income;

  static Future<void> show(
    BuildContext context, {
    required String month,
    required int income,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExpectedIncomeSheet(month: month, income: income),
    );
  }

  @override
  ConsumerState<_ExpectedIncomeSheet> createState() =>
      _ExpectedIncomeSheetState();
}

class _ExpectedIncomeSheetState extends ConsumerState<_ExpectedIncomeSheet> {
  late final _income = TextEditingController(text: widget.income.toString());
  bool _busy = false;

  @override
  void dispose() {
    _income.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(budgetDaoProvider)
          .setMonthlyExpectedIncome(widget.month, parseKRW(_income.text));
      if (!mounted) return;
      refreshBudget(ref);
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예상 수입을 저장했습니다.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: mobileBottomPadding(context, spacing: 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '예상 수입 수정',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          MobileAmountField(
            controller: _income,
            enabled: !_busy,
            label: '예상 수입',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

Future<void> _syncCategories(
  BudgetDao dao,
  BudgetVsActual row,
  Set<int> selectedIds,
) async {
  final before = row.categories.map((category) => category.id).toSet();
  final toAdd = selectedIds.difference(before);
  final toRemove = before.difference(selectedIds);

  for (final categoryId in toAdd) {
    await dao.addCategoryToGroup(row.groupId, categoryId);
  }
  for (final categoryId in toRemove) {
    await dao.removeCategoryFromGroup(row.groupId, categoryId);
  }
}
