import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/daos/transactions_dao.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../../../features/investments/quantity_precision.dart';
import 'package:my_little_budget/features/accounts/providers.dart';
import '../../../features/transactions/validation.dart';
import '../transactions/sheets/mobile_transaction_sheet.dart';
import '../mobile_widgets.dart';

class MobileAccountDetailScreen extends ConsumerWidget {
  const MobileAccountDetailScreen({super.key, required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountByIdProvider(accountId));
    final rows = ref.watch(accountTransactionsProvider(accountId));

    return MobilePageScaffold(
      title: '자산 상세',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/accounts'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('자산 목록'),
          ),
        ),
        MobileAsync(
          value: account,
          builder: (value) {
            if (value == null) return const EmptyMobileCard('자산을 찾을 수 없습니다.');
            return MobileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AmountLine(
                    label: _kindLabel(value.kind),
                    value: formatKRW(value.balance),
                    valueColor: value.balance < 0
                        ? context.appExpense
                        : context.appIncome,
                  ),
                  if (value.isInvestment)
                    Text(
                      '투자 자산',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        _AccountDetailFilterCard(accountId: accountId),
        MobileAsync(
          value: rows,
          builder: (value) {
            if (value.isEmpty) return const EmptyMobileCard('거래내역이 없습니다.');
            return Column(
              children: [
                for (final row in value)
                  _AccountTransactionCard(row: row, accountId: accountId),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AccountDetailFilterCard extends ConsumerWidget {
  const _AccountDetailFilterCard({required this.accountId});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(accountDetailFilterProvider(accountId));
    return MobileCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              filter.isActive ? _filterSummary(filter) : '전체 거래',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (filter.isActive)
            IconButton(
              key: const ValueKey('mobile-account-detail-filter-reset'),
              onPressed: () =>
                  ref
                          .read(accountDetailFilterProvider(accountId).notifier)
                          .state =
                      const AccountDetailFilter(),
              icon: const Icon(Icons.close),
              tooltip: '필터 초기화',
            ),
          OutlinedButton.icon(
            key: const ValueKey('mobile-account-detail-filter-button'),
            onPressed: () =>
                _AccountDetailFilterSheet.show(context, accountId: accountId),
            icon: const Icon(Icons.tune),
            label: const Text('필터'),
          ),
        ],
      ),
    );
  }

  String _filterSummary(AccountDetailFilter filter) {
    final parts = <String>[];
    if (filter.fromDate != null || filter.toDate != null) {
      parts.add('${filter.fromDate ?? '처음'} - ${filter.toDate ?? '오늘'}');
    }
    if (filter.categoryIds.isNotEmpty) {
      parts.add('카테고리 ${filter.categoryIds.length}');
    }
    if (filter.tagIds.isNotEmpty) parts.add('태그 ${filter.tagIds.length}');
    return parts.join(' · ');
  }
}

class _AccountDetailFilterSheet extends ConsumerStatefulWidget {
  const _AccountDetailFilterSheet({required this.accountId});

  final int accountId;

  static Future<void> show(BuildContext context, {required int accountId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountDetailFilterSheet(accountId: accountId),
    );
  }

  @override
  ConsumerState<_AccountDetailFilterSheet> createState() =>
      _AccountDetailFilterSheetState();
}

class _AccountDetailFilterSheetState
    extends ConsumerState<_AccountDetailFilterSheet> {
  late String? _fromDate;
  late String? _toDate;
  late Set<int> _categoryIds;
  late Set<int> _tagIds;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(accountDetailFilterProvider(widget.accountId));
    _fromDate = filter.fromDate;
    _toDate = filter.toDate;
    _categoryIds = {...filter.categoryIds};
    _tagIds = {...filter.tagIds};
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _fromDate : _toDate;
    final parsed = current == null ? DateTime.now() : DateTime.parse(current);
    final selected = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected == null) return;
    final value =
        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    setState(() {
      if (from) {
        _fromDate = value;
      } else {
        _toDate = value;
      }
    });
  }

  void _apply() {
    ref
        .read(accountDetailFilterProvider(widget.accountId).notifier)
        .state = AccountDetailFilter(
      fromDate: _fromDate,
      toDate: _toDate,
      categoryIds: _categoryIds,
      tagIds: _tagIds,
    );
    Navigator.pop(context);
  }

  void _reset() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _categoryIds = {};
      _tagIds = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(accountDetailCategoriesProvider);
    final tags = ref.watch(accountDetailTagsProvider);
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
            const Text(
              '거래 필터',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_fromDate ?? '시작일'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(from: false),
                    icon: const Icon(Icons.event),
                    label: Text(_toDate ?? '종료일'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('카테고리', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            MobileAsync(
              value: categories,
              builder: (items) => _FilterChips<Category>(
                items: items,
                selectedIds: _categoryIds,
                idOf: (item) => item.id,
                labelOf: (item) => item.name,
                onChanged: (ids) => setState(() => _categoryIds = ids),
              ),
            ),
            const SizedBox(height: 16),
            const Text('태그', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            MobileAsync(
              value: tags,
              builder: (items) => _FilterChips<Tag>(
                items: items,
                selectedIds: _tagIds,
                idOf: (item) => item.id,
                labelOf: (item) => '#${item.name}',
                onChanged: (ids) => setState(() => _tagIds = ids),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('초기화'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _apply, child: const Text('적용')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips<T> extends StatelessWidget {
  const _FilterChips({
    required this.items,
    required this.selectedIds,
    required this.idOf,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> items;
  final Set<int> selectedIds;
  final int Function(T item) idOf;
  final String Function(T item) labelOf;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('선택할 항목이 없습니다.');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          FilterChip(
            selected: selectedIds.contains(idOf(item)),
            label: Text(labelOf(item)),
            onSelected: (selected) {
              final next = {...selectedIds};
              if (selected) {
                next.add(idOf(item));
              } else {
                next.remove(idOf(item));
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _AccountTransactionCard extends ConsumerWidget {
  const _AccountTransactionCard({required this.row, required this.accountId});

  final TransactionRow row;
  final int accountId;

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    if (row.source == 'investment') {
      context.go('/investments');
      return;
    }
    if (row.type == 'adjustment') {
      await _MobileAdjustmentSheet.show(
        context,
        row: row,
        accountId: accountId,
      );
    } else {
      await MobileTransactionSheet.show(context, row: row);
    }
    refreshAccountDetail(ref, accountId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = row.type == 'income' ? context.appIncome : context.appExpense;
    return MobileCard(
      child: InkWell(
        onTap: () => _openEditor(context, ref),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatKRW(row.amount),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (row.balanceAfter != null)
                      Text(
                        formatKRW(row.balanceAfter!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            if (row.memo?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                row.memo!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _title {
    if (row.source == 'investment') return row.categoryName ?? '투자 거래';
    if (row.type == 'transfer') return '이체';
    return row.categoryName ?? _typeLabel(row.type);
  }

  String get _subtitle {
    final date = '${row.occurredOn} ${row.occurredTime}';
    if (row.source == 'investment') {
      final quantity = row.quantity == null || row.quantity == 0
          ? ''
          : ' · 수량 ${formatInvestmentQuantity(row.quantity!)}';
      return '$date$quantity';
    }
    if (row.type == 'transfer') {
      final from = row.fromAccountName ?? '-';
      final to = row.toAccountName ?? '-';
      return '$date · $from → $to';
    }
    return '$date · ${row.accountName ?? ''}';
  }
}

class _MobileAdjustmentSheet extends ConsumerStatefulWidget {
  const _MobileAdjustmentSheet({required this.row, required this.accountId});

  final TransactionRow row;
  final int accountId;

  static Future<void> show(
    BuildContext context, {
    required TransactionRow row,
    required int accountId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MobileAdjustmentSheet(row: row, accountId: accountId),
    );
  }

  @override
  ConsumerState<_MobileAdjustmentSheet> createState() =>
      _MobileAdjustmentSheetState();
}

class _MobileAdjustmentSheetState
    extends ConsumerState<_MobileAdjustmentSheet> {
  late DateTime _date = parseDateKey(widget.row.occurredOn);
  late final String _time = widget.row.occurredTime;
  late final _amount = TextEditingController(text: '${widget.row.amount}');
  late final _memo = TextEditingController(text: widget.row.memo ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final result = validateTransaction(
      type: 'adjustment',
      amount: parseKRW(_amount.text),
      occurredOn: toDateKey(_date),
      occurredTime: _time,
      memo: _memo.text,
      accountId: widget.accountId,
    );
    if (result.isFail) {
      _showSnack(result.errors.values.first);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(transactionsDaoProvider)
          .saveTransaction(id: widget.row.id, draft: result.value!);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('잔액 조정을 수정했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('잔액 조정 삭제'),
        content: const Text('이 잔액 조정 내역을 삭제할까요?'),
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
      await ref.read(transactionsDaoProvider).deleteTransaction(widget.row.id);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('잔액 조정을 삭제했습니다.');
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
            const Text(
              '잔액 조정',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(toDateKey(_date)),
            ),
            const SizedBox(height: 12),
            MobileAmountField(
              controller: _amount,
              enabled: !_busy,
              suffixText: null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memo,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '메모',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
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

String _typeLabel(String type) => switch (type) {
  'income' => '수입',
  'expense' => '지출',
  'transfer' => '이체',
  'adjustment' => '잔액 조정',
  _ => type,
};

String _kindLabel(String kind) => switch (kind) {
  'cash' => '현금',
  'bank' => '은행',
  'card' => '카드',
  'other' => '기타',
  _ => kind,
};
