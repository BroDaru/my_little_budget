import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/date.dart';
import '../../../../core/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/providers.dart';
import '../../../../features/transactions/validation.dart';
import '../../../../features/presets/validation.dart';
import 'package:my_little_budget/features/transactions/providers.dart';
import '../../../shared/spending_limit_warning.dart';
import 'form_fields.dart';

class InlineEntry extends ConsumerStatefulWidget {
  const InlineEntry({super.key, this.preset, this.presetRevision = 0});

  final TransactionPresetDraft? preset;
  final int presetRevision;

  @override
  ConsumerState<InlineEntry> createState() => _InlineEntryState();
}

class _InlineEntryState extends ConsumerState<InlineEntry> {
  String _type = 'expense';
  DateTime _date = DateTime.now();
  int? _accountId;
  int? _categoryId;
  int? _fromAccountId;
  int? _toAccountId;
  List<String> _tags = [];

  late final _dateCtrl = TextEditingController(text: toDateKey(_date));
  final _timeCtrl = TextEditingController(text: nowTime());
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  final _dateFocus = FocusNode();
  final _timeFocus = FocusNode();
  final _accountFocus = FocusNode();
  final _categoryFocus = FocusNode();
  final _tagFocus = FocusNode();
  final _fromAccountFocus = FocusNode();
  final _toAccountFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _memoFocus = FocusNode();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateFocus.addListener(_handleDateFocusChanged);
    _timeFocus.addListener(_handleTimeFocusChanged);
  }

  @override
  void didUpdateWidget(covariant InlineEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preset != null &&
        widget.presetRevision != oldWidget.presetRevision) {
      _applyPreset(widget.preset!);
    }
  }

  void _applyPreset(TransactionPresetDraft preset) {
    final now = DateTime.now();
    setState(() {
      _type = preset.type;
      _date = now;
      _dateCtrl.text = toDateKey(now);
      _timeCtrl.text = nowTime();
      _accountId = preset.accountId;
      _categoryId = preset.categoryId;
      _fromAccountId = preset.fromAccountId;
      _toAccountId = preset.toAccountId;
      _amountCtrl.text = preset.amount.toString();
      _memoCtrl.text = preset.memo ?? '';
      _tags = List<String>.from(preset.tagNames);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFirstField();
    });
  }

  @override
  void dispose() {
    _dateFocus.removeListener(_handleDateFocusChanged);
    _timeFocus.removeListener(_handleTimeFocusChanged);
    _dateFocus.dispose();
    _timeFocus.dispose();
    _accountFocus.dispose();
    _categoryFocus.dispose();
    _tagFocus.dispose();
    _fromAccountFocus.dispose();
    _toAccountFocus.dispose();
    _amountFocus.dispose();
    _memoFocus.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _handleDateFocusChanged() {
    if (_dateFocus.hasFocus) {
      _selectAll(_dateCtrl);
    } else {
      _syncDateAndTime(showErrors: false);
    }
  }

  void _handleTimeFocusChanged() {
    if (_timeFocus.hasFocus) {
      _selectAll(_timeCtrl);
    } else {
      _syncDateAndTime(showErrors: false);
    }
  }

  void _selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _focus(FocusNode node) {
    node.requestFocus();
  }

  void _focusFirstField() {
    _focus(_amountFocus);
  }

  void _focusAfterAmount() {
    _focus(_type == 'transfer' ? _fromAccountFocus : _accountFocus);
  }

  void _focusAfterDate() {
    if (_syncDateAndTime()) _focus(_timeFocus);
  }

  void _focusAfterTime() {
    if (!_syncDateAndTime()) return;
    _focus(_type == 'transfer' ? _memoFocus : _tagFocus);
  }

  void _focusAfterAccount() {
    _focus(_categoryFocus);
  }

  void _focusAfterCategory() {
    _focus(_dateFocus);
  }

  void _focusAfterTag() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(_memoFocus);
    });
  }

  void _focusAfterFromAccount() {
    _focus(_toAccountFocus);
  }

  void _focusAfterToAccount() {
    _focus(_dateFocus);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('ko', 'KR'),
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateCtrl.text = toDateKey(picked);
      });
      _focus(_timeFocus);
    }
  }

  DateTime? _parseDateInput(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;
    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
        return parseDateKey(input);
      }
      final now = DateTime.now();
      if (RegExp(r'^\d{2}-\d{2}$').hasMatch(input)) {
        final parts = input.split('-');
        return DateTime(now.year, int.parse(parts[0]), int.parse(parts[1]));
      }
      if (RegExp(r'^\d{4}$').hasMatch(input)) {
        return DateTime(
          now.year,
          int.parse(input.substring(0, 2)),
          int.parse(input.substring(2, 4)),
        );
      }
      if (RegExp(r'^\d{6}$').hasMatch(input)) {
        return DateTime(
          2000 + int.parse(input.substring(0, 2)),
          int.parse(input.substring(2, 4)),
          int.parse(input.substring(4, 6)),
        );
      }
      if (RegExp(r'^\d{8}$').hasMatch(input)) {
        return DateTime(
          int.parse(input.substring(0, 4)),
          int.parse(input.substring(4, 6)),
          int.parse(input.substring(6, 8)),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _syncDateAndTime({bool showErrors = true}) {
    final parsedDate = _parseDateInput(_dateCtrl.text);
    final parsedTime = parseTimeInput(_timeCtrl.text);
    if (parsedDate == null) {
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\uB0A0\uC9DC\uB294 YYYY-MM-DD \uD615\uC2DD\uC774\uC5B4\uC57C \uD569\uB2C8\uB2E4.',
            ),
          ),
        );
      }
      return false;
    }
    if (parsedTime == null) {
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\uC2DC\uAC04\uC740 HH:MM \uD615\uC2DD\uC774\uC5B4\uC57C \uD569\uB2C8\uB2E4.',
            ),
          ),
        );
      }
      return false;
    }

    _date = parsedDate;
    _dateCtrl.text = toDateKey(parsedDate);
    _timeCtrl.text = parsedTime;
    return true;
  }

  void _focusFirstError(Map<String, String> errors) {
    if (errors.containsKey('occurredOn')) {
      _focus(_dateFocus);
    } else if (errors.containsKey('occurredTime')) {
      _focus(_timeFocus);
    } else if (errors.containsKey('accountId')) {
      _focus(_accountFocus);
    } else if (errors.containsKey('categoryId')) {
      _focus(_categoryFocus);
    } else if (errors.containsKey('fromAccountId')) {
      _focus(_fromAccountFocus);
    } else if (errors.containsKey('toAccountId')) {
      _focus(_toAccountFocus);
    } else if (errors.containsKey('amount')) {
      _focus(_amountFocus);
    } else if (errors.containsKey('memo')) {
      _focus(_memoFocus);
    }
  }

  Future<bool> _save() async {
    if (!_syncDateAndTime()) {
      _focus(_parseDateInput(_dateCtrl.text) == null ? _dateFocus : _timeFocus);
      return false;
    }
    final result = validateTransaction(
      type: _type,
      amount: parseKRW(_amountCtrl.text),
      occurredOn: _dateCtrl.text,
      occurredTime: _timeCtrl.text,
      memo: _memoCtrl.text,
      accountId: _accountId,
      categoryId: _categoryId,
      fromAccountId: _fromAccountId,
      toAccountId: _toAccountId,
    );

    if (result.isFail) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errors.values.first)));
      _focusFirstError(result.errors);
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(transactionsDaoProvider)
          .saveTransaction(
            draft: result.value!,
            tagNames: _type == 'transfer' ? const [] : _tags,
          );
      final warning = await ref
          .read(transactionsDaoProvider)
          .cardLimitWarningFor(result.value!);
      final budgetWarnings = await ref
          .read(budgetDaoProvider)
          .budgetLimitWarningsFor(result.value!);
      refreshTransactions(ref);
      if (!mounted) return true;
      showSpendingLimitWarnings(
        context,
        cardWarning: warning,
        budgetWarnings: budgetWarnings,
      );
      setState(() {
        _amountCtrl.clear();
        _memoCtrl.clear();
        _tags = [];
        _timeCtrl.text = nowTime();
      });
      _focusFirstField();
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final memoSuggestions =
        ref.watch(recentMemosProvider).asData?.value ?? const [];
    final visibleCats = categories
        .where((c) => c.type == (_type == 'income' ? 'income' : 'expense'))
        .toList();

    return Container(
      key: const ValueKey('desktop-transactions-inline-entry'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.desktopSurface,
        border: Border.all(color: context.desktopBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          children: [
            Row(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'income', label: Text('\uC218\uC785')),
                    ButtonSegment(
                      value: 'expense',
                      label: Text('\uC9C0\uCD9C'),
                    ),
                    ButtonSegment(
                      value: 'transfer',
                      label: Text('\uC774\uCCB4'),
                    ),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _categoryId = null;
                    if (_type == 'transfer') _tags = [];
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: TextField(
                      key: const ValueKey('desktop-transactions-inline-amount'),
                      controller: _amountCtrl,
                      focusNode: _amountFocus,
                      keyboardType: TextInputType.text,
                      textAlign: TextAlign.left,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: '₩ 금액',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _focusAfterAmount(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_type == 'transfer') ...[
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: AccountDropdown(
                        hint: '\uCD9C\uAE08',
                        accounts: accounts,
                        value: _fromAccountId,
                        width: null,
                        focusNode: _fromAccountFocus,
                        onChanged: (v) => setState(() => _fromAccountId = v),
                        onSubmitted: (_) => _focusAfterFromAccount(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: context.desktopMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: AccountDropdown(
                        hint: '\uC785\uAE08',
                        accounts: accounts,
                        value: _toAccountId,
                        width: null,
                        focusNode: _toAccountFocus,
                        onChanged: (v) => setState(() => _toAccountId = v),
                        onSubmitted: (_) => _focusAfterToAccount(),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: AccountDropdown(
                        hint: '\uC790\uC0B0',
                        accounts: accounts,
                        value: _accountId,
                        width: null,
                        focusNode: _accountFocus,
                        onChanged: (v) => setState(() => _accountId = v),
                        onSubmitted: (_) => _focusAfterAccount(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: CategoryDropdown(
                        categories: visibleCats,
                        value: _categoryId,
                        width: null,
                        focusNode: _categoryFocus,
                        onChanged: (v) => setState(() => _categoryId = v),
                        onSubmitted: (_) => _focusAfterCategory(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                SizedBox(
                  width: 74,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(74, 40),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('\uCD94\uAC00', softWrap: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 168,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(4),
                    child: TextField(
                      key: const ValueKey('desktop-transactions-inline-date'),
                      controller: _dateCtrl,
                      focusNode: _dateFocus,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: '\uB0A0\uC9DC',
                        isDense: true,
                        prefixIcon: const Icon(Icons.calendar_today, size: 16),
                        prefixIconConstraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 36,
                        ),
                        suffixIcon: IconButton(
                          tooltip: '\uB0A0\uC9DC \uC120\uD0DD',
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _pickDate,
                          icon: const Icon(Icons.expand_more, size: 18),
                        ),
                        suffixIconConstraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 36,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _focusAfterDate(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 74,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(5),
                    child: TextField(
                      key: const ValueKey('desktop-transactions-inline-time'),
                      controller: _timeCtrl,
                      focusNode: _timeFocus,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: '\uC2DC\uAC04',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _focusAfterTime(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_type != 'transfer') ...[
                  Flexible(
                    flex: 2,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(6),
                      child: TagAutocompleteField(
                        value: _tags,
                        suggestions: tagSuggestions,
                        width: null,
                        focusNode: _tagFocus,
                        onChanged: (v) => setState(() => _tags = v),
                        onSubmitted: (result) {
                          if (result != TagSubmitResult.none) {
                            _focusAfterTag();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  flex: _type == 'transfer' ? 1 : 3,
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder(_type == 'transfer' ? 6 : 7),
                    child: MemoAutocompleteField(
                      controller: _memoCtrl,
                      suggestions: memoSuggestions,
                      focusNode: _memoFocus,
                      onSubmitted: (committedSuggestion) {
                        if (!committedSuggestion) _save();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
