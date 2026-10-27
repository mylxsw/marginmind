import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../research/research_controller.dart' show researchPanelProvider;
import '../../research/research_origin.dart' show researchCardTitle;
import '../../research/widgets/research_note_view.dart';
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../assistant_settings.dart';
import 'assistant_conversations.dart';
import 'assistant_composer.dart';
import 'assistant_markdown.dart' show sourceNumbers;
import 'assistant_messages.dart';
import 'assistant_overlays.dart';

/// Gives a study set window its assistant: the conversation lives as long as
/// the window, so closing the panel or switching documents never stops an
/// answer. Entry points outside the window ask through [assistantUiProvider].
class AssistantScope extends ConsumerStatefulWidget {
  const AssistantScope({super.key, required this.studySetId, required this.child});

  final String studySetId;
  final Widget child;

  @override
  ConsumerState<AssistantScope> createState() => _AssistantScopeState();
}

class _AssistantScopeState extends ConsumerState<AssistantScope> {
  late final _dependencies = ref.read(assistantDependenciesForProvider(widget.studySetId));

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      assistantDependenciesProvider.overrideWithValue(_dependencies),
      assistantControllerProvider.overrideWith(AssistantController.new),
    ],
    child: _AssistantHost(studySetId: widget.studySetId, child: widget.child),
  );
}

class _AssistantHost extends ConsumerWidget {
  const _AssistantHost({required this.studySetId, required this.child});

  final String studySetId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listening keeps the conversation alive without rebuilding the window.
    ref.listen(assistantControllerProvider.select((c) => (c.id, c.running, c.title, c.messages.length)), (
      previous,
      next,
    ) {
      if (previous != next) ref.invalidate(assistantConversationsProvider(studySetId));
    });
    // Kept loaded, so a question asked as the panel opens is not dropped.
    ref.listen(assistantConfiguredProvider, (_, _) {});
    ref.listen(assistantUiProvider(studySetId).select((s) => s.request), (_, request) async {
      if (request == null) return;
      ref.read(assistantUiProvider(studySetId).notifier).handled(request.id);
      final l = context.l10n;
      final configured = await ref.read(assistantConfiguredProvider.future).catchError((Object _) => false);
      if (!configured || !context.mounted) return; // The panel shows how to connect.
      assistantSend(ref, studySetId, l, request.text, skill: request.skill);
    });
    return child;
  }
}

/// The right panel's assistant: header, the conversation (or the list of
/// conversations), and the input.
class AssistantPanel extends ConsumerWidget {
  const AssistantPanel({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(assistantUiProvider(studySetId));
    final uiNotifier = ref.read(assistantUiProvider(studySetId).notifier);
    final conversation = ref.watch(assistantControllerProvider);
    final configured = ref.watch(assistantConfiguredProvider).value ?? false;
    final noteId = ref.watch(researchPanelProvider(studySetId).select((s) => s.noteId));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final header = AssistantHeader(studySetId: studySetId);
    if (noteId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: ResearchNoteView(
              studySetId: studySetId,
              noteId: noteId,
              onBack: ref.read(researchPanelProvider(studySetId).notifier).closeNote,
            ),
          ),
        ],
      );
    }
    final source = ui.source;
    final number = source == null
        ? 0
        : conversation.messages
                  .where((m) => m.citations.any((c) => c.marker == source.marker && c.sourceId == source.sourceId))
                  .map((m) => sourceNumbers(m.text, m.citations)[source.sourceId])
                  .nonNulls
                  .firstOrNull ??
              0;

    // Esc, innermost first: the source, then a running answer, then the panel.
    void escape() {
      if (ui.source != null) return uiNotifier.closeSource();
      if (conversation.running) {
        unawaited(ref.read(assistantControllerProvider.notifier).stop());
        return;
      }
      workspace.closePanel();
    }

    final Widget body;
    if (ui.history) {
      body = ConversationHistory(studySetId: studySetId);
    } else if (!configured) {
      body = ListView(children: const [ConnectCard()]);
    } else if (conversation.messages.isEmpty) {
      body = AssistantSuggestions(studySetId: studySetId);
    } else {
      body = AssistantMessageList(key: ValueKey(conversation.id), studySetId: studySetId);
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): escape},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: body),
                    if (!ui.history) AssistantComposer(studySetId: studySetId, configured: configured),
                  ],
                ),
                if (source != null)
                  _DrawerTransition(
                    child: SourceDrawer(studySetId: studySetId, citation: source, number: number),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The source drawer comes in from the right (at once with reduced motion).
class _DrawerTransition extends StatelessWidget {
  const _DrawerTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MMAppearance.duration(context, MMMotion.standard),
    curve: MMMotion.layoutCurve,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
    ),
    child: child,
  );
}

