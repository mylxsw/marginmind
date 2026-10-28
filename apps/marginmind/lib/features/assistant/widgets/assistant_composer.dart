import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../../../app/providers.dart';
import '../assistant_settings.dart';
import 'assistant_messages.dart' show contextIcon, contextLabel;
import 'assistant_model_menu.dart';
import 'assistant_overlays.dart';
import 'dashed_border.dart';

/// The input at the bottom of the panel: attached context, quick actions,
/// the question, and the online / model / send controls.
class AssistantComposer extends ConsumerStatefulWidget {
  const AssistantComposer({super.key, required this.studySetId, required this.configured});

  final String studySetId;
  final bool configured;

  @override
  ConsumerState<AssistantComposer> createState() => _AssistantComposerState();
}

class _AssistantComposerState extends ConsumerState<AssistantComposer> {
  final _text = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _key);
  final _slash = OverlayPortalController();
  final _link = LayerLink();
  final _mentionButton = GlobalKey();
  int _slashAt = 0;
  String _previous = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.configured) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(AssistantComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.configured && widget.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.configured) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  AppLocalizations get _l => context.l10n;

  /// `/` commands matching what follows the slash at the start of the input.
  List<AssistantSkill> get _commands {
    final m = RegExp(r'^/(\S*)$').firstMatch(_text.text);
    if (m == null) return const [];
    final query = m[1]!.toLowerCase();
    return [
      for (final s in AssistantSkill.values)
        if (s.command(_l).toLowerCase().startsWith(query) || s.name.startsWith(query)) s,
    ];
  }

  void _changed() {
    final value = _text.text;
    // A typed "@" opens the reference menu and does not stay in the text.
    if (value.length == _previous.length + 1 && !_text.value.composing.isValid) {
      final at = _text.selection.baseOffset - 1;
      if (at >= 0 && at < value.length && value[at] == '@') {
        _previous = value.replaceRange(at, at + 1, '');
        _text.value = TextEditingValue(
          text: _previous,
          selection: TextSelection.collapsed(offset: at),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => _mention());
        return;
      }
    }
    _previous = value;
    final commands = _commands;
    if (commands.isEmpty) {
      if (_slash.isShowing) _slash.hide();
    } else {
      _slashAt = _slashAt.clamp(0, commands.length - 1);
      if (!_slash.isShowing) _slash.show();
    }
    setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final commands = _slash.isShowing ? _commands : const <AssistantSkill>[];
    if (commands.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        setState(
          () =>
              _slashAt = (_slashAt + (key == LogicalKeyboardKey.arrowDown ? 1 : commands.length - 1)) % commands.length,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _command(commands[_slashAt]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _slash.hide();
        setState(() {});
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter && !shift) {
      // Return while an input method is composing commits the text only.
      if (_text.value.composing.isValid) return KeyEventResult.ignored;
      _send();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && ref.read(assistantControllerProvider).running) {
      unawaited(ref.read(assistantControllerProvider.notifier).stop());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _send([String? text, String? skill]) {
    if (!widget.configured) return;
    final value = text ?? _text.text;
    if (value.trim().isEmpty || ref.read(assistantControllerProvider.notifier).busy) return;
    assistantSend(ref, widget.studySetId, _l, value, skill: skill);
    if (text == null) _text.clear();
  }

  /// A `/` command: sent at once about the attached context, else left in
  /// the input to be completed.
  void _command(AssistantSkill skill) {
    _slash.hide();
    final contexts = outgoingContexts(
      ref.read(assistantUiProvider(widget.studySetId)),
      ref.read(assistantAutoContextsProvider(widget.studySetId)),
    );
    if (contexts.isNotEmpty) {
      _text.clear();
      _send(skill.prompt(_l), skill.name);
    } else {
      final value = '/${skill.command(_l)} ';
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      _focus.requestFocus();
    }
  }

  Future<void> _mention() async {
    final box = _mentionButton.currentContext;
    if (box == null) return;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final state = ref.read(workspaceProvider(widget.studySetId));
    final content = workspace.content;
    final doc = state.activeDocumentId == null ? null : content.document(state.activeDocumentId!);
    final page = doc == null ? null : (ref.read(readingPagesProvider(widget.studySetId))[doc.id] ?? doc.lastPage);
    final mapId = state.activeMapId;
    final items = <PopupItem<ContextItem>>[
      if (doc != null && page != null)
        PopupItem(
          pageContext(document: doc, page: page),
          _l.assistantCurrentPage(page),
          icon: MMIcons.document,
        ),
      for (final d in content.documents) PopupItem(documentContext(d), d.title, icon: MMIcons.document),
      for (final n in content.childrenOf(null, mapId: mapId))
        PopupItem(
          nodeContext(mapId: mapId, nodeId: n.cardId, title: researchCardTitle(content, n.cardId), branch: true),
          researchCardTitle(content, n.cardId),
          icon: MMIcons.mindMap,
        ),
      PopupItem(
        mapContext(mapId: mapId, title: mapTitle(ref, widget.studySetId, mapId)),
        _l.assistantWholeMap,
        icon: MMIcons.mindMap,
      ),
    ];
    final chosen = await showPopupMenu<ContextItem>(context, anchor: boundsOf(box), items: items);
    if (chosen != null) ref.read(assistantUiProvider(widget.studySetId).notifier).addContext(chosen);
    if (mounted) _focus.requestFocus();
  }

  /// The toggle is remembered for the study set's next conversations.
  Future<void> _setOnline(bool online) async {
    await ref.read(sharedPreferencesProvider).setBool(assistantOnlineKey(widget.studySetId), online);
    await ref.read(assistantControllerProvider.notifier).setOnline(online);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final ui = ref.watch(assistantUiProvider(widget.studySetId));
    final auto = ref.watch(assistantAutoContextsProvider(widget.studySetId));
    final conversation = ref.watch(assistantControllerProvider);
    final running = conversation.running;
    final uiNotifier = ref.read(assistantUiProvider(widget.studySetId).notifier);
    ref.listen(assistantUiProvider(widget.studySetId).select((s) => s.focusTick), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    });
    final configured = widget.configured;
    final outgoing = outgoingContexts(ui, auto);
    final chips = [
      ...ui.contexts,
      for (final a in auto)
        if (!ui.contexts.any(
          (c) => c.kind == a.kind && c.nodeId == a.nodeId && c.documentId == a.documentId && c.page == a.page,
        ))
          a,
    ];
    final quick = outgoing.any(
      (c) => c.kind == ContextKind.selection || c.kind == ContextKind.node || c.kind == ContextKind.branch,
    );
    // One answer at a time per study set: another conversation is answering.
    final elsewhere = ref.watch(assistantBackgroundProvider) != null;
    final canSend = configured && !elsewhere && _text.text.trim().isNotEmpty;
    final commands = _slash.isShowing ? _commands : const <AssistantSkill>[];

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _slash,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(10, -4),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: (_link.leaderSize?.width ?? 300) - 20,
              child: commands.isEmpty
                  ? const SizedBox.shrink()
                  : PopupList<AssistantSkill>(
                      key: const ValueKey('assistant-slash-menu'),
                      items: [for (final s in commands) PopupItem(s, '/${s.command(l)}', icon: s.icon)],
                      highlighted: _slashAt,
                      onHover: (i) => setState(() => _slashAt = i),
                      onSelected: _command,
                    ),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, MMSpacing.s, 10, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.separator)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (configured && chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final item in chips)
                        _ContextChip(
                          key: ValueKey('context-chip-${item.id}'),
                          item: item,
                          off: item.auto && ui.suppressed.contains(item.id),
                          onRemove: () =>
                              item.auto ? uiNotifier.toggleAuto(item.id) : uiNotifier.removeContext(item.id),
                        ),
                    ],
                  ),
                ),
              if (configured && quick)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final s in AssistantSkill.values.take(6))
                        _QuickAction(
                          key: ValueKey('quick-${s.name}'),
                          skill: s,
                          onPressed: running ? null : () => _send(s.prompt(l), s.name),
                        ),
                    ],
                  ),
                ),
              AnimatedContainer(
                duration: MMMotion.quick,
                curve: MMMotion.quickCurve,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _focus.hasFocus ? c.research : c.separator),
                  boxShadow: _focus.hasFocus ? [BoxShadow(color: c.researchTint, spreadRadius: 3)] : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40 - 14, maxHeight: 140),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(MMSpacing.m, MMSpacing.s, MMSpacing.s, 6),
                        child: Semantics(
                          textField: true,
                          label: configured ? l.assistantPlaceholder : l.assistantConnectFirst,
                          child: Material(
                            type: MaterialType.transparency,
                            child: TextField(
                              key: const ValueKey('assistant-input'),
                              controller: _text,
                              focusNode: _focus,
                              enabled: configured,
                              minLines: 1,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: t.body.copyWith(height: 20 / 13, color: c.label),
                              cursorWidth: 1.5,
                              cursorColor: c.research,
                              decoration: InputDecoration.collapsed(
                                hintText: configured ? l.assistantPlaceholder : l.assistantConnectFirst,
                                hintStyle: t.bodySecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      child: Row(
                        children: [
                          _BarButton(
                            key: _mentionButton,
                            icon: MMIcons.mention,
                            tooltip: '${l.assistantMention}（@）',
                            onPressed: configured ? _mention : null,
                          ),
                          _BarButton(
                            key: const ValueKey('assistant-slash'),
                            icon: MMIcons.command,
                            tooltip: '${l.assistantCommands}（/）',
                            onPressed: configured
                                ? () {
                                    _text.value = const TextEditingValue(
                                      text: '/',
                                      selection: TextSelection.collapsed(offset: 1),
                                    );
                                    _focus.requestFocus();
                                  }
                                : null,
                          ),
                          _BarButton(
                            key: const ValueKey('assistant-online'),
                            icon: MMIcons.web,
                            label: conversation.online ? l.assistantOnline : l.assistantOffline,
                            color: conversation.online ? c.research : c.secondaryLabel,
                            tooltip: conversation.online ? l.assistantOnline : l.assistantOffline,
                            selected: conversation.online,
                            onPressed: configured ? () => unawaited(_setOnline(!conversation.online)) : null,
                          ),
                          const Spacer(),
                          if (configured)
                            Builder(
                              builder: (button) => _BarButton(
                                key: const ValueKey('assistant-model'),
                                label: conversationModelLabel(ref, conversation.model),
                                trailing: MMIcons.chevronDown,
                                tooltip: l.assistantModel,
                                maxLabel: 120,
                                onPressed: () => showModelMenu(context, ref, boundsOf(button)),
                              ),
                            ),
                          const SizedBox(width: MMSpacing.xs),
                          _SendButton(
                            running: running,
                            enabled: canSend,
                            onSend: () => _send(),
                            onStop: () => unawaited(ref.read(assistantControllerProvider.notifier).stop()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({super.key, required this.item, required this.off, required this.onRemove});

  final ContextItem item;

  /// An automatic chip left out of the next message.
  final bool off;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final selection = item.kind == ContextKind.selection;
    final (Color bg, Color fg) = item.auto
        ? (Colors.transparent, c.secondaryLabel)
        : selection
        ? (c.accentTint, c.accent)
        : (c.researchTint, c.research);
    var label = contextLabel(l, item);
    if (selection && label.runes.length > 22) label = '${String.fromCharCodes(label.runes.take(22))}…';
    final chip = Container(
      height: 24,
      padding: const EdgeInsets.only(left: MMSpacing.s, right: MMSpacing.xs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(contextIcon(item), size: 12, color: fg),
          const SizedBox(width: MMSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.callout.copyWith(color: fg, decoration: off ? TextDecoration.lineThrough : null),
            ),
          ),
          const SizedBox(width: 2),
          MMIconButton(
            key: ValueKey('context-remove-${item.id}'),
            icon: MMIcons.close,
            iconSize: 10,
            size: 18,
            color: fg,
            tooltip: l.assistantRemoveContext,
            onPressed: onRemove,
          ),
        ],
      ),
    );
    if (!item.auto) return Semantics(label: label, child: chip);
    return Tooltip(
      message: l.assistantAutoContext,
      child: CustomPaint(
        foregroundPainter: DashedBorderPainter(color: c.separator, radius: 8),
        child: Semantics(label: '$label, ${l.assistantAutoContext}', child: chip),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({super.key, required this.skill, required this.onPressed});

  final AssistantSkill skill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final label = skill.label(context.l10n);
    return MMInteractive(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, s) => AnimatedOpacity(
        duration: MMMotion.quick,
        opacity: s.enabled ? 1 : .4,
        child: AnimatedContainer(
          duration: MMMotion.quick,
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: s.hovered ? c.researchTint : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.research.withValues(alpha: .16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(skill.icon, size: 12, color: c.research),
              const SizedBox(width: MMSpacing.xs),
              Text(label, style: context.mmText.callout.copyWith(color: c.research)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 26pt control in the input's bottom row.
class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    this.icon,
    this.label,
    this.trailing,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.maxLabel = 160,
  });

  final IconData? icon;
  final String? label;
  final IconData? trailing;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;
  final double maxLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: label ?? tooltip,
      semanticValue: selected ? '✓' : null,
      builder: (context, s) {
        final fg = s.enabled ? (color ?? c.icon) : c.icon.withValues(alpha: .3);
        return AnimatedContainer(
          duration: MMMotion.quick,
          height: 26,
          constraints: const BoxConstraints(minWidth: 26),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 6),
          decoration: BoxDecoration(
            color: s.hovered ? c.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 14, color: fg),
              if (icon != null && label != null) const SizedBox(width: MMSpacing.xs),
              if (label != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabel),
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mmText.callout.copyWith(color: color ?? c.secondaryLabel),
                  ),
                ),
              if (trailing != null) ...[const SizedBox(width: 3), Icon(trailing, size: 10, color: c.icon)],
            ],
          ),
        );
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.running, required this.enabled, required this.onSend, required this.onStop});

  final bool running, enabled;
  final VoidCallback onSend, onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    return MMInteractive(
      key: ValueKey(running ? 'assistant-stop' : 'assistant-send'),
      onTap: running ? onStop : (enabled ? onSend : null),
      tooltip: running ? '${l.assistantStop}（Esc）' : '${l.assistantSend}（↩）',
      semanticLabel: running ? l.assistantStop : l.assistantSend,
      builder: (context, s) => AnimatedOpacity(
        duration: MMMotion.quick,
        opacity: running || enabled ? 1 : .35,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: running ? c.label : c.research, shape: BoxShape.circle),
          child: Icon(
            running ? MMIcons.stop : MMIcons.send,
            size: running ? 10 : 14,
            color: running ? c.windowBackground : c.onAccent,
          ),
        ),
      ),
    );
  }
}
