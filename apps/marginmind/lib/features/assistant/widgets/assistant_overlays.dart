import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart' show SearxngSearch;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../research/research_origin.dart' show researchCardTitle;
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_reader.dart';
import '../assistant_scope.dart';
import '../assistant_settings.dart';

final assistantLinksProvider = Provider<ExternalLinks>((ref) => const ExternalLinks());

/// Routes are pushed above the window's assistant scope: [child] gets the
/// scope of [context] back.
Widget inScope(BuildContext context, Widget child) =>
    UncontrolledProviderScope(container: ProviderScope.containerOf(context, listen: false), child: child);

enum SourceKind { web, paper, video }

/// Prefer the recorded kind; legacy citations fall back to the address.
SourceKind sourceKind(Citation c) {
  if (c.kind == 'openAlex') return SourceKind.paper;
  final host = Uri.tryParse(c.url ?? '')?.host ?? '';
  if (RegExp(r'(^|\.)(youtube\.com|youtu\.be|bilibili\.com|vimeo\.com)$').hasMatch(host)) return SourceKind.video;
  if (RegExp(r'(^|\.)(doi\.org|openalex\.org|arxiv\.org)$').hasMatch(host)) return SourceKind.paper;
  return SourceKind.web;
}

IconData sourceIcon(Citation c) => switch (sourceKind(c)) {
  SourceKind.web => MMIcons.web,
  SourceKind.paper => MMIcons.paper,
  SourceKind.video => MMIcons.video,
};

/// Prefer the title captured with the snapshot; legacy citations show the site.
String sourceTitle(Citation c) {
  if (c.title.isNotEmpty) return c.title;
  final url = Uri.tryParse(c.url ?? '');
  return url == null || url.host.isEmpty ? (c.sourceId ?? '') : url.host.replaceFirst(RegExp(r'^www\.'), '');
}

// ---- popup menus --------------------------------------------------------------------------------

class PopupItem<T> {
  const PopupItem(this.value, this.label, {this.icon, this.checked});

  final T value;
  final String label;
  final IconData? icon;

  /// Non-null leaves room for a check mark (the model menu).
  final bool? checked;
}

/// Rows of a glass popup: the `/` and `@` menus and the model menu.
class PopupList<T> extends StatelessWidget {
  const PopupList({super.key, required this.items, required this.highlighted, required this.onSelected, this.onHover});

