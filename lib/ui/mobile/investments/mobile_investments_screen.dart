import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/daos/investments_dao.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../../../features/investments/cost_basis.dart';
import '../../../features/investments/quantity_precision.dart';
import '../../../features/investments/validation.dart';
import 'package:my_little_budget/features/investments/providers.dart';
import '../mobile_widgets.dart';

enum _InvestmentTab { holdings, transactions, realizedPnl }

final _annualInvestmentRowsProvider = FutureProvider.autoDispose
    .family<List<Investment>, int>(
      (ref, year) =>
          ref.watch(investmentsDaoProvider).listInvestmentsByYear(year),
    );

final _annualInvestmentSummaryProvider = FutureProvider.autoDispose
    .family<InvestmentSummary, int>(
      (ref, year) =>
          ref.watch(investmentsDaoProvider).investmentYearlySummary(year),
    );

final _annualRealizedPnlProvider = FutureProvider.autoDispose
    .family<List<RealizedPnL>, int>(
      (ref, year) => ref
          .watch(investmentsDaoProvider)
          .getRealizedPnL('$year-01-01', '$year-12-31'),
    );

class MobileInvestmentsScreen extends ConsumerStatefulWidget {
  const MobileInvestmentsScreen({super.key});

  @override
  ConsumerState<MobileInvestmentsScreen> createState() =>
      _MobileInvestmentsScreenState();
}

class _MobileInvestmentsScreenState
    extends ConsumerState<MobileInvestmentsScreen> {
  _InvestmentTab _tab = _InvestmentTab.holdings;
  final _search = TextEditingController();
  String _query = '';
  bool _yearly = false;
  int _year = DateTime.now().year;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(investmentMonthProvider);
    final filter = ref.watch(investmentFilterProvider);
    final summary = ref.watch(investmentMonthlySummaryProvider);
    final yearlySummary = ref.watch(_annualInvestmentSummaryProvider(_year));
    final holdings = ref.watch(currentHoldingsProvider);
    final rows = ref.watch(investmentRowsProvider);
    final yearlyRows = ref.watch(_annualInvestmentRowsProvider(_year));
    final realizedPnl = ref.watch(realizedPnlProvider);
    final yearlyRealizedPnl = ref.watch(_annualRealizedPnlProvider(_year));
    final visiblePnl = _yearly ? yearlyRealizedPnl : realizedPnl;
    final accounts =
        ref.watch(investmentFilterAccountsProvider).asData?.value ??
        const <Account>[];
    final accountNames = {
      for (final account in accounts) account.id: account.name,
    };

    return MobilePageScaffold(
      title: '투자',
      onAdd: () => _InvestmentSheet.show(context, side: 'buy'),
      addTooltip: '매수 추가',
      children: [
        _InvestmentPeriodBar(
          yearly: _yearly,
          month: month,
          year: _year,
          onModeChanged: (value) => setState(() {
            _yearly = value;
            if (value) _year = parseMonthKey(month).year;
          }),
          onMonthChanged: (value) =>
              ref.read(investmentMonthProvider.notifier).state = value,
          onYearChanged: (value) => setState(() => _year = value),
        ),
        MobileAsync(
          value: _yearly ? yearlySummary : summary,
          builder: (value) => _SummaryCard(summary: value),
        ),
        _InvestmentTabs(
          value: _tab,
          onChanged: (value) => setState(() => _tab = value),
        ),
        _InvestmentSearchFilterBar(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          onClear: () {
            _search.clear();
            setState(() => _query = '');
          },
          showFilter: _tab == _InvestmentTab.transactions,
          filterActive: filter.isActive,
          onFilter: () => _InvestmentSideFilterSheet.show(context),
        ),
        MobileAsync(
          value: holdings,
          builder: (holdingRows) {
            if (_tab != _InvestmentTab.holdings) {
              return const SizedBox.shrink();
            }
            return MobileAsync(
              value: visiblePnl,
              builder: (pnlRows) => _HoldingsCard(
                holdings: _filterHoldings(holdingRows, _query),
                pnlRows: pnlRows,
                isSearching: _query.trim().isNotEmpty,
              ),
            );
          },
        ),
        MobileAsync(
          value: _yearly ? yearlyRows : rows,
          builder: (value) {
            if (_tab != _InvestmentTab.transactions) {
              return const SizedBox.shrink();
            }
            final filteredRows = _filterRows(value, accountNames, _query);
            if (filteredRows.isEmpty) {
              return EmptyMobileCard(
                _query.trim().isEmpty ? '표시할 투자 내역이 없습니다.' : '검색 결과가 없습니다.',
              );
            }
            return Column(
              children: [
                for (final row in filteredRows)
                  _InvestmentCard(
                    row: row,
                    accountName: accountNames[row.accountId],
                  ),
              ],
            );
          },
        ),
        MobileAsync(
          value: visiblePnl,
          builder: (value) {
            if (_tab != _InvestmentTab.realizedPnl) {
              return const SizedBox.shrink();
            }
            return _RealizedPnlCard(rows: _filterPnlRows(value, _query));
          },
        ),
      ],
    );
  }
}

