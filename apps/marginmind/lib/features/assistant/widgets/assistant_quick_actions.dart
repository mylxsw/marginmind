import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../assistant_settings.dart';
import 'assistant_messages.dart';
import 'assistant_overlays.dart';
import 'assistant_panel.dart' show ModelSetupCard;

/// A transparent, selection-preserving route. Its content stays inside the
/// reader; clicking outside or Escape closes it without cancelling the answer.
Future<bool?> showAssistantQuickActions(
  BuildContext context, {
  required String studySetId,
  PendingAction? pending,
  required ContextItem passage,
  SourceAnchor? source,
  required Rect toolbar,
  required Rect selection,
  required Rect viewport,
  List<ContextItem> contexts = const [],
  ({String mapId, String? parentId})? insertionTarget,
  PanelOrigin origin = PanelOrigin.reader,
}) => showGeneralDialog<bool>(
  context: context,
  barrierColor: Colors.transparent,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: MMAppearance.duration(context, MMMotion.quick),
  pageBuilder: (_, _, _) => inScope(
    context,
    CustomSingleChildLayout(
      delegate: QuickActionsPlacement(toolbar: toolbar, selection: selection, viewport: viewport),
      child: AssistantQuickActions(
        studySetId: studySetId,
        pending: pending,
        passage: passage,
        source: source,
        contexts: contexts,
        insertionTarget: insertionTarget,
        origin: origin,
      ),
    ),
  ),
  transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

/// Keeps the toolbar in place and puts the answer below it, or above the
/// selection if that side has more room. Long answers scroll inside the card.
class QuickActionsPlacement extends SingleChildLayoutDelegate {
  QuickActionsPlacement({required this.toolbar, required this.selection, required this.viewport});

  final Rect toolbar, selection, viewport;

  Rect _bounds(Size size) => viewport.intersect(Offset.zero & size).deflate(8);
  double _bottom(Rect bounds) {
    final belowSelection = math.max(toolbar.bottom, selection.bottom) + 8;
    final belowToolbar = toolbar.bottom + 8;
    // A tall selection can leave only a sliver for the answer. In that case
    // anchor to the toolbar so the actions and answer remain usable.
    return bounds.bottom - belowSelection < 400 && bounds.bottom - belowToolbar >= 400 ? belowToolbar : belowSelection;
  }

  double get _top => math.min(toolbar.top, selection.top) - 8;
  bool _below(Rect bounds) =>
      bounds.bottom - _bottom(bounds) >= 460 || bounds.bottom - _bottom(bounds) >= _top - bounds.top;
  double _room(Rect bounds) => _below(bounds) ? bounds.bottom - _bottom(bounds) : _top - bounds.top;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    final width = math.min(408.0, math.max(0.0, bounds.width));
    final room = _room(bounds);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.min(540, math.max(0, room >= 240 ? room : bounds.height)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _bounds(size);
    final x = (toolbar.right - childSize.width).clamp(
      bounds.left,
      math.max(bounds.left, bounds.right - childSize.width),
    );
    final y = _below(bounds) ? _bottom(bounds) : _top - childSize.height;
    return Offset(x.toDouble(), y.clamp(bounds.top, math.max(bounds.top, bounds.bottom - childSize.height)));
  }

  @override
  bool shouldRelayout(QuickActionsPlacement old) =>
      old.toolbar != toolbar || old.selection != selection || old.viewport != viewport;
}

enum _QuickAction {
  explain(AssistantSkill.explain),
  translate(AssistantSkill.translate),
  summarize(AssistantSkill.summarize),
  outline(null),
  verify(AssistantSkill.verify),
  quiz(AssistantSkill.quiz);

  const _QuickAction(this.skill);
  final AssistantSkill? skill;
  IconData get icon => skill?.icon ?? MMIcons.organize;
  String title(AppLocalizations l) => switch (this) {
    explain => l.assistantQuickExplain,
    summarize => l.assistantQuickSummarize,
    outline => l.assistantQuickOutline,
    _ => skill!.label(l),
  };
  String prompt(AppLocalizations l) => skill?.prompt(l) ?? l.assistantQuickOutlinePrompt;
}

class AssistantQuickActions extends ConsumerStatefulWidget {
  const AssistantQuickActions({
    super.key,
    required this.studySetId,
    this.pending,
    required this.passage,
    this.source,
    this.contexts = const [],
    this.insertionTarget,
    this.origin = PanelOrigin.reader,
  });

  final String studySetId;
  final PendingAction? pending;
  final ContextItem passage;
  final SourceAnchor? source;
  final List<ContextItem> contexts;
  final ({String mapId, String? parentId})? insertionTarget;
  final PanelOrigin origin;

  @override
  ConsumerState<AssistantQuickActions> createState() => _AssistantQuickActionsState();
}

class _AssistantQuickActionsState extends ConsumerState<AssistantQuickActions> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String get _contextKey {
    if (widget.contexts.length < 2) return widget.passage.id;
    final ids = widget.contexts.map((item) => item.id).toList()..sort();
    return '${widget.passage.id}:${ids.join('|')}';
  }

  String? _conversationId;
  _QuickAction? _action;
  bool _menu = true, _sending = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ui = ref.read(assistantUiProvider(widget.studySetId));
    if (ui.quickPassageId == _contextKey) {
      _conversationId = ui.quickConversationId;
      _action = _QuickAction.values.where((a) => a.name == ui.quickAction).firstOrNull;
      _menu = _conversationId == null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([_QuickAction? action]) async {
    final controller = ref.read(assistantControllerProvider.notifier);
    final question = action?.prompt(context.l10n) ?? _text.text.trim();
    if (_sending || controller.busy || question.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final configured = await ref.read(assistantConfiguredProvider.future);
      if (!mounted || !configured || controller.busy) return;
      if (_conversationId == null) {
        // Leave existing chat history intact, and do not attach sidebar drafts
        // or the currently selected map node to this passage-only question.
        await controller.newConversation();
        if (!mounted) return;
        _conversationId = ref.read(assistantControllerProvider).id;
      }
      if (ref.read(assistantControllerProvider).id != _conversationId) return;
      if (widget.source case final source?) {
        ref.read(assistantUiProvider(widget.studySetId).notifier).rememberAnchor(widget.passage.id, source);
      }
      final execution = controller.send(
        question,
        contexts: widget.contexts.isEmpty ? [widget.passage] : widget.contexts,
        skill: action?.skill?.name,
      );
      ref
          .read(assistantUiProvider(widget.studySetId).notifier)
          .rememberQuickConversation(_contextKey, _conversationId!, action?.name);
      setState(() {
        _menu = false;
        _action = action;
        _text.clear();
      });
      // The window owns the run. Closing this route leaves it running and saved.
      unawaited(execution.catchError((Object _) {}));
      _focus.requestFocus();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.assistantErrorFailed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sidebar({Citation? source}) async {
    final controller = ref.read(assistantControllerProvider.notifier);
    try {
      if (_conversationId != null) await controller.openConversation(_conversationId!);
      if (!mounted) return;
      askAssistant(
        ref,
        widget.studySetId,
        origin: widget.origin,
        contexts: _conversationId == null ? (widget.contexts.isEmpty ? [widget.passage] : widget.contexts) : const [],
        anchors: _conversationId == null && widget.source != null ? {widget.passage.id: widget.source!} : const {},
      );
      if (source != null) ref.read(assistantUiProvider(widget.studySetId).notifier).openSource(source);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.assistantErrorFailed);
    }
  }

  Future<void> _save(Message answer) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(assistantControllerProvider.notifier)
          .saveNote(
            answer.id,
            SaveNoteRequest(
              title: noteTitleFrom(ref.read(assistantControllerProvider).title).isEmpty
                  ? context.l10n.assistantNoteDefault
                  : noteTitleFrom(ref.read(assistantControllerProvider).title),
              anchor: widget.source,
              mapId: widget.insertionTarget?.mapId,
              parentId: widget.insertionTarget?.parentId,
            ),
          );
      if (mounted) MMHud.show(context, context.l10n.assistantSavedNote);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.assistantErrorFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final conversation = ref.watch(assistantControllerProvider);
    final background = ref.watch(assistantBackgroundProvider);
    final configured = ref.watch(assistantConfiguredProvider);
    final own = _conversationId != null && conversation.id == _conversationId;
    final changed = _conversationId != null && !own;
    final busy = conversation.running || background != null || _sending;
    final answer = own ? conversation.messages.where((m) => m.role == MessageRole.agent).lastOrNull : null;
    final question = answer == null
        ? null
        : conversation.messages.where((m) => m.role == MessageRole.user && m.requestId == answer.requestId).lastOrNull;
    final running = own && conversation.running;
    final canSend = configured.value == true && !busy && !changed;
    if (widget.pending != null) {
      ref.listen(workspaceProvider(widget.studySetId).select((s) => s.pending), (_, pending) {
        if (identical(pending, widget.pending)) return;
        final route = ModalRoute.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && route?.isActive == true) Navigator.of(context).removeRoute(route!);
        });
      });
    }
    final showingAnswer = !_menu && answer != null && question != null;
    final title = showingAnswer
        ? (question.skill == AssistantSkill.organize.name ? l.assistantAnswerToMap : _action?.title(l) ?? question.text)
        : l.assistantQuickTitle;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: Focus(
        autofocus: true,
        child: Material(
          key: const ValueKey('assistant-quick-actions'),
          color: c.glassOpaque,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.separator, width: .5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (showingAnswer)
                      MMIconButton(
                        icon: MMIcons.chevronLeft,
                        tooltip: l.back,
                        onPressed: running ? null : () => setState(() => _menu = true),
                      ),
                    Icon(MMIcons.ai, size: 17, color: c.research),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.headline.copyWith(color: c.label),
                      ),
                    ),
                    MMIconButton(
                      key: const ValueKey('quick-close'),
                      icon: MMIcons.close,
                      tooltip: l.closePanel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('quick-content'),
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (configured.isLoading)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(l.assistantThinking, style: t.body),
                            ),
                          if (configured.hasError || (!configured.isLoading && configured.value != true))
                            const ModelSetupCard(inline: true)
                          else if (changed)
                            Text(l.assistantQuickChanged, style: t.body.copyWith(color: c.secondaryLabel))
                          else if (showingAnswer) ...[
                            Divider(height: 12, color: c.separator),
                            SelectionArea(
                              child: AgentMessage(
                                studySetId: widget.studySetId,
                                message: answer,
                                question: question,
                                compact: true,
                                onSource: (citation) => _sidebar(source: citation),
                                onSaveNote: () => _save(answer),
                                saveNoteTooltip: widget.insertionTarget == null ? null : l.assistantInsertChild,
                                savingNote: _saving,
                              ),
                            ),
                          ] else ...[
                            if (busy)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(l.assistantQuickBusy, style: t.callout.copyWith(color: c.secondaryLabel)),
                              ),
                            for (final action in _QuickAction.values)
                              _ActionRow(
                                key: ValueKey('quick-action-${action.name}'),
                                icon: action.icon,
                                title: action.title(l),
                                onTap: canSend ? () => _send(action) : null,
                              ),
                          ],
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(_error!, style: t.callout.copyWith(color: c.critical)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        key: const ValueKey('quick-composer'),
                        height: 36,
                        padding: const EdgeInsets.all(3),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(color: c.separator),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, right: 6),
                                child: TextField(
                                  key: const ValueKey('quick-input'),
                                  controller: _text,
                                  focusNode: _focus,
                                  enabled: canSend,
                                  style: t.body.copyWith(color: c.label),
                                  maxLength: 60000,
                                  decoration: InputDecoration(
                                    hintText: _conversationId == null ? l.assistantQuickAsk : l.assistantQuickFollowUp,
                                    hintStyle: t.body.copyWith(color: c.secondaryLabel),
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    counterText: '',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (_) => _send(),
                                ),
                              ),
                            ),
                            ClipOval(
                              key: const ValueKey('quick-send-surface'),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: running || (canSend && _text.text.trim().isNotEmpty) ? c.research : c.fill,
                                ),
                                child: MMIconButton(
                                  key: const ValueKey('quick-send'),
                                  size: 28,
                                  icon: running ? MMIcons.stop : MMIcons.send,
                                  tooltip: running ? l.assistantStop : l.assistantSend,
                                  color: c.onAccent,
                                  onPressed: running
                                      ? () => unawaited(
                                          ref
                                              .read(assistantControllerProvider.notifier)
                                              .stop()
                                              .catchError((Object _) {}),
                                        )
                                      : canSend && _text.text.trim().isNotEmpty
                                      ? () => _send()
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    MMIconButton(
                      key: const ValueKey('quick-sidebar'),
                      icon: MMIcons.sidebarRight,
                      tooltip: l.assistantQuickSidebar,
                      size: 32,
                      onPressed: _sending ? null : () => _sidebar(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({super.key, required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onTap,
      semanticLabel: title,
      builder: (context, s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: s.hovered || s.focused ? c.researchTint : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Opacity(
          opacity: s.enabled ? 1 : .4,
          child: Row(
            children: [
              Icon(icon, size: 16, color: c.icon),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: t.body)),
              Icon(MMIcons.chevronRight, size: 11, color: c.secondaryLabel),
            ],
          ),
        ),
      ),
    );
  }
}