  final List<PopupItem<T>> items;
  final int highlighted;
  final ValueChanged<T> onSelected;
  final ValueChanged<int>? onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMGlass(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in items.indexed)
            MouseRegion(
              onEnter: (_) => onHover?.call(i),
              child: MMInteractive(
                onTap: () => onSelected(item.value),
                canRequestFocus: false,
                semanticLabel: item.label,
                builder: (context, s) {
                  final on = i == highlighted;
                  final fg = on ? c.onAccent : c.label;
                  return Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                    decoration: BoxDecoration(
                      color: on ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        if (item.checked != null)
                          SizedBox(width: 20, child: item.checked! ? Icon(MMIcons.check, size: 14, color: fg) : null),
                        if (item.icon != null) ...[
                          Icon(item.icon, size: 14, color: on ? fg : c.icon),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.body.copyWith(color: fg),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Places a popup of a fixed [width] above [anchor] (below when there is
/// no room), inside the window.
class _AnchoredLayout extends SingleChildLayoutDelegate {
  _AnchoredLayout(this.anchor, this.width);

  final Rect anchor;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: width.clamp(0, constraints.maxWidth - 16),
    minWidth: width.clamp(0, constraints.maxWidth - 16),
    maxHeight: constraints.maxHeight - 16,
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final placement = placeFloatingToolbar(anchor: anchor, size: child, viewport: Offset.zero & size);
    final x = (anchor.left).clamp(MMSpacing.s, size.width - child.width - MMSpacing.s);
    return Offset(x.toDouble(), placement.offset.dy);
  }

  @override
  bool shouldRelayout(_AnchoredLayout old) => old.anchor != anchor || old.width != width;
}

/// Global bounds of [context]'s widget.
Rect boundsOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Shows [items] above [anchor]; resolves to the chosen value. ↑↓ move,
/// ↩ / Tab choose, Esc closes.
Future<T?> showPopupMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required List<PopupItem<T>> items,
  double width = 240,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierColor: Colors.transparent,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: const Duration(milliseconds: 90),
  pageBuilder: (context, _, _) => CustomSingleChildLayout(
    delegate: _AnchoredLayout(anchor, width),
    child: _KeyboardPopup<T>(items: items),
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

class _KeyboardPopup<T> extends StatefulWidget {
  const _KeyboardPopup({super.key, required this.items});

  final List<PopupItem<T>> items;

  @override
  State<_KeyboardPopup<T>> createState() => _KeyboardPopupState<T>();
}

class _KeyboardPopupState<T> extends State<_KeyboardPopup<T>> {
  int _at = 0;

  void _move(int by) => setState(() => _at = (_at + by) % widget.items.length);
  void _choose() => Navigator.of(context).pop(widget.items[_at].value);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(widget.items.length - 1),
      const SingleActivator(LogicalKeyboardKey.enter): _choose,
      const SingleActivator(LogicalKeyboardKey.tab): _choose,
      const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
    },
    child: Focus(
      autofocus: true,
      child: PopupList<T>(
        items: widget.items,
        highlighted: _at,
        onHover: (i) => setState(() => _at = i),
        onSelected: (v) => Navigator.of(context).pop(v),
      ),
    ),
  );
}

// ---- save as note ---------------------------------------------------------------------------------

/// Where a note goes in the map: a topic (or the root) it is about, else
/// the parent of the card it is about, else the root (no parent).
({String mapId, String? parentId, String title}) notePlace(
  StudySetContent content,
  String activeMapId,
  List<ContextItem> contexts,
  String rootTitle,
) {
  final node = contexts
      .where((c) => (c.kind == ContextKind.node || c.kind == ContextKind.branch) && c.nodeId != null)
      .firstOrNull;
  final mapId = node?.mapId ?? activeMapId;
  final String? noParent = null;
  final root = (mapId: mapId, parentId: noParent, title: rootTitle);
  if (node == null || node.nodeId == assistantRootId) return root;
  final card = content.card(node.nodeId!);
  final mapNode = content.node(node.nodeId!, mapId: mapId);
  if (card == null || mapNode == null) return root;
  if (card.kind == CardKind.topic) return (mapId: mapId, parentId: card.id, title: researchCardTitle(content, card.id));
  final parent = mapNode.parentId;
  if (parent == null) return root;
  return (mapId: mapId, parentId: parent, title: researchCardTitle(content, parent));
}

/// A title for a note from the conversation's: without a leading
/// "解释：" (or "Explain:") style prefix.
String noteTitleFrom(String conversationTitle) =>
    conversationTitle.replaceFirst(RegExp(r'^[^:：\s]{1,8}[:：]\s*'), '').trim();

/// The popover above an answer's "Save as Note" button.
Future<void> showSaveNotePopover(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Message answer,
  Message question,
) {
  final anchor = boundsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.quick),
    pageBuilder: (dialog, _, _) => inScope(
      context,
      CustomSingleChildLayout(
        delegate: _AnchoredLayout(anchor, 300),
        child: SaveNotePopover(studySetId: studySetId, answer: answer, question: question),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

class SaveNotePopover extends ConsumerStatefulWidget {
  const SaveNotePopover({super.key, required this.studySetId, required this.answer, required this.question});

  final String studySetId;
  final Message answer;
  final Message question;

  @override
  ConsumerState<SaveNotePopover> createState() => _SaveNotePopoverState();
}

class _SaveNotePopoverState extends ConsumerState<SaveNotePopover> {
  late final TextEditingController _title;
  final _focus = FocusNode();
  bool _inMap = true, _inSource = true, _saving = false;

  @override
  void initState() {
    super.initState();
    final title = noteTitleFrom(ref.read(assistantControllerProvider).title);
    _title = TextEditingController(text: title)..selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  SourceAnchor? get _anchor {
    final anchors = ref.read(assistantUiProvider(widget.studySetId)).anchors;
    for (final c in widget.question.contexts) {
      if (c.kind == ContextKind.selection && anchors[c.id] != null) return anchors[c.id];
    }
    return null;
  }

  Future<void> _save(({String mapId, String? parentId, String title}) place) async {
    final anchor = _anchor;
    final inSource = anchor != null && _inSource;
    if (_saving || (!_inMap && !inSource)) return;
    setState(() => _saving = true);
    final l = context.l10n;
    final hud = Navigator.of(context).context;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final title = _title.text.trim().isEmpty ? l.assistantNoteDefault : _title.text.trim();
    try {
      await ref
          .read(assistantControllerProvider.notifier)
          .saveNote(
            widget.answer.id,
            SaveNoteRequest(
              title: title,
              mapId: _inMap ? place.mapId : null,
              parentId: _inMap ? place.parentId : null,
              anchor: inSource ? anchor : null,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (hud.mounted) MMHud.show(hud, l.assistantSavedNote, action: (l.undo, () => unawaited(workspace.undo())));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      MMHud.show(context, l.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final place = notePlace(
      workspace.content,
      mapId,
      widget.question.contexts,
      mapTitle(ref, widget.studySetId, mapId),
    );
    final anchor = _anchor;
    final page = anchor?.target is PdfTarget ? (anchor!.target as PdfTarget).pages.first.page : null;
    final can = !_saving && (_inMap || (anchor != null && _inSource));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): () => _save(place),
      },
      child: FocusScope(
        child: MMGlass(
          key: const ValueKey('save-note-popover'),
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MMSpacing.m),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.assistantSaveNote, style: t.headline.copyWith(color: c.label)),
                const SizedBox(height: MMSpacing.s),
                MMTextField(
                  controller: _title,
                  focusNode: _focus,
                  semanticLabel: l.assistantNoteTitle,
                  onSubmitted: (_) => _save(place),
                ),
                const SizedBox(height: MMSpacing.s),
                MMCheckbox(
                  key: const ValueKey('save-note-map'),
                  value: _inMap,
                  color: c.research,
                  label: l.assistantPutInMap(place.title),
                  onChanged: (v) => setState(() => _inMap = v),
                ),
                if (page != null) ...[
                  const SizedBox(height: MMSpacing.xs + 2),
                  MMCheckbox(
                    key: const ValueKey('save-note-source'),
                    value: _inSource,
                    color: c.research,
                    label: l.assistantAttachToSource(page),
                    onChanged: (v) => setState(() => _inSource = v),
                  ),
                ],
                const SizedBox(height: MMSpacing.m),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: MMSpacing.s),
                    MMButton(
                      key: const ValueKey('save-note-confirm'),
                      label: l.save,
                      variant: MMButtonVariant.primary,
                      color: c.research,
                      onPressed: can ? () => _save(place) : null,
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

// ---- source drawer -----------------------------------------------------------------------------------

/// An external source over the messages and input: the cited passage,
/// highlighted, with a way to the browser.
class SourceDrawer extends ConsumerWidget {
  const SourceDrawer({super.key, required this.studySetId, required this.citation, required this.number});

  final String studySetId;
  final Citation citation;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final ui = ref.read(assistantUiProvider(studySetId).notifier);
    final url = Uri.tryParse(citation.url ?? '');
    final kind = switch (sourceKind(citation)) {
      SourceKind.web => l.assistantKindWeb,
      SourceKind.paper => l.assistantKindPaper,
      SourceKind.video => l.assistantKindVideo,
    };
    return ColoredBox(
      key: const ValueKey('source-drawer'),
      color: c.windowBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.separator)),
            ),
            child: Row(
              children: [
                MMIconButton(
                  icon: MMIcons.chevronLeft,
                  tooltip: l.assistantBack,
                  iconSize: 13,
                  onPressed: ui.closeSource,
                ),
                const SizedBox(width: MMSpacing.xs),
                MMPill('[$number] $kind'),
                const Spacer(),
                if (url != null && ExternalLinks.canOpen(url))
                  MMButton(
                    label: l.assistantOpenInBrowser,
                    icon: MMIcons.openExternal,
                    variant: MMButtonVariant.plain,
                    onPressed: () => ref.read(assistantLinksProvider).open(url),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l, vertical: MMSpacing.m),
              children: [
                Text(sourceTitle(citation), style: t.title3.copyWith(color: c.label)),
                if (citation.version != null) ...[
                  const SizedBox(height: MMSpacing.xxs),
                  Text(
                    [
                      if (url?.host case final host? when host.isNotEmpty) host,
                      'v${citation.version}',
                      if (citation.fetchedAt case final stamp?)
                        DateFormat.yMd(Localizations.localeOf(context).toLanguageTag())
                            .add_Hm()
                            .format(stamp.toLocal()),
                    ].join(' · '),
                    style: t.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ],
                const SizedBox(height: MMSpacing.m),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: MMSpacing.xxs),
                  decoration: BoxDecoration(color: c.researchTint, borderRadius: BorderRadius.circular(4)),
                  child: Text(citation.quote, style: t.readingExcerpt.copyWith(color: c.label)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- settings ------------------------------------------------------------------------------------------

String serviceName(AppLocalizations l, AssistantProvider p) => switch (p) {
  AssistantProvider.claude => l.assistantServiceClaude,
  AssistantProvider.responses => l.assistantServiceOpenAI,
  AssistantProvider.compatible => l.assistantServiceCompatible,
  AssistantProvider.ollama => 'Ollama',
  AssistantProvider.gemini => 'Gemini',
};

/// Services supported by the bounded assistant transport.
// Legacy sheet stays at four choices until GUL-537 replaces it with service cards.
const connectableServices = [
  AssistantProvider.claude,
  AssistantProvider.responses,
  AssistantProvider.compatible,
  AssistantProvider.ollama,
];

/// The assistant's settings sheet: service, model, key and network.
Future<void> showAssistantSettings(BuildContext context, WidgetRef ref) =>
    showMMSheet<void>(context: context, width: 560, builder: (_) => inScope(context, const AssistantSettingsSheet()));

class AssistantSettingsSheet extends ConsumerStatefulWidget {
  const AssistantSettingsSheet({super.key});

  @override
  ConsumerState<AssistantSettingsSheet> createState() => _AssistantSettingsSheetState();
}

class _AssistantSettingsSheetState extends ConsumerState<AssistantSettingsSheet> {
  late AssistantSettings _settings;
  final _model = TextEditingController();
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _searxng = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = ref.read(assistantSettingsProvider);
    _model.text = _settings.model;
    _endpoint.text = _settings.endpoint;
    _searxng.text = _settings.searxngEndpoint;
  }

  @override
  void dispose() {
    _model.dispose();
    _endpoint.dispose();
    _key.dispose();
    _searxng.dispose();
    super.dispose();
  }

  bool get _invalidSearxng {
    if (_settings.provider != AssistantProvider.compatible && _settings.provider != AssistantProvider.ollama) {
      return false;
    }
    if (_searxng.text.trim().isEmpty) return false;
    try {
      SearxngSearch.parseEndpoint(_searxng.text.trim());
      return false;
    } on ResearchFailure {
      return true;
    }
  }

  Future<void> _save() async {
    if (_invalidSearxng) return;
    final settings = AssistantSettings(
      provider: _settings.provider,
      model: _model.text.trim(),
      endpoint: _endpoint.text.trim(),
      online: _settings.online,
      localEnabled: _settings.localEnabled,
      searxngEndpoint: _searxng.text.trim(),
    );
    final notifier = ref.read(assistantSettingsProvider.notifier);
    await notifier.configure(settings);
    if (_key.text.trim().isNotEmpty) await notifier.saveKey(_key.text);
    final controller = ref.read(assistantControllerProvider.notifier);
    await controller.switchModel(settings.configuration);
    await controller.setOnline(settings.online);
    if (mounted) Navigator.of(context).pop();
  }

  void _service(AssistantProvider p) {
    final next = ref.read(assistantSettingsProvider.notifier).saved(p);
    setState(() {
      _settings = AssistantSettings(
        provider: p,
        model: next.model,
        endpoint: next.endpoint,
        online: _settings.online,
        localEnabled: _settings.localEnabled || p == AssistantProvider.ollama,
        searxngEndpoint: _settings.searxngEndpoint,
      );
      _model.text = next.model;
      _endpoint.text = next.endpoint;
      _key.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return MMSheet(
      title: l.assistantSettings,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(
          key: const ValueKey('assistant-settings-save'),
          label: l.save,
          variant: MMButtonVariant.primary,
          color: c.research,
          onPressed: _invalidSearxng ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMFormRow(
            label: l.assistantService,
            child: MMSegmentedControl<AssistantProvider>(
              segments: [for (final p in connectableServices) MMSegment(value: p, label: serviceName(l, p))],
              value: _settings.provider,
              onChanged: _service,
            ),
          ),
          MMFormRow(
            label: l.assistantModelField,
            child: MMTextField(
              key: const ValueKey('settings-model'),
              controller: _model,
              semanticLabel: l.assistantModelField,
            ),
          ),
          if (_settings.provider == AssistantProvider.compatible || _settings.provider == AssistantProvider.ollama)
            MMFormRow(
              label: l.assistantEndpointField,
              child: MMTextField(controller: _endpoint, semanticLabel: l.assistantEndpointField),
            ),
          if (_settings.provider != AssistantProvider.ollama)
            MMFormRow(
              label: 'API Key',
              child: MMTextField(controller: _key, obscureText: true, semanticLabel: 'API Key'),
            ),
          if (_settings.provider == AssistantProvider.compatible || _settings.provider == AssistantProvider.ollama)
            MMFormRow(
              label: 'SearXNG',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MMTextField(
                    key: const ValueKey('settings-searxng'),
                    controller: _searxng,
                    semanticLabel: 'SearXNG',
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_invalidSearxng)
                    Padding(
                      padding: const EdgeInsets.only(top: MMSpacing.xs),
                      child: Text(
                        l.assistantSearxngInvalid,
                        style: context.mmText.footnote.copyWith(color: c.critical),
                      ),
                    ),
                ],
              ),
            ),
          MMFormRow(
            label: l.assistantLocalSetting,
            child: Align(
              alignment: Alignment.centerLeft,
              child: MMSwitch(
                key: const ValueKey('settings-local-enabled'),
                value: _settings.localEnabled,
                color: c.research,
                semanticLabel: l.assistantLocalSetting,
                onChanged: (v) => setState(
                  () => _settings = AssistantSettings(
                    provider: _settings.provider,
                    model: _settings.model,
                    endpoint: _settings.endpoint,
                    online: _settings.online,
                    localEnabled: v,
                    searxngEndpoint: _settings.searxngEndpoint,
                  ),
                ),
              ),
            ),
          ),
          MMFormRow(
            label: l.assistantOnline,
            child: Align(
              alignment: Alignment.centerLeft,
              child: MMSwitch(
                value: _settings.online,
                color: c.research,
                semanticLabel: l.assistantOnline,
                onChanged: (v) => setState(
                  () => _settings = AssistantSettings(
                    provider: _settings.provider,
                    model: _settings.model,
                    endpoint: _settings.endpoint,
                    online: v,
                    localEnabled: _settings.localEnabled,
                    searxngEndpoint: _settings.searxngEndpoint,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
