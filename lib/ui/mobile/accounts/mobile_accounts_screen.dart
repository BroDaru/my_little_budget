import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/daos/accounts_dao.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../../../features/accounts/validation.dart';
import 'package:my_little_budget/features/accounts/providers.dart';
import '../mobile_widgets.dart';

class MobileAccountsScreen extends ConsumerWidget {
  const MobileAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountBalancesProvider);
    final archived = ref.watch(archivedAccountsProvider);

    return MobilePageScaffold(
      title: '자산',
      onAdd: () => _AccountSheet.show(context),
      addTooltip: '자산 추가',
      children: [
        MobileAsync(
          value: accounts,
          builder: (value) {
            if (value.isEmpty) return const EmptyMobileCard('등록된 자산이 없습니다.');
            final included = value.where((row) => !row.excludeFromTotal);
            final totalAssets = included.fold<int>(
              0,
              (sum, row) => row.balance > 0 ? sum + row.balance : sum,
            );
            final totalDebt = included.fold<int>(
              0,
              (sum, row) => row.balance < 0 ? sum - row.balance : sum,
            );
            final netWorth = totalAssets - totalDebt;
            final income = context.appIncome;
            final expense = context.appExpense;
            return Column(
              children: [
                MobileCard(
                  child: Column(
                    children: [
                      AmountLine(
                        label: '총 자산',
                        value: formatKRW(totalAssets),
                        valueColor: income,
                      ),
                      AmountLine(
                        label: '총 부채',
                        value: formatKRW(totalDebt),
                        valueColor: totalDebt > 0 ? expense : null,
                      ),
                      AmountLine(
                        label: '순자산',
                        value: formatKRW(netWorth),
                        valueColor: netWorth < 0 ? expense : income,
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < value.length; i++)
                  _AccountCard(account: value[i], allAccounts: value, index: i),
              ],
            );
          },
        ),
        MobileAsync(
          value: archived,
          builder: (value) {
            if (value.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text(
                    '보관된 자산',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                for (final account in value)
                  _ArchivedAccountCard(account: account),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({
    required this.account,
    required this.allAccounts,
    required this.index,
  });

  final AccountBalance account;
  final List<AccountBalance> allAccounts;
  final int index;

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('자산 보관'),
        content: Text('${account.name} 자산을 보관할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('보관'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(accountsDaoProvider).archiveAccount(account.accountId);
    if (!context.mounted) return;
    refreshAccountsList(ref);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('자산을 보관했습니다.')));
  }

  Future<void> _move(WidgetRef ref, int direction) async {
    final target = index + direction;
    if (target < 0 || target >= allAccounts.length) return;
    final ordered = [...allAccounts];
    final moving = ordered.removeAt(index);
    ordered.insert(target, moving);
    await ref
        .read(accountsDaoProvider)
        .updateAccountOrder(ordered.map((row) => row.accountId).toList());
    refreshAccountsList(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final income = context.appIncome;
    final expense = context.appExpense;
    return MobileCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        onTap: () => context.go('/accounts/${account.accountId}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                _kindIcon(account.kind, account.isInvestment),
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _kindLabel(account.kind),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.78,
                          ),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (account.isInvestment) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.trending_up,
                          size: 14,
                          color: context.appIncome,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '투자',
                          style: TextStyle(
                            color: context.appIncome,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                formatKRW(account.balance),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: account.balance < 0 ? expense : income,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(
              width: 42,
              child: PopupMenuButton<String>(
                tooltip: '자산 메뉴',
                iconSize: 22,
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'detail') {
                    context.go('/accounts/${account.accountId}');
                  } else if (value == 'edit') {
                    _AccountSheet.show(context, account: account);
                  } else if (value == 'up') {
                    _move(ref, -1);
                  } else if (value == 'down') {
                    _move(ref, 1);
                  } else if (value == 'archive') {
                    _archive(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('거래내역 보기'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('수정'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_upward),
                      title: Text('위로 이동'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index < allAccounts.length - 1,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_downward),
                      title: Text('아래로 이동'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'archive',
                    child: ListTile(
                      leading: Icon(Icons.archive_outlined),
                      title: Text('보관'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedAccountCard extends ConsumerWidget {
  const _ArchivedAccountCard({required this.account});

  final Account account;

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    await ref.read(accountsDaoProvider).restoreAccount(account.id);
    if (!context.mounted) return;
    refreshAccountsList(ref);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('자산을 복원했습니다.')));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('영구 삭제'),
        content: Text('${account.name} 자산을 완전히 삭제할까요?'),
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

    final error = await ref.read(accountsDaoProvider).deleteAccount(account.id);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    refreshAccountsList(ref);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('자산을 삭제했습니다.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MobileCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_kindLabel(account.kind)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _restore(context, ref),
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('복원'),
          ),
          IconButton(
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline),
            tooltip: '삭제',
          ),
        ],
      ),
    );
  }
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.account});

  final AccountBalance? account;

  static Future<void> show(BuildContext context, {AccountBalance? account}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountSheet(account: account),
    );
  }

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _balance = TextEditingController(
    text: (widget.account?.balance ?? 0).toString(),
  );
  late final _cardLimit = TextEditingController(
    text: widget.account?.cardLimit?.toString() ?? '',
  );
  late String _kind = widget.account?.kind ?? 'bank';
  late bool _exclude = widget.account?.excludeFromTotal ?? false;
  late bool _investment = widget.account?.isInvestment ?? false;
  bool _busy = false;

  bool get _isEdit => widget.account != null;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _cardLimit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cardLimit = _kind == 'card' && _cardLimit.text.trim().isNotEmpty
        ? parseKRW(_cardLimit.text)
        : null;
    final result = validateAccount(
      name: _name.text,
      kind: _kind,
      initialBalance: parseKRW(_balance.text),
      cardLimit: cardLimit,
      excludeFromTotal: _exclude,
      isInvestment: _investment,
    );
    if (result.isFail) {
      _showSnack('자산 이름을 입력해주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(accountsDaoProvider)
          .saveAccount(
            id: widget.account?.accountId,
            draft: result.value!,
            currentBalance: parseKRW(_balance.text),
          );
      if (!mounted) return;
      refreshAccountsList(ref);
      Navigator.pop(context);
      _showSnack(_isEdit ? '자산을 수정했습니다.' : '자산을 추가했습니다.');
    } catch (e) {
      if (mounted) _showSnack('자산 저장에 실패했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final account = widget.account;
    if (account == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('자산 보관'),
        content: Text('${account.name} 자산을 보관할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('보관'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(accountsDaoProvider).archiveAccount(account.accountId);
      if (!mounted) return;
      refreshAccountsList(ref);
      Navigator.pop(context);
      _showSnack('자산을 보관했습니다.');
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
            Text(
              _isEdit ? '자산 수정' : '자산 추가',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '자산 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('현금')),
                DropdownMenuItem(value: 'bank', child: Text('은행')),
                DropdownMenuItem(value: 'card', child: Text('카드')),
                DropdownMenuItem(value: 'other', child: Text('기타')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _kind = value!),
              decoration: const InputDecoration(
                labelText: '종류',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_kind == 'card') ...[
              MobileAmountField(
                controller: _cardLimit,
                enabled: !_busy,
                label: '카드 한도',
                helperText: '현재 카드 부채가 한도의 80% 이상이면 경고합니다.',
              ),
              const SizedBox(height: 12),
            ],
            MobileAmountField(
              controller: _balance,
              enabled: !_busy,
              label: '현재 금액',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _exclude,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _exclude = value),
              title: const Text('총액에서 제외'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _investment,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _investment = value),
              title: const Text('투자 자산'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('보관'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.appAccent,
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

String _kindLabel(String kind) => switch (kind) {
  'cash' => '현금',
  'bank' => '은행',
  'card' => '카드',
  'other' => '기타',
  _ => kind,
};

IconData _kindIcon(String kind, bool investment) {
  if (investment) return Icons.trending_up;
  return switch (kind) {
    'cash' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'card' => Icons.credit_card,
    'other' => Icons.account_balance_wallet_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };
}
