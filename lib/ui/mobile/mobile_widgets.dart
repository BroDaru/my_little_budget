import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';

double mobileBottomPadding(BuildContext context, {double spacing = 0}) {
  final mediaQuery = MediaQuery.of(context);
  final obstruction =
      mediaQuery.viewInsets.bottom > mediaQuery.viewPadding.bottom
      ? mediaQuery.viewInsets.bottom
      : mediaQuery.viewPadding.bottom;
  return obstruction + spacing;
}

class MobilePage extends StatelessWidget {
  const MobilePage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 16),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}

class MobilePageScaffold extends StatelessWidget {
  const MobilePageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.onAdd,
    this.addTooltip = '추가',
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onAdd;
  final String addTooltip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: MobilePage(title: title, actions: actions, children: children),
      floatingActionButton: onAdd == null
          ? null
          : SafeArea(
              child: FloatingActionButton(
                onPressed: onAdd,
                tooltip: addTooltip,
                child: const Icon(Icons.add),
              ),
            ),
    );
  }
}

class MobileCard extends StatelessWidget {
  const MobileCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.cardTheme.color,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class MobileAsync<T> extends StatelessWidget {
  const MobileAsync({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () =>
          const MobileCard(child: LinearProgressIndicator(minHeight: 3)),
      error: (error, _) => MobileCard(
        child: Text(
          error.toString(),
          style: TextStyle(color: context.appExpense),
        ),
      ),
    );
  }
}

class MobileMonthNav extends StatelessWidget {
  const MobileMonthNav({
    super.key,
    required this.month,
    required this.onChanged,
  });

  final String month;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final date = parseMonthKey(month);
    return MobileCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onChanged(shiftMonth(month, -1)),
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 달',
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final selected = await showMobileMonthPicker(
                  context,
                  initialMonth: month,
                );
                if (selected != null) onChanged(selected);
              },
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                '${date.year}년 ${date.month}월',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(shiftMonth(month, 1)),
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 달',
          ),
        ],
      ),
    );
  }
}

Future<String?> showMobileMonthPicker(
  BuildContext context, {
  required String initialMonth,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (_) => _MobileMonthPicker(initialMonth: initialMonth),
  );
}

class _MobileMonthPicker extends StatefulWidget {
  const _MobileMonthPicker({required this.initialMonth});

  final String initialMonth;

  @override
  State<_MobileMonthPicker> createState() => _MobileMonthPickerState();
}

