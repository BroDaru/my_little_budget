import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/date.dart';
import '../../../../core/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/validation.dart';
import '../../../../data/daos/transactions_dao.dart';
import '../../../../data/providers.dart';
import '../../../../features/transactions/validation.dart';
import 'package:my_little_budget/features/transactions/providers.dart';
import '../../../shared/spending_limit_warning.dart';
import 'form_fields.dart';

class TransactionEditDialog extends ConsumerStatefulWidget {
  const TransactionEditDialog({
    super.key,
    required this.row,
    this.duplicate = false,
  });

  final TransactionRow row;
  final bool duplicate;

  static Future<void> show(BuildContext context, TransactionRow row) {
    return showDialog<void>(
      context: context,
      builder: (_) => TransactionEditDialog(row: row),
    );
  }

  static Future<void> showDuplicate(BuildContext context, TransactionRow row) {
    return showDialog<void>(
      context: context,
      builder: (_) => TransactionEditDialog(row: row, duplicate: true),
    );
  }

  @override
  ConsumerState<TransactionEditDialog> createState() => _State();
}

class _State extends ConsumerState<TransactionEditDialog> {
  late String _type = widget.row.type;
  late DateTime _date = parseDateKey(widget.row.occurredOn);
  late int? _accountId = widget.row.accountId;
  late int? _categoryId = widget.row.categoryId;
  late int? _fromAccountId = widget.row.fromAccountId;
  late int? _toAccountId = widget.row.toAccountId;
  late List<String> _tags = widget.row.tags.map((t) => t.name).toList();
  late final _amountCtrl = TextEditingController(
    text: widget.row.amount.toString(),
  );
  late final _timeCtrl = TextEditingController(text: widget.row.occurredTime);
  late final _memoCtrl = TextEditingController(text: widget.row.memo ?? '');
  bool _busy = false;

  bool get _isEdit => !widget.duplicate;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _timeCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  ValidationResult<TransactionDraft> _validate() => validateTransaction(
    type: _type,
    amount: parseKRW(_amountCtrl.text),
    occurredOn: toDateKey(_date),
    occurredTime: parseTimeInput(_timeCtrl.text) ?? _timeCtrl.text.trim(),
    memo: _memoCtrl.text,
    accountId: _accountId,
    categoryId: _categoryId,
    fromAccountId: _fromAccountId,
    toAccountId: _toAccountId,
  );

  Future<void> _persist() async {
    final result = _validate();
    if (result.isFail) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errors.values.first)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(transactionsDaoProvider)
          .saveTransaction(
            id: _isEdit ? widget.row.id : null,
            draft: result.value!,
            tagNames: _tags,
          );
      final warning = await ref
          .read(transactionsDaoProvider)
          .cardLimitWarningFor(result.value!);
      final budgetWarnings = await ref
          .read(budgetDaoProvider)
          .budgetLimitWarningsFor(result.value!);
      refreshTransactions(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSpendingLimitWarnings(
        context,
        cardWarning: warning,
        budgetWarnings: budgetWarnings,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(transactionsDaoProvider).deleteTransaction(widget.row.id);
      refreshTransactions(ref);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDuplicate() {
    Navigator.of(context).pop();
    TransactionEditDialog.showDuplicate(context, widget.row);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('ko', 'KR'),
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(activeAccountsProvider).asData?.value ?? const [];
    final categories =
        ref.watch(activeCategoriesProvider).asData?.value ?? const [];
    final tagSuggestions =
        (ref.watch(allTagsProvider).asData?.value ?? const [])
            .map((t) => t.name)
            .toList();
    final visibleCats = categories
        .where((c) => c.type == (_type == 'income' ? 'income' : 'expense'))
        .toList();

    return AlertDialog(
      title: Text(_isEdit ? '거래 편집' : '거래 복사'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'income', label: Text('수입')),
                  ButtonSegment(value: 'expense', label: Text('지출')),
                  ButtonSegment(value: 'transfer', label: Text('이체')),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: Icon(Icons.calendar_today, size: 16),
                label: Text(toDateKey(_date)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _timeCtrl,
                decoration: const InputDecoration(
                  labelText: '시간',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onEditingComplete: () {
                  final parsed = parseTimeInput(_timeCtrl.text);
                  if (parsed != null) _timeCtrl.text = parsed;
                },
              ),
              const SizedBox(height: 12),
              if (_type == 'transfer') ...[
                AccountDropdown(
                  hint: '출금',
                  accounts: accounts,
                  value: _fromAccountId,
                  onChanged: (v) => setState(() => _fromAccountId = v),
                ),
                AccountDropdown(
                  hint: '입금',
                  accounts: accounts,
                  value: _toAccountId,
                  onChanged: (v) => setState(() => _toAccountId = v),
                ),
              ] else ...[
                AccountDropdown(
                  hint: '자산',
                  accounts: accounts,
                  value: _accountId,
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                CategoryDropdown(
                  categories: visibleCats,
                  value: _categoryId,
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: '금액',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  labelText: '메모',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TagInput(
                value: _tags,
                suggestions: tagSuggestions,
                onChanged: (v) => setState(() => _tags = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: context.desktopExpense,
            ),
            child: Text('삭제'),
          ),
        if (_isEdit)
          TextButton(
            onPressed: _busy ? null : _openDuplicate,
            child: Text('복사'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _persist,
          child: Text(_isEdit ? '저장' : '추가'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    );
  }
}