class _InvestmentPeriodBar extends StatelessWidget {
  const _InvestmentPeriodBar({
    required this.yearly,
    required this.month,
    required this.year,
    required this.onModeChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  final bool yearly;
  final String month;
  final int year;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<int> onYearChanged;

  Future<void> _pickPeriod(BuildContext context) async {
    if (yearly) {
      final selected = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        builder: (_) => _YearPickerSheet(initialYear: year),
      );
      if (selected != null) onYearChanged(selected);
      return;
    }

    final selected = await showMobileMonthPicker(context, initialMonth: month);
    if (selected != null) onMonthChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final date = parseMonthKey(month);
    final label = yearly ? '$year년' : '${date.year}년 ${date.month}월';

    return MobileCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => yearly
                    ? onYearChanged(year - 1)
                    : onMonthChanged(shiftMonth(month, -1)),
                icon: const Icon(Icons.chevron_left),
                tooltip: yearly ? '이전 연도' : '이전 월',
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPeriod(context),
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(label, overflow: TextOverflow.ellipsis),
                ),
              ),
              IconButton(
                onPressed: () => yearly
                    ? onYearChanged(year + 1)
                    : onMonthChanged(shiftMonth(month, 1)),
                icon: const Icon(Icons.chevron_right),
                tooltip: yearly ? '다음 연도' : '다음 월',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('월')),
                ButtonSegment(value: true, label: Text('연')),
              ],
              selected: {yearly},
              onSelectionChanged: (values) => onModeChanged(values.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearPickerSheet extends StatefulWidget {
  const _YearPickerSheet({required this.initialYear});

  final int initialYear;

  @override
  State<_YearPickerSheet> createState() => _YearPickerSheetState();
}

class _YearPickerSheetState extends State<_YearPickerSheet> {
  late int _year = widget.initialYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        mobileBottomPadding(context, spacing: 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _year -= 1),
                icon: const Icon(Icons.chevron_left),
                tooltip: '이전 연도',
              ),
              Expanded(
                child: Text(
                  '$_year년',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _year += 1),
                icon: const Icon(Icons.chevron_right),
                tooltip: '다음 연도',
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, _year),
            child: const Text('선택'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }
}

class _InvestmentTabs extends StatelessWidget {
  const _InvestmentTabs({required this.value, required this.onChanged});