/// The panel's top row: the conversation's title (opening the list of
/// conversations), then new conversation, settings and close.
class AssistantHeader extends ConsumerWidget {
  const AssistantHeader({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final title = ref.watch(assistantControllerProvider.select((s) => s.title));
    final history = ref.watch(assistantUiProvider(studySetId).select((s) => s.history));
    final ui = ref.read(assistantUiProvider(studySetId).notifier);
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    var shown = title.trim().isEmpty ? l.assistant : title.trim();
    if (shown.runes.length > 24) shown = '${String.fromCharCodes(shown.runes.take(24))}…';
    return Container(
      height: MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.s + 2, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Flexible(
            child: MMInteractive(
              key: const ValueKey('assistant-title'),
              onTap: () {
                ref.read(researchPanelProvider(studySetId).notifier).closeNote();
                ui.showHistory(!history);
              },
              semanticLabel: shown,
              semanticValue: l.assistantHistory,
              builder: (context, s) => AnimatedContainer(
                duration: MMMotion.quick,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: s.hovered ? c.hover : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(7)),
                      child: const Icon(MMIcons.ai, size: 13, color: Colors.white),
                    ),
                    const SizedBox(width: MMSpacing.s),
                    Flexible(
                      child: Text(
                        shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.headline.copyWith(color: c.label),
                      ),
                    ),
                    const SizedBox(width: MMSpacing.xs),
                    Icon(history ? MMIcons.chevronUp : MMIcons.chevronDown, size: 11, color: c.icon),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          MMIconButton(
            key: const ValueKey('assistant-new'),
            icon: MMIcons.add,
            iconSize: 13,
            tooltip: l.assistantNewConversation,
            onPressed: () => startNewConversation(ref, studySetId),
          ),
          MMIconButton(
            key: const ValueKey('assistant-settings'),
            icon: MMIcons.settings,
            iconSize: 13,
            tooltip: l.assistantSettings,
            onPressed: () => showAssistantSettings(context, ref),
          ),
          MMIconButton(
            key: const ValueKey('assistant-close'),
            icon: MMIcons.close,
            iconSize: 13,
            tooltip: AppShortcuts.tip(l.closePanel, AppShortcuts.assistantPanel),
            onPressed: workspace.closePanel,
          ),
        ],
      ),
    );
  }
}

/// A new, empty conversation in the panel.
void startNewConversation(WidgetRef ref, String studySetId) {
  ref.read(researchPanelProvider(studySetId).notifier).closeNote();
  ref.read(assistantUiProvider(studySetId).notifier).showHistory(false);
  unawaited(ref.read(assistantControllerProvider.notifier).newConversation().catchError((Object _) {}));
  ref.read(assistantUiProvider(studySetId).notifier).focus();
}

