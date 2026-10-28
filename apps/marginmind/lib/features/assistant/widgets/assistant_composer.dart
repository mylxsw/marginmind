import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';
import '../../../settings/settings_window.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_settings.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../../../app/providers.dart';
import '../assistant_settings.dart';
import 'assistant_context_summary.dart';
import 'assistant_model_menu.dart';
import 'assistant_overlays.dart';

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
  late final VoiceController _voice;
  TextEditingValue? _voiceDraft;
  String _voiceText = '';
  bool _applyingVoice = false;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceControllerFactoryProvider)()..addListener(_voiceChanged);
    _text.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.configured) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(AssistantComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studySetId != widget.studySetId || (oldWidget.configured && !widget.configured)) {
      _cancelVoice();
    }
    if (!oldWidget.configured && widget.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.configured) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  AppLocalizations get _l => context.l10n;

  void _voiceChanged() {
    if (!mounted) return;
    final draft = _voiceDraft;
    if (draft != null && _voice.text != _voiceText) {
      _voiceText = _voice.text;
      final selection = draft.selection.isValid ? draft.selection : TextSelection.collapsed(offset: draft.text.length);
      final value = draft.text.replaceRange(selection.start, selection.end, _voiceText);
      _applyingVoice = true;
      _text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: selection.start + _voiceText.length),
      );
      _applyingVoice = false;
    }
    setState(() {});
    if (!_voice.active && ref.read(workspaceProvider(widget.studySetId)).panel == RightPanel.assistant) {
      _focus.requestFocus();
    }
  }

  Future<void> _toggleVoice() async {
    if (_voice.phase == VoicePhase.recording) {
      await _voice.finish();
      return;
    }
    if (_voice.active) return;
    final settings = ref.read(voiceSettingsProvider);
    if (settings.provider == VoiceProvider.none) {
      await showSettings(context, tab: SettingsTab.voice);
      return;
    }
    _voiceDraft = _text.value;
    _voiceText = '';
    if (_slash.isShowing) _slash.hide();
    final secrets = ref.read(assistantSecretsProvider);
    await _voice.start(settings, () => voiceKey(secrets, settings));
  }

  void _cancelVoice() {
    if (!_voice.active) return;
    final draft = _voiceDraft;
    _voiceDraft = null;
    unawaited(_voice.cancel());
    if (draft != null) _text.value = draft;
  }

  String? get _voiceError => switch (_voice.error) {
    null => null,
    VoiceError.permission => _l.voicePermissionError,
    VoiceError.configuration => _l.voiceConfigurationError,
    VoiceError.connection => _l.voiceConnectionError,
    VoiceError.recording => _l.voiceRecordingError,
    VoiceError.timeout => _l.voiceTimeoutError,
    VoiceError.empty => _l.voiceEmptyError,
  };

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
    if (!_applyingVoice && value.length == _previous.length + 1 && !_text.value.composing.isValid) {
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
    final commands = _voice.active ? const <AssistantSkill>[] : _commands;
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
    if (_voice.active) {
      if (key == LogicalKeyboardKey.escape) {
        _cancelVoice();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter && !shift) {
        unawaited(_voice.finish());
        return KeyEventResult.handled;
      }
    }
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
    if (!widget.configured || _voice.active) return;
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

  Future<void> _moreActions(BuildContext button) async {
    final chosen = await showPopupMenu<AssistantSkill>(
      context,
      anchor: boundsOf(button),
      items: [
        for (final s in AssistantSkill.values.take(6))
          if (s != AssistantSkill.explain && s != AssistantSkill.summarize) PopupItem(s, s.label(_l), icon: s.icon),
      ],
    );
    if (!mounted) return;
    if (chosen != null) _send(chosen.prompt(_l), chosen.name);
    _focus.requestFocus();
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
    ref.listen(assistantControllerProvider.select((s) => s.id), (_, _) => _cancelVoice());
    ref.listen(workspaceProvider(widget.studySetId).select((s) => s.panel), (_, panel) {
      if (panel != RightPanel.assistant && _voice.active) {
        _voiceDraft = null;
        unawaited(_voice.cancel());
      }
    });
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
    final canSend = configured && !elsewhere && !_voice.active && _text.text.trim().isNotEmpty;
    final commands = _slash.isShowing ? _commands : const <AssistantSkill>[];

    final composer = CompositedTransformTarget(
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
              if (configured && quick && _text.text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: MMSpacing.xs),
                  child: Row(
                    children: [
                      for (final s in [AssistantSkill.explain, AssistantSkill.summarize])
                        _QuickAction(
                          key: ValueKey('quick-${s.name}'),
                          label: s.label(l),
                          icon: s.icon,
                          onPressed: running || elsewhere || _voice.active ? null : () => _send(s.prompt(l), s.name),
                        ),
                      Builder(
                        builder: (button) => _QuickAction(
                          key: const ValueKey('quick-more'),
                          label: l.assistantMoreActions,
                          icon: MMIcons.chevronDown,
                          trailing: true,
                          onPressed: running || elsewhere || _voice.active ? null : () => _moreActions(button),
                        ),
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
                    if (_voice.active || _voiceError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _voice.active
                                      ? switch (_voice.phase) {
                                          VoicePhase.connecting => l.voiceConnecting,
                                          VoicePhase.recording => l.voiceListening,
                                          _ => l.voiceFinishing,
                                        }
                                      : _voiceError!,
                                  key: const ValueKey('assistant-voice-status'),
                                  style: t.footnote.copyWith(color: _voice.active ? c.secondaryLabel : c.critical),
                                ),
                              ),
                            ),
                            if (_voice.active)
                              _BarButton(
                                key: const ValueKey('assistant-voice-cancel'),
                                icon: MMIcons.close,
                                tooltip: l.voiceCancel,
                                onPressed: _cancelVoice,
                              ),
                            if (!_voice.active && _voice.error != VoiceError.empty)
                              _BarButton(
                                icon: MMIcons.settings,
                                tooltip: l.settingsVoice,
                                onPressed: () => unawaited(showSettings(context, tab: SettingsTab.voice)),
                              ),
                          ],
                        ),
                      ),
                    if (configured && chips.isNotEmpty)
                      AssistantContextSummary(
                        key: ValueKey('composer-contexts-${conversation.id}-${conversation.messages.length}'),
                        items: chips,
                        outgoing: outgoing,
                        onChange: (item) =>
                            item.auto ? uiNotifier.toggleAuto(item.id) : uiNotifier.removeContext(item.id),
                      ),
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
                              readOnly: _voice.active,
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
                            onPressed: configured && !_voice.active ? _mention : null,
                          ),
                          _BarButton(
                            key: const ValueKey('assistant-slash'),
                            icon: MMIcons.command,
                            tooltip: '${l.assistantCommands}（/）',
                            onPressed: configured && !_voice.active
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
                          _BarButton(
                            key: const ValueKey('assistant-voice'),
                            icon: _voice.phase == VoicePhase.recording ? MMIcons.stop : MMIcons.microphone,
                            tooltip: _voice.phase == VoicePhase.recording ? l.voiceFinish : l.settingsVoice,
                            color: _voice.active ? c.research : null,
                            onPressed: configured && (!_voice.active || _voice.phase == VoicePhase.recording)
                                ? () => unawaited(_toggleVoice())
                                : null,
                          ),
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
    return Actions(
      actions: {
        VoiceInputIntent: CallbackAction<VoiceInputIntent>(
          onInvoke: (_) {
            if (widget.configured) unawaited(_toggleVoice());
            return null;
          },
        ),
      },
      child: composer,
    );
  }
}

/// A quiet shortcut: emphasis appears only while pointing at or focusing it.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.trailing = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, s) {
        final active = s.hovered || s.focused || s.pressed;
        final fg = active ? c.research : c.secondaryLabel;
        return Opacity(
          opacity: s.enabled ? 1 : .4,
          child: Container(
            height: MMSizes.field,
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
            decoration: BoxDecoration(
              color: active ? c.researchTint : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!trailing) ...[Icon(icon, size: MMSpacing.m, color: fg), const SizedBox(width: MMSpacing.xs)],
                Text(label, style: context.mmText.callout.copyWith(color: fg)),
                if (trailing) ...[const SizedBox(width: MMSpacing.xs), Icon(icon, size: MMSpacing.m, color: fg)],
              ],
            ),
          ),
        );
      },
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
