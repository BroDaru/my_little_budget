import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/database.dart';
import '../../color_hex.dart';

typedef FieldSubmitted = void Function(bool committedSuggestion);

enum TagSubmitResult { added, empty, none }

typedef TagSubmitted = void Function(TagSubmitResult result);

class AccountDropdown extends StatefulWidget {
  const AccountDropdown({
    super.key,
    required this.hint,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.width = 150,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final String hint;
  final List<Account> accounts;
  final int? value;
  final ValueChanged<int?> onChanged;
  final double? width;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final FieldSubmitted? onSubmitted;

  @override
  State<AccountDropdown> createState() => _AccountDropdownState();
}

class _AccountDropdownState extends State<AccountDropdown> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedName());
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(AccountDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedName = _selectedName();
    if (!_focusNode.hasFocus && _controller.text != selectedName) {
      _controller.text = selectedName;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commitFirstMatch();
  }

  String _selectedName() {
    for (final account in widget.accounts) {
      if (account.id == widget.value) return account.name;
    }
    return '';
  }

  Iterable<Account> _matches(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return widget.accounts;
    final matching = <Account>[];
    final remaining = <Account>[];
    for (final account in widget.accounts) {
      (account.name.toLowerCase().contains(query) ? matching : remaining).add(
        account,
      );
    }
    return [...matching, ...remaining];
  }

  Iterable<Account> _matchingOnly(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return widget.accounts;
    return widget.accounts.where(
      (account) => account.name.toLowerCase().contains(query),
    );
  }

  void _select(Account account) {
    widget.onChanged(account.id);
    _controller.text = account.name;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  bool _commitFirstMatch() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      widget.onChanged(null);
      return false;
    }

    for (final account in widget.accounts) {
      if (account.name.toLowerCase() == query.toLowerCase()) {
        _select(account);
        return true;
      }
    }

    final first = _matchingOnly(query).cast<Account?>().firstOrNull;
    if (first == null) return false;
    _select(first);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final field = RawAutocomplete<Account>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (account) => account.name,
      optionsBuilder: (textEditingValue) => _matches(textEditingValue.text),
      onSelected: _select,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          decoration: InputDecoration(
            hintText: widget.hint,
            isDense: true,
            suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.trim().isEmpty) widget.onChanged(null);
          },
          onSubmitted: (_) {
            final before = _controller.text;
            onFieldSubmitted();
            if (_controller.text != before) {
              widget.onSubmitted?.call(true);
              return;
            }
            widget.onSubmitted?.call(_commitFirstMatch());
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsSurface<Account>(
          width: widget.width ?? 180,
          options: options.toList(),
          onSelected: onSelected,
          itemBuilder: (context, account, highlighted) =>
              _OptionTile(label: account.name, highlighted: highlighted),
        );
      },
    );
    if (widget.width == null) return field;
    return SizedBox(width: widget.width, child: field);
  }
}

class CategoryDropdown extends StatefulWidget {
  const CategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    this.width = 150,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final List<Category> categories;
  final int? value;
  final ValueChanged<int?> onChanged;
  final double? width;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final FieldSubmitted? onSubmitted;