/// An empty conversation: five questions that fit what is open, sent on click.
class AssistantSuggestions extends ConsumerWidget {
  const AssistantSuggestions({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final auto = ref.watch(assistantAutoContextsProvider(studySetId));
    final ui = ref.watch(assistantUiProvider(studySetId));
    final online = ref.watch(assistantControllerProvider.select((c) => c.online));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final mapId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    final content = workspace.content;
    final page = auto.where((c) => c.kind == ContextKind.page).firstOrNull;
    final selection = ui.contexts.where((c) => c.kind == ContextKind.selection).firstOrNull;
    var topic = [
      ...ui.contexts,
      ...auto,
    ].where((c) => c.kind == ContextKind.node || c.kind == ContextKind.branch).firstOrNull;
    // No node attached: the latest topic excerpted from the page being read.
    if (topic == null && page != null) {
      final card = content.cards
          .where((c) => content.annotation(c.annotationId ?? '')?.documentId == page.documentId)
          .where((c) => content.annotation(c.annotationId!)!.page == page.page)
          .lastOrNull;
      final parent = card == null ? null : content.node(card.id, mapId: mapId)?.parentId;
      if (parent != null) topic = nodeContext(mapId: mapId, nodeId: parent, title: researchCardTitle(content, parent));
    }
    final suggestions = <(IconData, String, AssistantSkill, List<ContextItem>)>[
      if (page != null) (MMIcons.summarize, l.assistantSuggestSummarize(page.page!), AssistantSkill.summarize, [page]),
      if (topic != null)
        (MMIcons.explain, l.assistantSuggestExplain(topic.displayText), AssistantSkill.explain, [topic]),
      if (page != null && online)
        (MMIcons.verify, l.assistantSuggestVerify(page.page!), AssistantSkill.verify, [page])
      else if (selection != null)
        (MMIcons.translate, l.assistantSuggestTranslate, AssistantSkill.translate, [selection]),
      if (topic != null) (MMIcons.review, l.assistantSuggestQuiz(topic.displayText), AssistantSkill.quiz, [topic]),
      if (page != null) (MMIcons.organize, l.assistantSuggestOrganize, AssistantSkill.organize, [page]),
    ];
    return ListView(
      key: const ValueKey('assistant-suggestions'),
      padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.l),
      children: [
        for (final (icon, text, skill, contexts) in suggestions.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Suggestion(
              icon: icon,
              text: text,
              onPressed: () {
                final notifier = ref.read(assistantUiProvider(studySetId).notifier);
                for (final c in contexts) {
                  if (!c.auto) notifier.addContext(c);
                }
                assistantSend(ref, studySetId, l, skill.prompt(l), skill: skill.name);
              },
            ),
          ),
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.icon, required this.text, required this.onPressed});

  final IconData icon;
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      semanticLabel: text,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
        decoration: BoxDecoration(
          color: s.hovered ? c.researchTint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: s.hovered ? c.research.withValues(alpha: .16) : c.separator),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.research),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.body.copyWith(color: c.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No AI service yet: pick one and paste its key, right in the panel.
class ConnectCard extends ConsumerStatefulWidget {
  const ConnectCard({super.key});

  @override
  ConsumerState<ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends ConsumerState<ConnectCard> {
  late AssistantProvider _service;
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _endpoint = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(assistantSettingsProvider).provider;
    _service = connectableServices.contains(current) ? current : AssistantProvider.claude;
    final saved = ref.read(assistantSettingsProvider.notifier).saved(_service);
    _model.text = saved.model;
    _endpoint.text = saved.endpoint;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  void _pick(AssistantProvider p) {
    final saved = ref.read(assistantSettingsProvider.notifier).saved(p);
    setState(() {
      _service = p;
      _model.text = saved.model;
      _endpoint.text = saved.endpoint;
      _error = null;
    });
  }

  Future<void> _connect() async {
    final l = context.l10n;
    final key = _key.text.trim();
    if (_connecting || key.isEmpty || _model.text.trim().isEmpty) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    final notifier = ref.read(assistantSettingsProvider.notifier);
    final current = ref.read(assistantSettingsProvider);
    final settings = AssistantSettings(
      provider: _service,
      model: _model.text.trim(),
      endpoint: _endpoint.text.trim(),
      online: current.online,
      localEnabled: current.localEnabled,
      searxngEndpoint: current.searxngEndpoint,
    );
    final failure = await ref.read(assistantConnectionTesterProvider)(settings.configuration, key);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _connecting = false;
        _error = failure == ResearchFailureKind.authentication ? l.assistantKeyInvalid : l.assistantCannotConnect;
      });
      return;
    }
    await notifier.configure(settings);
    await notifier.saveKey(key);
    await ref.read(assistantControllerProvider.notifier).switchModel(settings.configuration);
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    return Container(
      key: const ValueKey('assistant-connect'),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(MMIcons.ai, size: 14, color: c.research),
              const SizedBox(width: 6),
              Text(l.assistantConnectTitle, style: t.headline.copyWith(color: c.label)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in connectableServices)
                  SizedBox(
                    width: (box.maxWidth - 6) / 2,
                    child: MMInteractive(
                      key: ValueKey('connect-${p.name}'),
                      onTap: () => _pick(p),
                      selected: p == _service,
                      semanticLabel: serviceName(l, p),
                      semanticValue: p == _service ? '✓' : null,
                      builder: (context, s) => AnimatedContainer(
                        duration: MMMotion.quick,
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                        decoration: BoxDecoration(
                          color: p == _service ? c.researchTint : (s.hovered ? c.hover : Colors.transparent),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: p == _service ? c.research : c.separator,
                            width: p == _service ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(MMIcons.ai, size: 12, color: p == _service ? c.research : c.icon),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                serviceName(l, p),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.callout.copyWith(color: c.label),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_service != AssistantProvider.claude) ...[
            MMTextField(controller: _model, placeholder: l.assistantModelField, semanticLabel: l.assistantModelField),
            const SizedBox(height: 6),
          ],
          if (_service == AssistantProvider.compatible) ...[
            MMTextField(
              controller: _endpoint,
              placeholder: l.assistantEndpointField,
              semanticLabel: l.assistantEndpointField,
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: MMTextField(
                  key: const ValueKey('connect-key'),
                  controller: _key,
                  obscureText: true,
                  placeholder: l.assistantPasteKey,
                  semanticLabel: l.assistantPasteKey,
                  onSubmitted: (_) => _connect(),
                ),
              ),
              const SizedBox(width: MMSpacing.s),
              if (_connecting)
                SizedBox(
                  width: 60,
                  child: Center(child: CupertinoActivityIndicator(radius: 7, color: c.research)),
                )
              else
                MMButton(
                  key: const ValueKey('connect-button'),
                  label: l.assistantConnect,
                  variant: MMButtonVariant.primary,
                  color: c.research,
                  onPressed: _connect,
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              key: const ValueKey('connect-error'),
              style: t.footnote.copyWith(color: c.critical),
            ),
          ],
        ],
      ),
    );
  }
}
