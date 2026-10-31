import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../full_translation.dart';

/// Paragraph actions share the document/language scheduler with the full job.
class TranslationParagraphView extends ConsumerStatefulWidget {
  const TranslationParagraphView({
    super.key,
    required this.studySetId,
    required this.language,
    required this.paragraph,
    required this.value,
    required this.style,
    required this.placeholder,
    required this.contextMenuBuilder,
  });
  final String studySetId, language;
  final TranslationParagraph paragraph;
  final String? value;
  final TextStyle style;
  final Widget placeholder;
  final Widget Function(BuildContext, EditableTextState) contextMenuBuilder;

  @override
  ConsumerState<TranslationParagraphView> createState() => _TranslationParagraphViewState();
}

class _TranslationParagraphViewState extends ConsumerState<TranslationParagraphView> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _hide;
  bool _editing = false, _busy = false;

  (String, String, String) get _key => (widget.studySetId, widget.paragraph.documentId, widget.language);
  FullTranslationController get _controller => ref.read(fullTranslationProvider(_key).notifier);

  void _show() {
    _hide?.cancel();
    final segment = ref.read(fullTranslationProvider(_key)).segments[textKey(widget.paragraph.text, widget.language)];
    if (!_editing && segment != null) _overlay.show();
  }

  void _leave() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _overlay.hide();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit() {
    _hide?.cancel();
    _overlay.hide();
    _text.text = widget.value!;
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  Future<void> _save() => _run(() async {
    if (_text.text.trim().isEmpty) return;
    await _controller.editParagraph(widget.paragraph, _text.text);
    if (mounted) {
      setState(() => _editing = false);
      MMHud.show(context, context.l10n.translationEditSaved);
    }
  });

  Future<void> _copy() => _run(() async {
    await Clipboard.setData(ClipboardData(text: widget.value!));
    if (mounted) MMHud.show(context, context.l10n.translationCopied);
  });

  Future<void> _retranslate() => _run(() async {
    final scope = _key;
    final undo = await _controller.retranslateParagraph(widget.paragraph);
    if (!mounted || scope != _key) return;
    if (undo == null) {
      MMHud.show(context, context.l10n.somethingWentWrong);
    } else {
      MMHud.show(
        context,
        context.l10n.translationRetranslated,
        action: (
          context.l10n.undo,
          () => unawaited(
            undo().catchError((Object _) {
              if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
            }),
          ),
        ),
      );
    }
  });

  @override
  void didUpdateWidget(covariant TranslationParagraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.studySetId, oldWidget.paragraph.documentId, oldWidget.language) != _key ||
        oldWidget.paragraph.fingerprint != widget.paragraph.fingerprint) {
      _hide?.cancel();
      _overlay.hide();
      _editing = false;
      _text.clear();
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fullTranslationProvider(_key));
    final p = widget.paragraph, l = context.l10n, c = context.mmColors;
    final edited = state.segments[textKey(p.text, widget.language)]?.origin == TranslationOrigin.edited;
    final failed = widget.value == null && state.segmentState(p) == TranslationSegmentState.failed;
    if (_editing) {
      return Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (!_busy) setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          if ((event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
              _text.value.composing.isCollapsed) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              if (!_busy) {
                final selection = _text.selection;
                final start = selection.isValid ? selection.start : _text.text.length;
                final end = selection.isValid ? selection.end : start;
                _text.value = TextEditingValue(
                  text: _text.text.replaceRange(start, end, '\n'),
                  selection: TextSelection.collapsed(offset: start + 1),
                );
              }
            } else {
              unawaited(_save());
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          key: ValueKey('translation-editor-${p.index}'),
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          readOnly: _busy,
          maxLines: null,
          style: widget.style,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(6)),
        ),
      );
    }
    if (failed) {
      final kind = state.job?.failures[p.fingerprint]?.kind;
      final reason = switch (kind) {
        'protocol' => l.researchErrorProtocol,
        'refusal' => l.researchErrorRefusal,
        'timeout' => l.researchErrorTimeout,
        _ => l.researchErrorUnavailable,
      };
      return Container(
        key: ValueKey('translation-failed-${p.index}'),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: c.critical.withValues(alpha: .08),
          border: Border(left: BorderSide(color: c.critical, width: 2)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.body.copyWith(
                fontSize: 12.5,
                height: 1.7,
                color: widget.style.color?.withValues(alpha: .65) ?? c.secondaryLabel,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(MMIcons.warning, size: 12, color: c.critical),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.translationParagraphFailed(reason),
                    style: context.mmText.footnote.copyWith(color: c.critical),
                  ),
                ),
                MMButton(
                  label: l.assistantRetry,
                  variant: MMButtonVariant.plain,
                  icon: MMIcons.retry,
                  color: c.critical,
                  onPressed: _busy ? null : () => _run(() => _controller.retry(p)),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (widget.value == null) return widget.placeholder;
    return MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _leave(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (_) => Positioned.fill(
            child: Align(
              alignment: Alignment.topLeft,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                child: MouseRegion(
                  onEnter: (_) => _show(),
                  onExit: (_) => _leave(),
                  child: MMGlass(
                    child: SizedBox(
                      key: ValueKey('translation-tools-${p.index}'),
                      height: 28,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MMIconButton(
                            icon: MMIcons.retry,
                            tooltip: l.translationRetranslate,
                            size: 24,
                            iconSize: 14,
                            onPressed: _busy ? null : _retranslate,
                          ),
                          MMIconButton(
                            icon: MMIcons.pen,
                            tooltip: l.translationEdit,
                            size: 24,
                            iconSize: 14,
                            onPressed: _busy ? null : _edit,
                          ),
                          MMIconButton(
                            icon: MMIcons.copy,
                            tooltip: l.copyAction,
                            size: 24,
                            iconSize: 14,
                            onPressed: _copy,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SelectableText(
                  widget.value!,
                  style: widget.style,
                  contextMenuBuilder: widget.contextMenuBuilder,
                ),
              ),
              if (edited)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Tooltip(
                    message: l.translationEdited,
                    child: Icon(
                      MMIcons.pen,
                      key: ValueKey('translation-edited-${p.index}'),
                      size: 12,
                      color: widget.style.color?.withValues(alpha: .5) ?? c.secondaryLabel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