  @override
  State<CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<CategoryDropdown> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedName());
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(CategoryDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedName = _selectedName();
    if (!_focusNode.hasFocus && _controller.text != selectedName) {
      _controller.text = selectedName;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commitFirstMatch();
  }

  String _selectedName() {
    for (final category in widget.categories) {
      if (category.id == widget.value) return category.name;
    }
    return '';
  }

  Iterable<Category> _matches(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return widget.categories;
    final matching = <Category>[];
    final remaining = <Category>[];
    for (final category in widget.categories) {
      (category.name.toLowerCase().contains(query) ? matching : remaining).add(
        category,
      );
    }
    return [...matching, ...remaining];
  }

  Iterable<Category> _matchingOnly(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return widget.categories;
    return widget.categories.where(
      (category) => category.name.toLowerCase().contains(query),
    );
  }

  void _select(Category category) {
    widget.onChanged(category.id);
    _controller.text = category.name;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  bool _commitFirstMatch() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      widget.onChanged(null);
      return false;
    }

    for (final category in widget.categories) {
      if (category.name.toLowerCase() == query.toLowerCase()) {
        _select(category);
        return true;
      }
    }

    final first = _matchingOnly(query).cast<Category?>().firstOrNull;
    if (first == null) return false;
    _select(first);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final field = RawAutocomplete<Category>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (category) => category.name,
      optionsBuilder: (textEditingValue) => _matches(textEditingValue.text),
      onSelected: _select,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          decoration: const InputDecoration(
            hintText: '\uCE74\uD14C\uACE0\uB9AC',
            isDense: true,
            suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.trim().isEmpty) widget.onChanged(null);
          },
          onSubmitted: (_) {
            final before = _controller.text;
            onFieldSubmitted();
            if (_controller.text != before) {
              widget.onSubmitted?.call(true);
              return;
            }
            widget.onSubmitted?.call(_commitFirstMatch());
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsSurface<Category>(
          width: widget.width ?? 200,
          options: options.toList(),
          onSelected: onSelected,
          itemBuilder: (context, category, highlighted) => _OptionTile(
            label: category.name,
            highlighted: highlighted,
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorFromHex(category.color),
              ),
            ),
          ),
        );
      },
    );
    if (widget.width == null) return field;
    return SizedBox(width: widget.width, child: field);
  }
}