  final _InvestmentTab value;
  final ValueChanged<_InvestmentTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_InvestmentTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _InvestmentTab.holdings,
              label: Text('보유종목', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: _InvestmentTab.transactions,
              label: Text('거래내역', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: _InvestmentTab.realizedPnl,
              label: Text('실현손익', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
          selected: {value},
          onSelectionChanged: (values) => onChanged(values.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ),
    );
  }
}

class _InvestmentSearchFilterBar extends StatelessWidget {
  const _InvestmentSearchFilterBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.showFilter,
    required this.filterActive,
    required this.onFilter,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool showFilter;
  final bool filterActive;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      child: Row(
        key: const ValueKey('mobile-investments-search-filter-bar'),
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('mobile-investments-search-field'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '종목, 계좌, 메모 검색',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('mobile-investments-search-clear'),
                        onPressed: onClear,
                        icon: const Icon(Icons.close),
                        tooltip: '검색어 지우기',
                      ),
              ),
            ),
          ),
          if (showFilter) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('mobile-investments-filter-button'),
              onPressed: onFilter,
              isSelected: filterActive,
              selectedIcon: const Icon(Icons.filter_alt),
              icon: const Icon(Icons.tune),
              tooltip: filterActive ? '필터 적용됨' : '필터',
            ),
          ],
        ],
      ),
    );
  }
}

List<CurrentHolding> _filterHoldings(
  List<CurrentHolding> holdings,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return holdings;
  return holdings
      .where((holding) => holding.ticker.toLowerCase().contains(query))
      .toList();
}

List<Investment> _filterRows(
  List<Investment> rows,
  Map<int, String> accountNames,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return rows;
  return rows.where((row) {
    final accountName = accountNames[row.accountId]?.toLowerCase() ?? '';
    final memo = row.memo?.toLowerCase() ?? '';
    return row.ticker.toLowerCase().contains(query) ||
        accountName.contains(query) ||
        memo.contains(query);
  }).toList();
}

List<RealizedPnL> _filterPnlRows(List<RealizedPnL> rows, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return rows;
  return rows.where((row) => row.ticker.toLowerCase().contains(query)).toList();
}

class _InvestmentSideFilterSheet extends ConsumerStatefulWidget {
  const _InvestmentSideFilterSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => const _InvestmentSideFilterSheet(),
    );
  }

  @override
  ConsumerState<_InvestmentSideFilterSheet> createState() =>
      _InvestmentSideFilterSheetState();
}