class _MobileMonthPickerState extends State<_MobileMonthPicker> {
  late int _year = parseMonthKey(widget.initialMonth).year;
  late int _selectedMonth = parseMonthKey(widget.initialMonth).month;

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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final selected = month == _selectedMonth;
              return FilledButton.tonal(
                onPressed: () {
                  setState(() => _selectedMonth = month);
                  Navigator.pop(context, toMonthKey(DateTime(_year, month, 1)));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
                  foregroundColor: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('$month월', maxLines: 1),
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }
}

class AmountLine extends StatelessWidget {
  const AmountLine({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyMobileCard extends StatelessWidget {
  const EmptyMobileCard(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MobileCard(
      child: Text(
        message,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class MobileAmountField extends StatelessWidget {
  const MobileAmountField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.enabled = true,
    this.label = '금액',
    this.suffixText = '원',
    this.helperText,
    this.onCompleted,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final bool enabled;
  final String label;
  final String? suffixText;
  final String? helperText;
  final VoidCallback? onCompleted;

  Future<void> _openCalculator(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MobileAmountCalculatorPage(
          initialValue: controller.text,
          title: label,
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    controller.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
    onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      readOnly: true,
      showCursor: false,
      keyboardType: TextInputType.none,
      onTap: enabled ? () => _openCalculator(context) : null,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _MobileAmountCalculatorPage extends StatefulWidget {
  const _MobileAmountCalculatorPage({
    required this.initialValue,
    required this.title,
  });

  final String initialValue;
  final String title;

  @override
  State<_MobileAmountCalculatorPage> createState() =>
      _MobileAmountCalculatorPageState();
}

class _MobileAmountCalculatorPageState
    extends State<_MobileAmountCalculatorPage> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _complete() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      final result = parseKRW(text).toString();
      _controller.value = TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('mobile-transaction-amount-calculator-page'),
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          tooltip: '닫기',
        ),
      ),
      body: KeyedSubtree(
        key: const ValueKey('mobile-amount-calculator-page'),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        final display = value.text.isEmpty ? '0' : value.text;
                        return Text(
                          display,
                          key: const ValueKey(
                            'mobile-transaction-calculator-display',
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _MobileAmountKeypad(controller: _controller, onDone: _complete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAmountKeypad extends StatelessWidget {
  const _MobileAmountKeypad({required this.controller, required this.onDone});

  final TextEditingController controller;
  final VoidCallback onDone;

  static const _rows = [
    [
      _MobileAmountKey('C', _MobileAmountKeyAction.clear),
      _MobileAmountKey('backspace', _MobileAmountKeyAction.backspace),
      _MobileAmountKey('()', _MobileAmountKeyAction.parentheses),
      _MobileAmountKey('÷', _MobileAmountKeyAction.input),
    ],
    [
      _MobileAmountKey('7', _MobileAmountKeyAction.input),
      _MobileAmountKey('8', _MobileAmountKeyAction.input),
      _MobileAmountKey('9', _MobileAmountKeyAction.input),
      _MobileAmountKey('×', _MobileAmountKeyAction.input),
    ],
    [
      _MobileAmountKey('4', _MobileAmountKeyAction.input),
      _MobileAmountKey('5', _MobileAmountKeyAction.input),
      _MobileAmountKey('6', _MobileAmountKeyAction.input),
      _MobileAmountKey('-', _MobileAmountKeyAction.input),
    ],
    [
      _MobileAmountKey('1', _MobileAmountKeyAction.input),
      _MobileAmountKey('2', _MobileAmountKeyAction.input),
      _MobileAmountKey('3', _MobileAmountKeyAction.input),
      _MobileAmountKey('+', _MobileAmountKeyAction.input),
    ],
    [
      _MobileAmountKey('00', _MobileAmountKeyAction.input),
      _MobileAmountKey('0', _MobileAmountKeyAction.input),
      _MobileAmountKey('.', _MobileAmountKeyAction.input),
      _MobileAmountKey('=', _MobileAmountKeyAction.done),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('mobile-transaction-amount-keypad'),
      color: Colors.transparent,
      child: Column(
        children: [
          for (final row in _rows)
            Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _MobileAmountKeyButton(
                        item: key,
                        onPressed: () => _handle(key),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _handle(_MobileAmountKey key) {
    switch (key.action) {
      case _MobileAmountKeyAction.input:
        _insert(key.label);
      case _MobileAmountKeyAction.parentheses:
        _insert(_nextParenthesis());
      case _MobileAmountKeyAction.clear:
        controller.clear();
      case _MobileAmountKeyAction.backspace:
        _backspace();
      case _MobileAmountKeyAction.done:
        final text = controller.text.trim();
        if (text.isNotEmpty) _replaceAll(parseKRW(text).toString());
        onDone();
    }
  }

  void _insert(String value) {
    final current = controller.value;
    final selection = current.selection;
    final text = current.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final normalizedStart = start.clamp(0, text.length).toInt();
    final normalizedEnd = end.clamp(0, text.length).toInt();
    final nextText = text.replaceRange(normalizedStart, normalizedEnd, value);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: normalizedStart + value.length,
      ),
    );
  }

  void _backspace() {
    final current = controller.value;
    final selection = current.selection;
    final text = current.text;
    if (text.isEmpty) return;
    if (selection.isValid && !selection.isCollapsed) {
      final start = selection.start.clamp(0, text.length).toInt();
      final end = selection.end.clamp(0, text.length).toInt();
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }

    final cursor = selection.isValid ? selection.start : text.length;
    final offset = cursor.clamp(0, text.length).toInt();
    if (offset == 0) return;
    controller.value = TextEditingValue(
      text: text.replaceRange(offset - 1, offset, ''),
      selection: TextSelection.collapsed(offset: offset - 1),
    );
  }

  String _nextParenthesis() {
    final selection = controller.selection;
    final text = controller.text;
    final cursor = selection.isValid
        ? selection.start.clamp(0, text.length).toInt()
        : text.length;
    final beforeCursor = text.substring(0, cursor);
    final openCount = '('.allMatches(beforeCursor).length;
    final closeCount = ')'.allMatches(beforeCursor).length;
    return openCount > closeCount ? ')' : '(';
  }

  void _replaceAll(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _MobileAmountKeyButton extends StatelessWidget {
  const _MobileAmountKeyButton({required this.item, required this.onPressed});

  final _MobileAmountKey item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAction = item.action != _MobileAmountKeyAction.input;
    final isDone = item.action == _MobileAmountKeyAction.done;
    final foreground = isDone
        ? theme.colorScheme.onPrimary
        : item.action == _MobileAmountKeyAction.clear ||
              item.action == _MobileAmountKeyAction.backspace
        ? context.appExpense
        : theme.colorScheme.onSurface;
    final background = isDone
        ? theme.colorScheme.primary
        : isAction ||
              item.label == '+' ||
              item.label == '-' ||
              item.label == '×' ||
              item.label == '÷'
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;

    return SizedBox(
      height: 54,
      child: FilledButton(
        key: ValueKey('mobile-transaction-keypad-${item.label}'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: background,
          foregroundColor: foreground,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: item.action == _MobileAmountKeyAction.backspace
            ? const Icon(Icons.backspace_outlined, size: 24)
            : Text(
                item.label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

enum _MobileAmountKeyAction { input, parentheses, clear, backspace, done }

class _MobileAmountKey {
  const _MobileAmountKey(this.label, this.action);

  final String label;
  final _MobileAmountKeyAction action;
}
