import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../data/daos/transaction_presets_dao.dart';
import '../../../../data/daos/transactions_dao.dart';
import '../../../../data/database.dart';
import '../../../../data/providers.dart';
import '../../../../features/presets/validation.dart';
import '../../../../features/settings/providers.dart';
import '../../mobile_widgets.dart';

class MobileTransactionPresetSheet extends ConsumerStatefulWidget {
  const MobileTransactionPresetSheet({super.key, this.item, this.source});

  final TransactionPresetListItem? item;
  final TransactionRow? source;

  static Future<void> show(
    BuildContext context, {
    TransactionPresetListItem? item,
    TransactionRow? source,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => MobileTransactionPresetSheet(item: item, source: source),
  );

  @override
  ConsumerState<MobileTransactionPresetSheet> createState() => _State();
}

class _State extends ConsumerState<MobileTransactionPresetSheet> {
  late String _type =
      widget.item?.preset.type ?? widget.source?.type ?? 'expense';
  late int? _accountId =
      widget.item?.preset.accountId ?? widget.source?.accountId;
  late int? _categoryId =
      widget.item?.preset.categoryId ?? widget.source?.categoryId;
  late int? _fromAccountId =
      widget.item?.preset.fromAccountId ?? widget.source?.fromAccountId;
  late int? _toAccountId =
      widget.item?.preset.toAccountId ?? widget.source?.toAccountId;
  late final _name = TextEditingController(
    text: widget.item?.preset.name ?? '',
  );
  late final _amount = TextEditingController(
    text:
        (widget.item?.preset.amount ?? widget.source?.amount)?.toString() ?? '',
  );
  late final _memo = TextEditingController(
    text: widget.item?.preset.memo ?? widget.source?.memo ?? '',
  );
  late final _tags = TextEditingController(
    text:
        (widget.item?.tagNames ??
                widget.source?.tags.map((tag) => tag.name).toList() ??
                const <String>[])
            .join(', '),
  );
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _memo.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final result = validateTransactionPreset(
      name: _name.text,
      type: _type,
      amount: parseKRW(_amount.text),
      memo: _memo.text,
      accountId: _accountId,
      categoryId: _categoryId,
      fromAccountId: _fromAccountId,
      toAccountId: _toAccountId,
      tagNames: _tags.text.split(','),
    );
    if (result.isFail) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errors.values.first)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(transactionPresetsDaoProvider)
          .savePreset(id: widget.item?.preset.id, draft: result.value!);
      refreshTransactionPresets(ref);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(settingsAccountsProvider).asData?.value ?? const <Account>[];
    final categories =
        ref.watch(settingsActiveCategoriesProvider).asData?.value ??
        const <Category>[];
    final visibleCategories = categories
        .where((category) => category.type == _type)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? '프리셋 만들기' : '프리셋 수정'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('거래를 저장하는 화면이 아닙니다. 불러올 때 현재 날짜와 시간이 적용됩니다.'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('지출')),
              ButtonSegment(value: 'income', label: Text('수입')),
              ButtonSegment(value: 'transfer', label: Text('이체')),
            ],
            selected: {_type},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() {
                    _type = value.first;
                    _accountId = null;
                    _categoryId = null;
                    _fromAccountId = null;
                    _toAccountId = null;
                  }),
          ),
          const SizedBox(height: 12),
          _field(_name, '프리셋 이름(선택)'),
          const SizedBox(height: 12),
          MobileAmountField(controller: _amount, enabled: !_busy),
          const SizedBox(height: 12),
          if (_type == 'transfer') ...[
            _accountDropdown('출금 자산', accounts, _fromAccountId, (value) {
              setState(() => _fromAccountId = value);
            }),
            const SizedBox(height: 12),
            _accountDropdown('입금 자산', accounts, _toAccountId, (value) {
              setState(() => _toAccountId = value);
            }),
          ] else ...[
            _accountDropdown('자산', accounts, _accountId, (value) {
              setState(() => _accountId = value);
            }),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: visibleCategories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              items: [
                for (final category in visibleCategories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
              decoration: const InputDecoration(
                labelText: '카테고리',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _field(_memo, '메모'),
          const SizedBox(height: 12),
          _field(_tags, '태그(쉼표로 구분)'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.item == null ? '프리셋 저장' : '수정 저장'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _accountDropdown(
    String label,
    List<Account> accounts,
    int? value,
    ValueChanged<int?> onChanged,
  ) => DropdownButtonFormField<int>(
    initialValue: accounts.any((account) => account.id == value) ? value : null,
    items: [
      for (final account in accounts)
        DropdownMenuItem(value: account.id, child: Text(account.name)),
    ],
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