class _InvestmentSideFilterSheetState
    extends ConsumerState<_InvestmentSideFilterSheet> {
  late String? _side;

  @override
  void initState() {
    super.initState();
    _side = ref.read(investmentFilterProvider).side;
  }

  void _apply() {
    final filter = ref.read(investmentFilterProvider);
    ref.read(investmentFilterProvider.notifier).state = filter.copyWith(
      side: _side,
    );
    Navigator.pop(context);
  }

  void _reset() {
    ref.read(investmentFilterProvider.notifier).state =
        const InvestmentFilter();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const options = [
      (null, '전체'),
      ('buy', '매수'),
      ('sell', '매도'),
      ('dividend', '배당'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        mobileBottomPadding(context, spacing: 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '거래 유형 필터',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.$2),
                  selected: _side == option.$1,
                  onSelected: (_) => setState(() => _side = option.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 18),
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final InvestmentSummary summary;

  @override
  Widget build(BuildContext context) {
    final income = context.appIncome;
    final expense = context.appExpense;
    return MobileCard(
      child: Column(
        children: [
          AmountLine(label: '매수', value: formatKRW(summary.buy)),
          AmountLine(label: '매도', value: formatKRW(summary.sell)),
          AmountLine(label: '배당금', value: formatKRW(summary.dividend)),
          AmountLine(
            label: '실현손익',
            value: formatKRW(summary.realizedPnl),
            valueColor: summary.realizedPnl < 0 ? expense : income,
          ),
        ],
      ),
    );
  }
}

class _HoldingsCard extends StatelessWidget {
  const _HoldingsCard({
    required this.holdings,
    required this.pnlRows,
    required this.isSearching,
  });

  final List<CurrentHolding> holdings;
  final List<RealizedPnL> pnlRows;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    if (holdings.isEmpty) {
      return EmptyMobileCard(isSearching ? '검색 결과가 없습니다.' : '보유종목이 없습니다.');
    }
    final pnlByTicker = _pnlSummaryByTicker(pnlRows);
    return MobileCard(
      child: Column(
        children: [
          for (final holding in holdings) ...[
            _HoldingTile(
              holding: holding,
              realized: pnlByTicker[holding.ticker]?.realized ?? 0,
              dividends: pnlByTicker[holding.ticker]?.dividends ?? 0,
            ),
            if (holding != holdings.last) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({
    required this.holding,
    required this.realized,
    required this.dividends,
  });

  final CurrentHolding holding;
  final int realized;
  final int dividends;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = context.appIncome;
    final expense = context.appExpense;
    const unrealizedPnl = 0;
    const returnRate = 0.0;

    return InkWell(
      onTap: () => _HoldingActionsSheet.show(context, holding),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              holding.ticker,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            AmountLine(
              label: '보유수량',
              value: formatInvestmentQuantity(holding.quantity),
            ),
            AmountLine(
              label: '평균단가',
              value: formatKRW(holding.avgCost.round()),
            ),
            AmountLine(label: '평가금액', value: formatKRW(holding.totalCost)),
            AmountLine(label: '평가손익', value: formatKRW(unrealizedPnl)),
            AmountLine(
              label: '실현손익',
              value: formatKRW(realized),
              valueColor: realized < 0 ? expense : income,
            ),
            AmountLine(label: '배당금', value: formatKRW(dividends)),
            AmountLine(
              label: '수익률',
              value: '${(returnRate * 100).toStringAsFixed(1)}%',
              valueColor: returnRate < 0 ? expense : income,
            ),
          ],
        ),
      ),
    );
  }
}

class _TickerPnlSummary {
  const _TickerPnlSummary({required this.realized, required this.dividends});

  final int realized;
  final int dividends;
}

Map<String, _TickerPnlSummary> _pnlSummaryByTicker(List<RealizedPnL> rows) {
  final totals = <String, ({int realized, int dividends})>{};
  for (final row in rows) {
    final current = totals[row.ticker] ?? (realized: 0, dividends: 0);
    if (row.kind == RealizedKind.dividend) {
      totals[row.ticker] = (
        realized: current.realized,
        dividends: current.dividends + row.pnl,
      );
    } else {
      totals[row.ticker] = (
        realized: current.realized + row.pnl,
        dividends: current.dividends,
      );
    }
  }
  return {
    for (final entry in totals.entries)
      entry.key: _TickerPnlSummary(
        realized: entry.value.realized,
        dividends: entry.value.dividends,
      ),
  };
}

class _RealizedPnlCard extends StatelessWidget {
  const _RealizedPnlCard({required this.rows});

  final List<RealizedPnL> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const EmptyMobileCard('실현손익 내역이 없습니다.');

    final total = rows.fold<int>(0, (sum, row) => sum + row.pnl);
    final income = context.appIncome;
    final expense = context.appExpense;
    final byTicker = <String, int>{};
    for (final row in rows) {
      byTicker[row.ticker] = (byTicker[row.ticker] ?? 0) + row.pnl;
    }
    final entries = byTicker.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return MobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountLine(
            label: '총 실현손익',
            value: formatKRW(total),
            valueColor: total < 0 ? expense : income,
          ),
          const SizedBox(height: 10),
          const Text('종목별 실현손익', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final entry in entries)
            AmountLine(
              label: entry.key,
              value: formatKRW(entry.value),
              valueColor: entry.value < 0 ? expense : income,
            ),
          const SizedBox(height: 8),
          const Divider(),
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.ticker),
              subtitle: Text(
                '${_realizedKindLabel(row.kind)} · ${row.occurredOn} ${row.occurredTime}',
              ),
              trailing: Text(
                formatKRW(row.pnl),
                style: TextStyle(
                  color: row.pnl < 0 ? expense : income,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HoldingActionsSheet extends StatelessWidget {
  const _HoldingActionsSheet({required this.holding});

  final CurrentHolding holding;

  static Future<void> show(BuildContext context, CurrentHolding holding) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _HoldingActionsSheet(holding: holding),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        mobileBottomPadding(context, spacing: 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            holding.ticker,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '보유수량 ${formatInvestmentQuantity(holding.quantity)}',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _InvestmentSheet.show(
                context,
                side: 'sell',
                ticker: holding.ticker,
              );
            },
            child: const Text('매도 추가'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(context);
              _InvestmentSheet.show(
                context,
                side: 'dividend',
                ticker: holding.ticker,
              );
            },
            child: const Text('배당금 추가'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _InvestmentSheet.show(
                context,
                side: 'buy',
                ticker: holding.ticker,
              );
            },
            child: const Text('추가 매수'),
          ),
        ],
      ),
    );
  }
}