class MemoAutocompleteField extends StatefulWidget {
  const MemoAutocompleteField({
    super.key,
    required this.controller,
    required this.suggestions,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final List<String> suggestions;
  final FocusNode? focusNode;
  final FieldSubmitted? onSubmitted;

  @override
  State<MemoAutocompleteField> createState() => _MemoAutocompleteFieldState();
}

class _MemoAutocompleteFieldState extends State<MemoAutocompleteField> {
  late final FocusNode _focusNode;
  bool _navigatedOptions = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  Iterable<String> _matches(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return widget.suggestions;
    return widget.suggestions.where(
      (memo) => memo.toLowerCase().contains(query),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) => _matches(textEditingValue.text),
      onSelected: (memo) {
        widget.controller.text = memo;
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
        _navigatedOptions = false;
        _focusNode.requestFocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp)) {
              _navigatedOptions = true;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey('desktop-transactions-memo-field'),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '\uBA54\uBAA8',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (_navigatedOptions) {
                onFieldSubmitted();
                _navigatedOptions = false;
                return;
              }
              widget.onSubmitted?.call(false);
            },
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsSurface<String>(
          width: 260,
          options: options.toList(),
          onSelected: onSelected,
          itemBuilder: (context, memo, highlighted) => _OptionTile(
            label: memo,
            highlighted: highlighted,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _OptionsSurface<T extends Object> extends StatelessWidget {
  const _OptionsSurface({
    required this.options,
    required this.onSelected,
    required this.itemBuilder,
    required this.width,
  });

  final List<T> options;
  final AutocompleteOnSelected<T> onSelected;
  final Widget Function(BuildContext context, T option, bool highlighted)
  itemBuilder;
  final double width;

  @override
  Widget build(BuildContext context) {
    final highlightedIndex = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        color: context.desktopSurface,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 240, minWidth: width),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (var i = 0; i < options.length; i++)
                InkWell(
                  onTap: () => onSelected(options[i]),
                  child: itemBuilder(
                    context,
                    options[i],
                    i == highlightedIndex,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.highlighted,
    this.leading,
    this.overflow,
  });

  final String label;
  final bool highlighted;
  final Widget? leading;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: highlighted ? scheme.primaryContainer : Colors.transparent,
      child: ListTile(
        dense: true,
        leading: leading,
        title: Text(
          label,
          overflow: overflow,
          style: TextStyle(
            color: highlighted ? scheme.onPrimaryContainer : null,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class TagAutocompleteField extends StatefulWidget {
  const TagAutocompleteField({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggestions = const [],
    this.width = 140,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final double? width;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final TagSubmitted? onSubmitted;

  @override
  State<TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<TagAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.join(', '));
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(TagAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.value.join(', ');
    if (!_focusNode.hasFocus && _controller.text != text) {
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commitCurrentToken();
  }

  String get _currentToken {
    final text = _controller.text;
    final lastSeparator = text.lastIndexOf(RegExp(r'[,#\s]'));
    return text.substring(lastSeparator + 1).trim();
  }

  List<String> _parse(String raw) {
    return raw
        .split(RegExp(r'[,#\s]+'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name.length <= 20)
        .fold<List<String>>([], (items, name) {
          if (!items.contains(name)) items.add(name);
          return items;
        });
  }

  void _setTags(List<String> tags, {bool readyForNext = false}) {
    widget.onChanged(tags);
    _controller.text = readyForNext && tags.isNotEmpty
        ? '${tags.join(', ')}, '
        : tags.join(', ');
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Iterable<String> _matches(String token, Set<String> selected) {
    final lower = token.toLowerCase();
    return widget.suggestions
        .where((tag) => !selected.contains(tag))
        .where((tag) => lower.isEmpty || tag.toLowerCase().contains(lower))
        .take(8);
  }

  TagSubmitResult _commitCurrentToken() {
    final current = _controller.text;
    final tags = _parse(current);
    final token = _currentToken;
    if (token.isEmpty) {
      _setTags(tags);
      return TagSubmitResult.empty;
    }
    if (token.length > 20) {
      return TagSubmitResult.none;
    }

    final selected = tags.toSet()..remove(token);
    final exact = widget.suggestions.firstWhere(
      (tag) => tag.toLowerCase() == token.toLowerCase(),
      orElse: () => '',
    );
    final first = exact.isNotEmpty
        ? exact
        : _matches(token, selected).cast<String?>().firstOrNull;
    final nextTag = first != null && first.isNotEmpty ? first : token;
    final next = [...selected];
    if (!next.contains(nextTag)) next.add(nextTag);
    _setTags(next, readyForNext: true);
    return TagSubmitResult.added;
  }

  @override
  Widget build(BuildContext context) {
    final field = RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final token = _currentToken.toLowerCase();
        final selected = _parse(textEditingValue.text).toSet();
        return _matches(token, selected);
      },
      onSelected: (suggestion) {
        final tags = _parse(_controller.text);
        if (!tags.contains(suggestion)) tags.add(suggestion);
        _setTags(tags, readyForNext: true);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          key: const ValueKey('desktop-transactions-inline-tag'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          decoration: const InputDecoration(
            hintText: '\uD0DC\uADF8',
            isDense: true,
            prefixText: '#',
            suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.contains(',') || value.contains('#')) {
              widget.onChanged(_parse(value));
            }
          },
          onSubmitted: (_) {
            if (_currentToken.isEmpty) {
              widget.onSubmitted?.call(_commitCurrentToken());
              return;
            }
            final before = _controller.text;
            onFieldSubmitted();
            if (_controller.text != before) {
              widget.onSubmitted?.call(TagSubmitResult.added);
              return;
            }
            widget.onSubmitted?.call(_commitCurrentToken());
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsSurface<String>(
          width: widget.width ?? 180,
          options: options.toList(),
          onSelected: onSelected,
          itemBuilder: (context, tag, highlighted) =>
              _OptionTile(label: '#$tag', highlighted: highlighted),
        );
      },
    );
    if (widget.width == null) return field;
    return SizedBox(width: widget.width, child: field);
  }
}

class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggestions = const [],
  });

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final names = raw
        .split(RegExp(r'[,#\s]+'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name.length <= 20);
    final next = [...widget.value];
    for (final name in names) {
      if (!next.contains(name)) next.add(name);
    }
    widget.onChanged(next);
    _ctrl.clear();
    setState(() {});
  }

  void _remove(String name) {
    widget.onChanged(widget.value.where((t) => t != name).toList());
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    final matches = widget.suggestions
        .where((s) => !widget.value.contains(s))
        .where((s) => query.isEmpty || s.contains(query))
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...widget.value.map(
              (t) => InputChip(label: Text('#$t'), onDeleted: () => _remove(t)),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  hintText: '\uD0DC\uADF8 \uCD94\uAC00',
                  isDense: true,
                  prefixText: '#',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _add,
                onEditingComplete: () {
                  if (_ctrl.text.trim().isNotEmpty) _add(_ctrl.text);
                },
              ),
            ),
          ],
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              children: matches
                  .map(
                    (s) => ActionChip(
                      label: Text(
                        '#$s',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.desktopMuted,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _add(s),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
