import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';

/// Search field: magnifier, placeholder, clear button. Esc clears the text,
/// a second Esc gives focus back.
class MMSearchField extends StatefulWidget {
  const MMSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onEscape,
    this.height = MMSizes.field,
    this.filled = true,
  });

  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Replaces the default Esc behavior (clear, then give focus back).
  final VoidCallback? onEscape;
  final double height;
  final bool filled;

  @override
  State<MMSearchField> createState() => _MMSearchFieldState();
}

class _MMSearchFieldState extends State<MMSearchField> {
  TextEditingController? _own;
  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(MMSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_onText);
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.onEscape != null) {
            widget.onEscape!();
          } else if (_controller.text.isNotEmpty) {
            _clear();
          } else {
            _focus.unfocus();
          }
        },
      },
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: widget.filled
            ? BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(MMRadii.field))
            : null,
        child: Row(
          children: [
            Icon(MMIcons.search, size: 14, color: c.secondaryLabel),
            const SizedBox(width: 6),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: t.body,
                  cursorWidth: 1.5,
                  cursorHeight: 15,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration.collapsed(hintText: widget.placeholder, hintStyle: t.bodySecondary),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: _clear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(MMIcons.clear, size: 14, color: c.secondaryLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Single-line text input for forms (height 28, focus ring in accent).
class MMTextField extends StatefulWidget {
  const MMTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<MMTextField> createState() => _MMTextFieldState();
}

class _MMTextFieldState extends State<MMTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final focused = _focus.hasFocus;
    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: Container(
        height: MMSizes.field,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.quaternaryFill,
          borderRadius: BorderRadius.circular(MMRadii.field),
          border: Border.all(color: focused ? c.accent : Colors.transparent, width: 1),
          boxShadow: focused ? [BoxShadow(color: c.accentTint, spreadRadius: 3)] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: t.body,
            cursorWidth: 1.5,
            cursorHeight: 15,
            decoration: InputDecoration.collapsed(hintText: widget.placeholder, hintStyle: t.bodySecondary),
          ),
        ),
      ),
    );
  }
}