class _InvestmentCard extends ConsumerWidget {
  const _InvestmentCard({required this.row, this.accountName});

  final Investment row;
  final String? accountName;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('투자 거래 삭제'),
        content: Text('${row.ticker} ${_sideLabel(row.side)} 거래를 삭제할까요?'),
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

    await ref.read(investmentsDaoProvider).deleteInvestment(row.id);
    refreshInvestments(ref, accountId: row.accountId);
    ref.invalidate(_annualInvestmentRowsProvider);
    ref.invalidate(_annualInvestmentSummaryProvider);
    ref.invalidate(_annualRealizedPnlProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('투자 거래를 삭제했습니다.')));
  }

  void _edit(BuildContext context) {
    _InvestmentSheet.show(context, investment: row);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = switch (row.side) {
      'buy' => context.appExpense,
      'sell' => context.appIncome,
      'dividend' => context.appWarning,
      _ => theme.colorScheme.onSurface,
    };

    return MobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.ticker,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                _sideLabel(row.side),
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              PopupMenuButton<String>(
                tooltip: '거래 메뉴',
                onSelected: (value) {
                  if (value == 'edit') _edit(context);
                  if (value == 'delete') _delete(context, ref);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('수정'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('삭제'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          AmountLine(label: '금액', value: formatKRW(row.totalAmount)),
          if (row.quantity > 0)
            AmountLine(
              label: '수량',
              value: formatInvestmentQuantity(row.quantity),
            ),
          if (accountName != null) AmountLine(label: '계좌', value: accountName!),
          if (row.memo?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                row.memo!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${row.occurredOn} ${row.occurredTime}',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvestmentSheet extends ConsumerStatefulWidget {
  const _InvestmentSheet({required this.side, this.ticker, this.investment});

  final String side;
  final String? ticker;
  final Investment? investment;

  static Future<void> show(
    BuildContext context, {
    String side = 'buy',
    String? ticker,
    Investment? investment,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _InvestmentSheet(side: side, ticker: ticker, investment: investment),
    );
  }

  @override
  ConsumerState<_InvestmentSheet> createState() => _InvestmentSheetState();
}

class _InvestmentSheetState extends ConsumerState<_InvestmentSheet> {
  late DateTime _date;
  late final _ticker = TextEditingController(
    text: widget.investment?.ticker ?? widget.ticker ?? '',
  );
  late final _quantity = TextEditingController(
    text: widget.investment == null || widget.investment!.side == 'dividend'
        ? ''
        : formatInvestmentQuantity(widget.investment!.quantity),
  );
  late final _amount = TextEditingController(
    text: widget.investment?.totalAmount.toString() ?? '',
  );
  late final _memo = TextEditingController(text: widget.investment?.memo ?? '');
  bool _busy = false;

  String get _side => widget.investment?.side ?? widget.side;
  bool get _isEdit => widget.investment != null;
  bool get _isDividend => _side == 'dividend';
  bool get _tickerLocked => widget.ticker != null && widget.ticker!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final dateText = widget.investment?.occurredOn;
    _date = dateText == null ? DateTime.now() : DateTime.parse(dateText);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _quantity.dispose();
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
    final ticker = _ticker.text.trim();
    final holdings =
        ref.read(currentHoldingsProvider).asData?.value ?? const [];
    final heldQuantities = {
      for (final holding in holdings) holding.ticker: holding.quantity,
    };
    final original = widget.investment;
    if (original != null && original.side == 'sell') {
      heldQuantities[original.ticker] =
          (heldQuantities[original.ticker] ?? 0) + original.quantity;
    }
    final heldTickers = heldQuantities.keys.toSet();

    final result = validateInvestment(
      side: _side,
      occurredOn: toDateKey(_date),
      occurredTime: widget.investment?.occurredTime ?? nowTime(),
      ticker: ticker,
      quantity: _isDividend ? null : double.tryParse(_quantity.text.trim()),
      totalAmount: parseKRW(_amount.text),
      memo: _memo.text,
    );
    if (result.isFail) {
      _showSnack(_investmentErrorMessage(result.errors.keys.first));
      return;
    }

    final tickerError = checkTradableTicker(
      side: _side,
      ticker: ticker,
      heldTickers: heldTickers,
      existingTicker: widget.investment?.ticker,
    );
    if (tickerError != null) {
      _showSnack(
        _side == 'sell'
            ? '보유하지 않은 종목은 매도할 수 없습니다.'
            : '보유하지 않은 종목은 배당금을 입력할 수 없습니다.',
      );
      return;
    }

    final quantityError = checkSellQuantity(
      side: _side,
      ticker: ticker,
      quantity: result.value!.quantity,
      heldQuantities: heldQuantities,
    );
    if (quantityError != null) {
      _showSnack('보유수량보다 많이 매도할 수 없습니다.');
      return;
    }

    setState(() => _busy = true);
    try {
      final id = await ref
          .read(investmentsDaoProvider)
          .saveInvestment(id: widget.investment?.id, draft: result.value!);
      final saved = await ref
          .read(investmentsDaoProvider)
          .getInvestmentById(id);
      if (!mounted) return;
      refreshInvestments(ref, accountId: saved?.accountId);
      ref.invalidate(_annualInvestmentRowsProvider);
      ref.invalidate(_annualInvestmentSummaryProvider);
      ref.invalidate(_annualRealizedPnlProvider);
      Navigator.pop(context);
      _showSnack('${_sideLabel(_side)} 거래를 ${_isEdit ? '수정' : '추가'}했습니다.');
    } catch (e) {
      if (mounted) _showSnack('투자 거래 저장에 실패했습니다: $e');
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
              '${_sideLabel(_side)} ${_isEdit ? '수정' : '추가'}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(toDateKey(_date)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ticker,
              enabled: !_busy && !_tickerLocked,
              decoration: const InputDecoration(
                labelText: '종목명',
                border: OutlineInputBorder(),
              ),
            ),
            if (!_isDividend) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _quantity,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '수량',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            MobileAmountField(controller: _amount, enabled: !_busy),
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

String _sideLabel(String side) => switch (side) {
  'buy' => '매수',
  'sell' => '매도',
  'dividend' => '배당',
  _ => side,
};

String _realizedKindLabel(RealizedKind kind) => switch (kind) {
  RealizedKind.sell => '매도',
  RealizedKind.dividend => '배당금',
};

String _investmentErrorMessage(String field) => switch (field) {
  'ticker' => '종목명을 입력해주세요.',
  'quantity' => '수량은 0보다 커야 합니다.',
  'totalAmount' => '금액은 1원 이상이어야 합니다.',
  'occurredOn' => '날짜 형식이 올바르지 않습니다.',
  'occurredTime' => '시간 형식이 올바르지 않습니다.',
  'memo' => '메모는 200자 이하로 입력해주세요.',
  _ => '입력값을 확인해주세요.',
};
