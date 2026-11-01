import '../../map_generation/widgets/document_map_banner.dart';
import '../../map_generation/widgets/map_ocr_banner.dart';

import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart' show RoutingIssue;
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/providers.dart';
import '../../../app/app_commands.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../../settings/highlight_palette.dart';
import '../../../shared/card_image.dart';
import '../../assistant/assistant_entry.dart';
import '../../assistant/expansion_controller.dart';
import '../../assistant/map_task_route.dart';
import '../../assistant/widgets/expansion_widgets.dart';
import '../../assistant/assistant_reader.dart' show assistantRootId, assistantNodeBody;
import '../../assistant/assistant_scope.dart' show assistantPreviewProvider, nodeContext;
import '../../assistant/widgets/assistant_quick_actions.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf;
import '../../research/research_origin.dart' show researchCardTitle;
import '../workspace_controller.dart';
import 'mind_map_canvas.dart';
import 'notices.dart';
import 'map_export_sheet.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../../map_generation/map_generation_controller.dart';
import '../../map_generation/widgets/generate_map_sheet.dart';
import '../../map_generation/widgets/map_empty_state.dart';
import '../../map_generation/widgets/map_diff_panel.dart';
import '../../map_generation/widgets/map_generation_bar.dart';
import 'map_style_popover.dart';
import 'outline_view.dart';
import 'map_selection_bar.dart';
import 'map_header.dart';
import 'generate_map_menu.dart';
import 'workspace_toolbar.dart';
import '../workspace_chrome_controller.dart';
import '../workspace_pane_chrome_controller.dart';

// Temporarily hidden; keep the toolbar and its actions available for restoration.
final mapCommandBarVisibleProvider = Provider<bool>((ref) => false);

/// Map pane: the mind map (or outline) plus floating glass controls — map
/// title and view switch at the top, node actions by the selection, zoom bottom-right.
class MapPane extends ConsumerStatefulWidget {
  const MapPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends ConsumerState<MapPane> {
  WorkspacePaneChromeController? _paneChrome;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = WorkspacePaneChromeScope.maybeOf(context);
    if (!identical(next, _paneChrome)) {
      _paneChrome?.unbindMap(this);
      _paneChrome = next;
    }
  }

  bool _mergeHover = false;
  WorkspaceController? _expansionWorkspace;
  void _showExpansionBlocked() {
    if (!mounted) return;
    final l = context.l10n;
    final expansion = ref.read(expansionControllerProvider(widget.studySetId));
    final generation = ref.read(mapGenerationControllerProvider(widget.studySetId));
    final running =
        expansion?.phase == ExpansionPhase.generating ||
        generation?.phase == MapGenerationPhase.reading ||
        generation?.phase == MapGenerationPhase.streaming;
    final message = running
        ? l.mapGenerateBlockedRunning
        : generation == null
        ? l.mapIdeaBlocked
        : generation.request.destination == MapGenerationDestination.update
        ? l.mapUpdateBlocked
        : l.mapGenerateBlocked;
    MMHud.show(context, message, icon: MMIcons.info);
  }

  final _headerGeometry = MapHeaderGeometry();
  bool _touchSelection = false;
  bool _toolbarBusy = false;
  Completer<void>? _pendingEditCommit;

  /// A toolbar press first saves the field that is losing focus. Waiting for
  /// the controller to close that edit also keeps slow writes in the right
  /// undo transaction before a second node is created.
  Future<void> _runToolbarAction(FutureOr<void> Function() action) async {
    if (_toolbarBusy) return;
    _toolbarBusy = true;
    try {
      final provider = workspaceProvider(widget.studySetId);
      final before = ref.read(provider);
      if (before.editingCardId != null || before.editingMarkId != null) {
        final finished = Completer<void>();
        _pendingEditCommit = finished;
        final subscription = ref.listenManual(provider.select((s) => (s.editingCardId, s.editingMarkId)), (_, next) {
          if (next.$1 == null && next.$2 == null && !finished.isCompleted) finished.complete();
        }, fireImmediately: true);
        _focus.requestFocus();
        try {
          await finished.future;
        } finally {
          subscription.close();
          _pendingEditCommit = null;
        }
        if (!mounted) return;
        // An empty new node was discarded: don't apply the click to the
        // previous selection restored by the cancellation.
        if (before.editingCardId != null && ref.read(provider).selectedCardId != before.editingCardId) return;
      }
      if (mounted) await action();
    } finally {
      _toolbarBusy = false;
    }
  }

  Future<void> _merge() async {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    if (_mergeHover) setState(() => _mergeHover = false);
    final result = await controller.mergeSelected();
    if (!mounted || result == null) return;
    if (result.reason case final reason?) {
      MMHud.show(context, mapEditReasonText(context, reason));
      return;
    }
    final l = context.l10n;
    final cleanup = result.removedRelationCount + result.removedSummaryCount == 0
        ? ''
        : ' · ${l.mergeCleanup(result.removedRelationCount, result.removedSummaryCount)}';
    MMHud.show(
      context,
      '${l.mergedNodes}$cleanup',
      action: (
        l.undo,
        () {
          controller.undo();
        },
      ),
    );
  }

  Future<void> _summary() async {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final selected = ref.read(workspaceProvider(widget.studySetId)).selectedCardIds.toSet();
    await controller.addSummaryAndEdit(context.l10n.newSummaryLabel);
    if (!mounted) return;
    final id = ref.read(workspaceProvider(widget.studySetId)).editingMarkId;
    final summary = controller.content.summaries.where((s) => s.id == id).firstOrNull;
    if (summary == null) return;
    final extra = (controller.content.summaryRange(summary) ?? []).where((id) => !selected.contains(id)).length;
    if (extra > 0) MMHud.show(context, context.l10n.summaryIncludedNodes(extra));
  }

  final _transforms = <String, TransformationController>{};
  TransformationController get _transform =>
      _transforms.putIfAbsent(ref.read(workspaceProvider(widget.studySetId)).activeMapId, TransformationController.new);

  void _viewCommand(MindMapCommand command) {
    final target = _focus.context;
    if (target != null) Actions.invoke(target, MindMapIntent(command));
  }

  /// The style popover, the style it previews, and where it hangs.
  bool _styleOpen = false;
  bool _styleCustomOpen = false;
  (MapStructure, MapPalette)? _stylePreview;
  final _stylePortal = OverlayPortalController();
  static const _styleRegion = 'map-style';

  void _toggleStyle() {
    if (_styleOpen) {
      _closeStyle();
    } else {
      _stylePortal.show();
      setState(() => _styleOpen = true);
    }
  }

  void _closeStyle() {
    if (!_styleOpen) return;
    _stylePortal.hide();
    setState(() {
      _styleOpen = false;
      _styleCustomOpen = false;
      _stylePreview = null;
    });
    _focus.requestFocus();
  }

  // Survives canvas remounts when switching outline/map or active map.
  int _handledLocateTick = 0;
  final _focus = FocusNode(debugLabel: 'MindMap');

  @override
  void dispose() {
    _paneChrome?.unbindMap(this);
    if (_expansionWorkspace?.onExpansionBlocked == _showExpansionBlocked) {
      _expansionWorkspace?.onExpansionBlocked = null;
    }
    if (_pendingEditCommit case final pending? when !pending.isCompleted) pending.complete();
    for (final transform in _transforms.values) {
      transform.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final size = context.size ?? const Size(800, 600);
    final center = Offset(size.width / 2, size.height / 2);
    _transform.value = zoomMapAt(_transform.value, center, factor);
  }

  /// Image cards open a preview; text cards are edited in place.
  void rename(String cardId) {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final card = controller.content.card(cardId);
    if (card?.kind == CardKind.image && card?.imageFileName != null) {
      showCardImagePreview(context, card!.imageFileName!);
    } else {
      controller.beginEditing(cardId);
    }
  }

  /// A new topic opens for editing in place; Esc removes it again.
  Future<void> addTopic({bool asChild = false}) => ref
      .read(workspaceProvider(widget.studySetId).notifier)
      .addTopicAndEdit(context.l10n.newTopicName, asChild: asChild);

  /// A new note under the selection, open for editing like a new topic.
  Future<void> addNote() => ref.read(workspaceProvider(widget.studySetId).notifier).addNoteAndEdit();

  Future<void> _clipboard(MindMapCommand command) async {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    try {
      if (command == MindMapCommand.paste) {
        await controller.pasteSelection();
      } else {
        await controller.copySelection(cut: command == MindMapCommand.cut);
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    }
  }

  Future<void> _expandIdeas({ExpansionScope scope = ExpansionScope.children}) async {
    if (!MMPlatformCapabilities.current.assistant) return;
    final state = ref.read(workspaceProvider(widget.studySetId));
    if (state.mapView != MapViewMode.map ||
        (!state.rootSelected && state.selectedCardId == null) ||
        state.editingCardId != null ||
        state.selectedMarkId != null) {
      return;
    }
    final route = await ref.read(mapTaskRouteProvider((widget.studySetId, TaskType.mapExpand)).future);
    if (!mounted) return;
    if (route.issue != RoutingIssue.none && route.issue != RoutingIssue.unknown) {
      await _openNodeAssistant(boundsOf(context).deflate(80));
      return;
    }
    final current = ref.read(workspaceProvider(widget.studySetId));
    if (current.activeMapId != state.activeMapId ||
        current.selectedCardId != state.selectedCardId ||
        current.rootSelected != state.rootSelected ||
        !setEquals(current.selectedCardIds, state.selectedCardIds) ||
        current.mapView != MapViewMode.map) {
      return;
    }
    final controller = ref.read(expansionControllerProvider(widget.studySetId).notifier);
    try {
      final ids = state.rootSelected
          ? [state.activeMapId]
          : state.selectedCardIds.isEmpty
          ? [state.selectedCardId!]
          : state.selectedCardIds.toList();
      final parents = {
        for (final id in ids)
          ref
                  .read(workspaceProvider(widget.studySetId).notifier)
                  .content
                  .node(id, mapId: state.activeMapId)
                  ?.parentId ??
              state.activeMapId,
      };
      final request = controller.request(
        state.activeMapId,
        ids.first,
        targets: ids,
        scope: state.rootSelected ? ExpansionScope.map : scope,
        breadth: state.rootSelected ? 8 : null,
        commonParentId: {ExpansionScope.group, ExpansionScope.siblings}.contains(scope) ? parents.single : null,
      );
      if (state.rootSelected) {
        await controller.planMap(request);
      } else {
        await controller.start(request);
      }
    } on StateError {
      if (mounted) MMHud.show(context, context.l10n.mapIdeaBusy);
    }
    if (mounted) _focus.requestFocus();
  }

  Future<void> _keepExpansion() async {
    final count = await ref.read(expansionControllerProvider(widget.studySetId).notifier).keep();
    if (!mounted) return;
    if (count > 0) {
      MMHud.show(
        context,
        context.l10n.mapIdeaAdded(count),
        action: (context.l10n.undo, () => ref.read(workspaceProvider(widget.studySetId).notifier).undo()),
      );
    }
    _focus.requestFocus();
  }

  double _diffExtent = MMSizes.bottomSheetMedium;

  Future<void> _keepMapGeneration() async {
    final before = ref.read(mapGenerationControllerProvider(widget.studySetId));
    final count = await ref.read(mapGenerationControllerProvider(widget.studySetId).notifier).keep();
    if (!mounted) return;
    if (count > 0) {
      final title = before?.request.title ?? '';
      MMHud.show(
        context,
        before?.request.destination == MapGenerationDestination.update
            ? context.l10n.mapUpdateApplied(count)
            : context.l10n.mapGenerateCreated(title, count),
        action: (context.l10n.undo, () => ref.read(workspaceProvider(widget.studySetId).notifier).undo()),
      );
    }
    _focus.requestFocus();
  }

  void _command(MindMapCommand command) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    switch (command) {
      case MindMapCommand.generateFromDocument:
        if (!ref.read(settingsProvider).betaFeaturesEnabled) return;
        final state = ref.read(workspaceProvider(widget.studySetId));
        if (state.mapView == MapViewMode.outline) {
          controller.setMapView(MapViewMode.map);
        }
        showGenerateMapSheet(context, ref, widget.studySetId, preselectedDocId: state.activeDocumentId);
      case MindMapCommand.expandIdeas:
        _expandIdeas();
      case MindMapCommand.copy || MindMapCommand.cut || MindMapCommand.paste:
        _clipboard(command);
      case MindMapCommand.siblingAfter || MindMapCommand.siblingBefore:
        controller.addTopicAndEdit(l.newTopicName, siblingBefore: command == MindMapCommand.siblingBefore);
      case MindMapCommand.parent:
        controller.addTopicAndEdit(l.newTopicName, asParent: true);
      case MindMapCommand.promote:
        controller.promoteSelected();
      case MindMapCommand.relation:
        controller.addRelation();
      case MindMapCommand.merge:
        _merge();
      case MindMapCommand.summary:
        _summary();
      case MindMapCommand.expand:
        controller.toggleSelectedExpanded();
      default:
        break;
    }
  }

  /// The assistant's actions on [card] (null: the whole map).
  List<MMMenuEntry> _assistantEntries(Card? card) {
    if (!MMPlatformCapabilities.current.assistant) return const [];
    final l = context.l10n;
    final topic = card?.kind == CardKind.topic;
    // The root stands for the whole map: its branch is everything on it.
    void ask(AssistantSkill? skill, {bool branch = false}) => askAboutNode(
      ref,
      widget.studySetId,
      card?.id ?? assistantRootId,
      branch: branch,
      text: skill?.prompt(l),
      skill: skill?.name,
    );
    if (card == null) {
      return [
        MMMenuItem(l.mapIdeaExpandMap, () => _expandIdeas(), icon: MMIcons.expandIdeas),
        MMMenuItem(l.assistantOrganizeBranch, () => ask(AssistantSkill.organize, branch: true), icon: MMIcons.organize),
        MMMenuItem(l.assistantQuizBranch, () => ask(AssistantSkill.quiz, branch: true), icon: MMIcons.review),
      ];
    }
    final selection = ref.read(workspaceProvider(widget.studySetId));
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final sameParent =
        {for (final id in selection.selectedCardIds) content.node(id, mapId: selection.activeMapId)?.parentId}.length ==
        1;
    return [
      if (selection.selectedCardIds.length > 1)
        for (final (scope, label) in [
          (ExpansionScope.group, l.mapIdeaGroup),
          (ExpansionScope.siblings, l.mapIdeaFillSiblings),
        ])
          MMMenuItem(
            label,
            sameParent ? () => _expandIdeas(scope: scope) : null,
            icon: scope == ExpansionScope.group ? MMIcons.groupParent : MMIcons.fillSiblings,
            disabledReason: sameParent ? null : l.mapEditDifferentParents,
          ),
      MMMenuItem(
        l.mapIdeaExpand,
        () => _expandIdeas(),
        shortcut: defaultTargetPlatform == TargetPlatform.macOS
            ? describeShortcut(const SingleActivator(LogicalKeyboardKey.tab, alt: true))
            : null,
        icon: MMIcons.expandIdeas,
      ),
      MMMenuItem(
        topic ? l.assistantExplainTopic : l.assistantExplainCard,
        () => ask(AssistantSkill.explain),
        shortcut: describeShortcut(AppShortcuts.askAssistant),
        icon: MMIcons.explain,
      ),
      if (topic) ...[
        MMMenuItem(l.assistantOrganizeBranch, () => ask(AssistantSkill.organize, branch: true), icon: MMIcons.organize),
        MMMenuItem(l.assistantQuizBranch, () => ask(AssistantSkill.quiz, branch: true), icon: MMIcons.review),
      ],
      if (card.kind == CardKind.excerpt)
        MMMenuItem(l.assistantVerifyCard, () => ask(AssistantSkill.verify), icon: MMIcons.verify),
      MMMenuItem(l.assistantAskWith, () => ask(null), icon: MMIcons.ai),
    ];
  }

  /// The root has only the actions that apply to the whole map.
  Widget? _nodeBar(String? cardId, VoidCallback remove) {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final card = cardId == null ? null : controller.content.card(cardId);
    final root = ref.read(workspaceProvider(widget.studySetId)).rootSelected;
    if (card == null && !root) return null;
    return MapNodeBar(
      root: root,
      onEdit: card == null ? null : () => _runToolbarAction(() => rename(card.id)),
      onChild: () => _runToolbarAction(() => addTopic(asChild: true)),
      onSibling: () => _runToolbarAction(
        () => root
            ? addTopic(asChild: true)
            : controller.addTopicAndEdit(context.l10n.newTopicName, siblingBefore: false),
      ),
      onNote: () => _runToolbarAction(addNote),
      onImage: () => _runToolbarAction(() => pickAndInsertImages(context, ref, widget.studySetId)),
      onRelation: () => _runToolbarAction(controller.addRelation),
      onDelete: () => _runToolbarAction(remove),
      onAssistant: MMPlatformCapabilities.current.assistant
          ? (rect) => _runToolbarAction(() => _openNodeAssistant(rect))
          : null,
    );
  }

  Future<void> _openNodeAssistant(Rect toolbar) async {
    final state = ref.read(workspaceProvider(widget.studySetId));
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = controller.content;
    final id = state.rootSelected ? assistantRootId : state.selectedCardId;
    if (id == null) return;
    final ids = state.selectedCardIds.isEmpty ? [id] : [id, ...state.selectedCardIds.where((other) => other != id)];
    final contexts = [
      for (final nodeId in ids)
        nodeContext(
          mapId: state.activeMapId,
          nodeId: nodeId,
          title: nodeId == assistantRootId
              ? mapTitle(ref, widget.studySetId, state.activeMapId)
              : researchCardTitle(content, nodeId).isEmpty
              ? (content.card(nodeId)?.kind == CardKind.image ? context.l10n.imageExcerpt : context.l10n.newTopicName)
              : researchCardTitle(content, nodeId),
          branch: nodeId == assistantRootId,
          body: assistantNodeBody(content, nodeId),
        ),
    ];
    await showAssistantQuickActions(
      context,
      studySetId: widget.studySetId,
      passage: contexts.first,
      contexts: contexts,
      source: id == assistantRootId
          ? null
          : SourceAnchor(
              mapId: state.activeMapId,
              target: CardTarget(cardId: id),
            ),
      insertionTarget: (mapId: state.activeMapId, parentId: id == assistantRootId ? null : id),
      origin: PanelOrigin.map,
      expansionTargets: state.rootSelected ? [state.activeMapId] : ids,
      toolbar: toolbar,
      selection: toolbar,
      viewport: boundsOf(context),
    );
    if (mounted) _focus.requestFocus();
  }

  void _showNodeMenu(String? cardId, Offset position, Future<void> Function() remove) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = controller.content;
    final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final card = cardId == null ? null : content.card(cardId);
    final node = cardId == null ? null : content.node(cardId, mapId: mapId);
    final hasChildren = content.childrenOf(cardId, mapId: mapId).isNotEmpty;
    final now = ref.read(clockProvider)();
    // A leaf is a single card, not a branch.
    final branchDue = card != null && hasChildren && content.dueCount(now, mapId: mapId, branchId: card.id) > 0;
    final suspendable = card != null && (card.suspended || card.kind != CardKind.topic);

    showMMMenu(
      context,
      position: position,
      entries: [
        // Ask the assistant about the node: sent at once, or attached to ask freely.
        if (_assistantEntries(card) case final entries when entries.isNotEmpty) ...[
          MMMenuHeader(l.askAssistant),
          ...entries,
          const MMMenuDivider(),
        ],
        if (card != null) ...[
          if (ref.read(settingsProvider).betaFeaturesEnabled)
            MMMenuItem(
              l.organizeSelection,
              () => showNoteSetupSheet(
                context,
                ref,
                widget.studySetId,
                branch: BranchScope(ref.read(workspaceProvider(widget.studySetId)).activeMapId, card.id),
              ),
              badge: const MMBetaBadge(),
              icon: MMIcons.organizeNote,
            ),
          MMMenuItem(
            l.exportBranch,
            () => showMapExportSheet(context, ref, widget.studySetId, branchId: card.id),
            icon: MMIcons.export,
          ),
          MMMenuItem(l.cardTags, () => showCardTagsSheet(context, ref, widget.studySetId, card.id), icon: MMIcons.tag),
          MMMenuItem(
            l.showCardDetails,
            () => controller.showDetails(card.id),
            shortcut: describeShortcut(AppShortcuts.cardDetails),
            icon: MMIcons.info,
          ),
          MMMenuItem(
            card.kind == CardKind.image
                ? l.previewImage
                : card.kind == CardKind.note
                ? l.editNote
                : l.renameTitle,
            () => rename(card.id),
            shortcut: 'F2',
            icon: card.kind == CardKind.image ? MMIcons.image : MMIcons.editNote,
          ),
          if (card.source != null || content.annotation(card.annotationId ?? '') != null)
            MMMenuItem(
              l.revealSource,
              () => controller.revealCard(card.id),
              shortcut: '⌘L',
              icon: MMIcons.revealSource,
            ),
          if (node?.width != null)
            MMMenuItem(l.resetCardWidth, () => controller.setCardWidth(card.id, null), icon: MMIcons.fitWidth),
          const MMMenuDivider(),
        ],
        if (branchDue || suspendable) ...[
          if (branchDue)
            MMMenuItem(
              l.reviewBranch,
              () => controller.startReview(mapId: mapId, branchId: card.id),
              icon: MMIcons.review,
            ),
          if (suspendable)
            MMMenuItem(
              card.suspended ? l.resumeCard : l.suspendCard,
              () => controller.setSuspended(card.id, suspended: !card.suspended),
              icon: card.suspended ? MMIcons.play : MMIcons.pause,
            ),
          const MMMenuDivider(),
        ],
        MMMenuItem(l.addChildTopic, () => addTopic(asChild: true), shortcut: '⇥', icon: MMIcons.addTopic),
        MMMenuItem(l.addNote, addNote, icon: MMIcons.addNote),
        MMMenuItem(l.insertImage, () => pickAndInsertImages(context, ref, widget.studySetId), icon: MMIcons.image),
        if (card != null && hasChildren) ...[
          const MMMenuDivider(),
          MMMenuItem((node?.collapsed ?? false) ? l.expandNode : l.collapseNode, () {
            controller.toggleCollapsed(card.id);
          }, icon: (node?.collapsed ?? false) ? MMIcons.expand : MMIcons.collapse),
        ],
        if (card != null) ...[
          const MMMenuDivider(),
          MMMenuItem(l.moveUp, () => controller.shiftSelected(-1), shortcut: '⌘↑', icon: MMIcons.moveUp),
          MMMenuItem(l.moveDown, () => controller.shiftSelected(1), shortcut: '⌘↓', icon: MMIcons.moveDown),
          if (ref
              .read(workspaceProvider(widget.studySetId))
              .selectedCardIds
              .any((id) => content.annotation(content.card(id)?.annotationId ?? '') != null)) ...[
            const MMMenuDivider(),
            for (final color in MMAnnotationColor.values)
              MMMenuItem(
                l.colorName(color),
                () => controller.recolorCards(ref.read(workspaceProvider(widget.studySetId)).selectedCardIds, color),
                icon: MMIcons.palette,
              ),
          ],
          const MMMenuDivider(),
          if (ref.read(workspaceProvider(widget.studySetId)).selectedCardIds.length >= 2)
            MMMenuItem(
              l.mergeNodes(ref.read(workspaceProvider(widget.studySetId)).selectedCardIds.length),
              controller.mergeReason == null ? _merge : null,
              shortcut: '⌥⌘J',
              icon: MMIcons.mergeIntoMap,
            ),
          if (card.segments.length > 1)
            MMMenuItem(l.splitNodes(card.segments.length), () => controller.splitCard(card.id), icon: MMIcons.split),
          MMMenuItem(
            l.addRelation,
            () => _command(MindMapCommand.relation),
            shortcut: describeShortcut(_shortcutOf(MindMapCommand.relation)),
            icon: MMIcons.relation,
          ),
          MMMenuItem(
            l.addSummary,
            () => _command(MindMapCommand.summary),
            shortcut: describeShortcut(_shortcutOf(MindMapCommand.summary)),
            icon: MMIcons.summary,
          ),
          const MMMenuDivider(),
          for (final map in content.maps)
            if (map.id != mapId && content.node(card.id, mapId: map.id) == null)
              MMMenuItem(
                l.addToNamedMap(map.title.isEmpty ? l.mainMap : map.title),
                () => controller.placeCardInMap(card.id, map.id),
                icon: MMIcons.mindMap,
              ),
          MMMenuItem(l.removeFromMap, remove, destructive: true, shortcut: '⌫', icon: MMIcons.trash),
        ],
      ],
    );
  }

  static SingleActivator _shortcutOf(MindMapCommand command) =>
      mindMapShortcuts.entries.firstWhere((e) => e.value == command).key;

  /// Right click on a relation line or summary.
  void _showMarkMenu(String markId, Offset position) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final isRelation = controller.content.relations.any((r) => r.id == markId);
    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(l.editMarkLabel, () => controller.beginMarkEditing(markId), shortcut: 'F2', icon: MMIcons.editNote),
        const MMMenuDivider(),
        MMMenuItem(
          isRelation ? l.deleteRelation : l.deleteSummary,
          controller.removeSelectedMark,
          destructive: true,
          shortcut: '⌫',
          icon: MMIcons.trash,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    Widget menuLabel(String label, Widget icon) => Row(
      children: [
        SizedBox.square(
          dimension: MMSizes.dropdownIcon,
          child: IconTheme.merge(
            data: const IconThemeData(size: MMSizes.dropdownIcon),
            child: Center(child: icon),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        Expanded(child: Text(label)),
      ],
    );
    final provider = workspaceProvider(widget.studySetId);
    ref.listen(provider.select((s) => s.layout), (_, _) {
      if (_styleOpen) _closeStyle();
    });
    ref.listen(provider.select((s) => s.tagFilter), (previous, next) {
      if (next != null) {
        _closeStyle();
      } else if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    });
    ref.watch(
      provider.select(
        (s) => (
          s.activeMapId,
          s.tagFilter,
          s.selectedCardId,
          s.rootSelected,
          s.selectedCardIds,
          s.mapView,
          s.flashCardId,
          s.flashAnnotationId,
          s.flashCardIds,
          s.locateCardTick,
          s.editingCardId,
          s.selectedMarkId,
          s.editingMarkId,
          s.connectingFromId,
          s.expandedCardIds,
        ),
      ),
    );
    ref.listen(provider.select((s) => (s.activeMapId, s.selectedCardIds, s.mapView)), (_, _) {
      if (_mergeHover) setState(() => _mergeHover = false);
    });
    // Closing the details hands the keyboard back to the map and its node;
    // the view stays where it was.
    ref.listen(provider.select((s) => s.panel), (previous, next) {
      if (previous != RightPanel.details || next != null) return;
      // After the frame: the closing panel first gives up the focus it held.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    });
    // A preview belongs to the map it was opened on.
    ref.listen(provider.select((s) => (s.activeMapId, s.mapView)), (_, _) => _closeStyle());
    final expansion = ref.watch(expansionControllerProvider(widget.studySetId));
    final mapGen = ref.watch(mapGenerationControllerProvider(widget.studySetId));
    final diffReview =
        mapGen?.request.destination == MapGenerationDestination.update &&
        mapGen?.request.mapId == ref.read(provider).activeMapId &&
        (mapGen?.phase == MapGenerationPhase.diff || mapGen?.phase == MapGenerationPhase.stopped);
    final diffFocus = ref.watch(mapDiffFocusProvider(widget.studySetId));
    ref.listen(mapGenerationControllerProvider(widget.studySetId), (previous, next) {
      if (next?.request.destination == MapGenerationDestination.update &&
          previous?.request.destination != MapGenerationDestination.update) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              ref.read(mapGenerationControllerProvider(widget.studySetId))?.request.destination ==
                  MapGenerationDestination.update) {
            ref.read(workspaceProvider(widget.studySetId).notifier).setLayout(MMSplitMode.secondary);
          }
        });
      }
      if (previous != null &&
          (previous.phase == MapGenerationPhase.reading || previous.phase == MapGenerationPhase.streaming) &&
          previous.lines.isEmpty &&
          next == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) MMHud.show(context, context.l10n.mapIdeaStoppedEmpty);
        });
      }
      if (next != null && next.lines.isEmpty && next.phase == MapGenerationPhase.review && next.failure == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(ref.read(mapGenerationControllerProvider(widget.studySetId)), next)) return;
          ref.read(mapGenerationControllerProvider(widget.studySetId).notifier).discard();
          MMHud.show(
            context,
            next.request.destination == MapGenerationDestination.update
                ? context.l10n.mapUpdateNothing
                : context.l10n.mapGenerateNothing,
          );
        });
      }
    });
    ref.listen(expansionControllerProvider(widget.studySetId), (previous, next) {
      if (previous?.phase == ExpansionPhase.generating && previous!.drafts.isEmpty && next == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) MMHud.show(context, context.l10n.mapIdeaStoppedEmpty);
        });
      }
      if (next != null &&
          next.drafts.isEmpty &&
          (next.phase == ExpansionPhase.review || next.failure?.message == 'noValidExpansion')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(ref.read(expansionControllerProvider(widget.studySetId)), next)) return;
          ref.read(expansionControllerProvider(widget.studySetId).notifier).discard();
          MMHud.show(context, context.l10n.mapIdeaNothing);
        });
      }
    });
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    _expansionWorkspace = controller;
    controller.onExpansionBlocked = _showExpansionBlocked;
    final loadedContent = ref.watch(workspaceContentProvider(widget.studySetId));
    // The controller's copy includes its own writes before the stream
    // delivers them, so a node created for editing is there at once.
    final content = loadedContent == null ? StudySetContent.empty : controller.content;
    final selectedColors = <MMAnnotationColor>{};
    if (state.selectedCardIds.length >= 2) {
      final annotationIds = {
        for (final card in content.cards)
          if (state.selectedCardIds.contains(card.id))
            for (final segment in content.segmentsOf(card)) ?segment.annotationId,
      };
      for (final annotation in content.annotations) {
        if (annotationIds.contains(annotation.id)) {
          selectedColors.add(MMAnnotationColor.fromIndex(annotation.colorIndex));
        }
      }
    }
    final setTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';
    final mapTitle = content.map(state.activeMapId)?.title ?? '';
    final rootTitle = mapTitle.isEmpty ? setTitle : mapTitle;
    // Where new excerpts go, marked on the map once there is a document.
    final excerptTargetId = content.documents.isEmpty || !state.syncToMap
        ? null
        : StudySetEditor.excerptTarget(content, state.selectedCardId, mapId: state.activeMapId) ?? rootNodeId;

    Future<void> remove() async {
      final notice = await controller.removeSelected();
      if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
    }

    // The map runs on beneath a touch window's glass chrome; its controls
    // and the outline keep clear of it.
    final chrome = MMChromeInsets.of(context);
    final merged = WorkspaceToolbarScope.maybeOf(context) != null;
    final phone = MMInput.of(context).phone;
    final workspaceChrome = WorkspaceChromeScope.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _styleOpen ? workspaceChrome?.hold('map-style') : workspaceChrome?.release('map-style');
    });
    final outline = state.mapView != MapViewMode.map;
    final map = content.map(state.activeMapId);
    final canvasColors = outline ? c : mapCanvasColors(c, map?.backgroundColor);
    final single = state.selectedCardIds.length <= 1 && state.selectedCardId != null;
    final ready =
        expansion == null &&
        mapGen == null &&
        loadedContent != null &&
        state.selectedMarkId == null &&
        state.connectingFromId == null;
    final target = ready && (single || state.rootSelected);
    final insert = ready && state.selectedCardIds.length <= 1;
    final commandBar = MapCommandBar(
      key: const ValueKey('map-command-bar'),
      onChild: insert ? () => _runToolbarAction(() => addTopic(asChild: true)) : null,
      onSibling: target && single
          ? () => _runToolbarAction(() => controller.addTopicAndEdit(l.newTopicName, siblingBefore: false))
          : null,
      onRelation: ready && state.selectedCardIds.length <= 2 && state.selectedCardId != null
          ? () => _runToolbarAction(controller.addRelation)
          : null,
      onSummary: ready && controller.summaryReason == null ? () => _runToolbarAction(_summary) : null,
      summaryReason: controller.summaryReason,
      onNote: target && single ? () => _runToolbarAction(addNote) : null,
      onImage: insert ? () => _runToolbarAction(() => pickAndInsertImages(context, ref, widget.studySetId)) : null,
      onTags: target && single
          ? () => _runToolbarAction(() => showCardTagsSheet(context, ref, widget.studySetId, state.selectedCardId!))
          : null,
      onDetails: target && single ? () => _runToolbarAction(() => controller.showDetails(state.selectedCardId!)) : null,
    );
    _paneChrome?.bindMap(
      this,
      WorkspacePaneCommands(state.activeMapId, {
        'fit': WorkspacePaneCommand(() => _viewCommand(MindMapCommand.fit)),
        'center': WorkspacePaneCommand(() => _viewCommand(MindMapCommand.center)),
        'zoom-in': WorkspacePaneCommand(() => _zoom(1.25)),
        'zoom-out': WorkspacePaneCommand(() => _zoom(1 / 1.25)),
        'actual-size': WorkspacePaneCommand(() => _zoom(1 / mapScale(_transform.value))),
        'style': WorkspacePaneCommand(_toggleStyle, selected: _styleOpen),
      }),
    );
    void viewCommand(String id, VoidCallback fallback) {
      final adapter = _paneChrome?.map;
      if (adapter == null) {
        fallback();
      } else {
        adapter.execute(id);
      }
    }

    final locateButton = MMToolbarButton(
      key: const ValueKey('map-locate-selected'),
      icon: MMIcons.locate,
      tooltip: l.centerCurrentNode,
      onPressed: () => viewCommand('center', () => _viewCommand(MindMapCommand.center)),
    );

    final mapPane = LayoutBuilder(
      builder: (context, paneConstraints) {
        final bottomDiff = paneConstraints.maxWidth < MMSizes.mapDiffPanelWidth + MMSizes.mapMinWidth;
        final styleWidth = phone
            ? (paneConstraints.maxWidth - MMSpacing.m * 2).clamp(0.0, MMSizes.mapStylePopoverWidth)
            : MMSizes.mapStylePopoverWidth;
        Widget styleAnchor(Widget child) => MapStyleAnchor(
          controller: _stylePortal,
          above: phone,
          width: styleWidth,
          maxHeight: phone
              ? (paneConstraints.maxHeight - chrome.vertical - MMSpacing.m * 2).clamp(80.0, double.infinity)
              : double.infinity,
          popover: TapRegion(
            groupId: _styleRegion,
            onTapOutside: (_) {
              if (!_styleCustomOpen) _closeStyle();
            },
            child: SingleChildScrollView(
              child: MapStylePopover(
                density: map?.density ?? MapDensity.compact,
                onDensity: controller.setMapDensity,
                backgroundColor: map?.backgroundColor,
                onBackgroundColor: controller.setMapBackgroundColor,
                onCustomOpenChanged: (open) => _styleCustomOpen = open,
                structure: map?.structure ?? MapStructure.mind,
                palette: map?.palette ?? MapPalette.system,
                onPreview: (style) => setState(() => _stylePreview = style),
                onStructure: (structure) {
                  setState(() => _stylePreview = null);
                  controller.setMapStructure(structure);
                },
                onPalette: (palette) {
                  setState(() => _stylePreview = null);
                  controller.setMapPalette(palette);
                },
                onClose: _closeStyle,
              ),
            ),
          ),
          child: child,
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MMSegmentedControl<MapViewMode>(
              value: state.mapView,
              onChanged: (value) {
                if (expansion != null) {
                  _showExpansionBlocked();
                } else {
                  controller.setMapView(value);
                }
              },
              segments: [
                MMSegment(value: MapViewMode.map, label: l.mapView),
                MMSegment(value: MapViewMode.outline, label: l.outlineView),
              ],
            ),
            if (!outline) ...[
              const SizedBox(width: MMSpacing.s),
              styleAnchor(
                TapRegion(
                  groupId: _styleRegion,
                  child: MMToolbarButton(
                    key: const ValueKey('map-style-button'),
                    icon: MMIcons.mapStyle,
                    label: l.mapStyle,
                    tooltip: l.mapStyle,
                    selected: _styleOpen,
                    onPressed: _toggleStyle,
                  ),
                ),
              ),
              if (MMInput.touchInputOf(context)) ...[
                SizedBox(width: context.mmTablet ? MMToolbarSpacing.item : MMSpacing.s),
                MMToolbarButton(
                  key: const ValueKey('map-multi-select'),
                  icon: _touchSelection ? MMIcons.check : Icons.checklist,
                  label: l.mapMultiSelect,
                  tooltip: l.mapMultiSelect,
                  selected: _touchSelection,
                  onPressed: () => setState(() => _touchSelection = !_touchSelection),
                ),
              ],
            ],
            if (outline) ...[
              const SizedBox(width: MMSpacing.s),
              MMToolbarGroup(
                children: [
                  MMToolbarButton(
                    icon: MMIcons.trash,
                    tooltip: l.removeFromMap,
                    onPressed: state.selectedMarkId != null
                        ? controller.removeSelectedMark
                        : state.selectedCardId == null
                        ? null
                        : remove,
                  ),
                ],
              ),
            ],
            const SizedBox(width: MMSpacing.s),
            locateButton,
          ],
        );
        return ColoredBox(
          color: state.mapView == MapViewMode.map ? c.canvas : c.windowBackground,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomMultiChildLayout(
                  delegate: MapPaneHeaderLayout(
                    _headerGeometry,
                    top: chrome.top + (merged ? 0 : MMSpacing.s),
                    merged: merged,
                    phone: phone,
                  ),
                  children: [
                    LayoutId(
                      id: MapPaneSlot.canvas,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final toolbarTopInset = _headerGeometry.toolbarTopInset;
                          final isGenNewMap =
                              mapGen != null && mapGen.request.destination == MapGenerationDestination.newMap;
                          final canvasMapId = isGenNewMap ? mapGen.request.mapId : state.activeMapId;
                          final canvasRootTitle = isGenNewMap ? mapGen.request.title : rootTitle;
                          return SizedBox.expand(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: diffReview && !bottomDiff ? MMSizes.mapDiffPanelWidth : 0,
                                bottom: diffReview && bottomDiff ? paneConstraints.maxHeight * _diffExtent : 0,
                              ),
                              child: state.mapView == MapViewMode.map
                                  ? MindMapCanvas(
                                      key: ValueKey(canvasMapId),
                                      expansion:
                                          expansion ??
                                          (mapGen?.request.mapId == canvasMapId
                                              ? mapGen?.toExpansionPreview(content: content)
                                              : null),
                                      diffLines: diffReview ? mapGen!.lines : const [],
                                      diffFocusId: diffFocus,
                                      onDiffFocus: (id) =>
                                          ref.read(mapDiffFocusProvider(widget.studySetId).notifier).select(id),
                                      draftSources: {
                                        for (final line in mapGen?.lines ?? <MapLine>[])
                                          if (line.source != null) line.id: line.source!,
                                      },
                                      sourceDocumentIds:
                                          mapGen?.request.sources.map((s) => s.documentId).toList() ?? [],
                                      onRevealDraftSource: controller.revealMapSource,
                                      skeletons: mapGen?.phase == MapGenerationPhase.reading ? mapGen?.skeletons : null,
                                      onDraftToggleWithUndo: (id) => mapGen != null
                                          ? ref
                                                .read(mapGenerationControllerProvider(widget.studySetId).notifier)
                                                .toggleForClick(id)
                                          : ref
                                                .read(expansionControllerProvider(widget.studySetId).notifier)
                                                .toggleForClick(id),
                                      onDraftToggle: (id) {
                                        if (mapGen != null) {
                                          final current = ref.read(mapGenerationControllerProvider(widget.studySetId));
                                          final d = current?.lines.where((d) => d.id == id).firstOrNull;
                                          if (d != null) {
                                            ref
                                                .read(mapGenerationControllerProvider(widget.studySetId).notifier)
                                                .toggle(id, !d.kept);
                                          }
                                        } else if (expansion != null) {
                                          final d = ref
                                              .read(expansionControllerProvider(widget.studySetId))
                                              ?.drafts
                                              .where((d) => d.id == id)
                                              .firstOrNull;
                                          if (d == null) return;
                                          ref
                                              .read(expansionControllerProvider(widget.studySetId).notifier)
                                              .toggle(id, !d.kept);
                                        }
                                      },
                                      onDraftEdit: (id, text) {
                                        if (mapGen != null) {
                                          ref
                                              .read(mapGenerationControllerProvider(widget.studySetId).notifier)
                                              .edit(id, text);
                                        } else if (expansion != null) {
                                          ref
                                              .read(expansionControllerProvider(widget.studySetId).notifier)
                                              .edit(id, text);
                                        }
                                      },
                                      onDraftMore: (id) {
                                        if (mapGen == null && expansion != null) {
                                          ref
                                              .read(expansionControllerProvider(widget.studySetId).notifier)
                                              .continueFromDraft(id);
                                        }
                                      },
                                      onExpansionKeep: mapGen != null ? _keepMapGeneration : _keepExpansion,
                                      onExpansionBlocked: _showExpansionBlocked,
                                      onExpansionStop: () {
                                        if (mapGen != null) {
                                          ref.read(mapGenerationControllerProvider(widget.studySetId).notifier).stop();
                                        } else if (expansion != null) {
                                          ref.read(expansionControllerProvider(widget.studySetId).notifier).stop();
                                        }
                                      },
                                      onExpansionDiscard: () {
                                        if (mapGen != null) {
                                          ref
                                              .read(mapGenerationControllerProvider(widget.studySetId).notifier)
                                              .discard();
                                        } else if (expansion != null) {
                                          ref.read(expansionControllerProvider(widget.studySetId).notifier).discard();
                                        }
                                      },
                                      toolbarTopInset: toolbarTopInset,
                                      touchSelectionMode: _touchSelection,
                                      selectionToolbar: state.selectedCardIds.length < 2
                                          ? _nodeBar(state.selectedCardId, remove)
                                          : MapSelectionBar(
                                              count: state.selectedCardIds.length,
                                              mergeReason: controller.mergeReason,
                                              summaryReason: controller.summaryReason,
                                              onMerge: _merge,
                                              onSummary: _summary,
                                              onRelation: controller.addRelation,
                                              onDelete: remove,
                                              onAssistant: MMPlatformCapabilities.current.assistant
                                                  ? _openNodeAssistant
                                                  : null,
                                              onMergeHover: (hover) {
                                                if (_mergeHover != hover) setState(() => _mergeHover = hover);
                                              },
                                              onColor: selectedColors.isNotEmpty
                                                  ? (color) async {
                                                      await controller.recolorCards(state.selectedCardIds, color);
                                                      if (mounted) {
                                                        await ref.read(highlightPaletteProvider.notifier).record(color);
                                                      }
                                                    }
                                                  : null,
                                              color: selectedColors.length == 1 ? selectedColors.single : null,
                                            ),
                                      mergePreviewCardId: _mergeHover ? controller.mergeSurvivorId : null,
                                      flashAnnotationId: state.flashAnnotationId,
                                      onRevealSegment: controller.revealSegment,
                                      content: content,
                                      mapId: canvasMapId,
                                      rootTitle: canvasRootTitle,
                                      selectedCardId: state.selectedCardId,
                                      rootSelected: state.rootSelected,
                                      onSelectRoot: controller.selectMapRoot,
                                      onAssistant: MMPlatformCapabilities.current.assistant ? _openNodeAssistant : null,
                                      selectedCardIds: state.selectedCardIds,
                                      onToggleSelection: controller.toggleCardSelection,
                                      flashCardId: state.flashCardId,
                                      flashCardIds: state.flashCardIds,
                                      locateCardTick: state.locateCardTick > _handledLocateTick
                                          ? state.locateCardTick
                                          : 0,
                                      onLocated: (tick) {
                                        if (tick > _handledLocateTick) _handledLocateTick = tick;
                                      },
                                      transformation: _transform,
                                      focusNode: _focus,
                                      loaded: loadedContent != null,
                                      onSelect: controller.selectCard,
                                      onReveal: controller.revealCard,
                                      onRename: rename,
                                      onDelete: remove,
                                      onDeleteNote: (id) => _runToolbarAction(() => controller.removeAttachedNote(id)),
                                      onSelectMany: controller.selectCards,
                                      onMove: (id, parent, index) => controller.moveCards(
                                        state.selectedCardIds.contains(id) ? state.selectedCardIds : [id],
                                        parent,
                                        index: index,
                                      ),
                                      onToggleCollapsed: controller.toggleCollapsed,
                                      onNavigate: controller.selectNeighbor,
                                      onShift: controller.shiftSelected,
                                      onAddChild: () => addTopic(asChild: true),
                                      onCommand: _command,
                                      editingCardId: state.editingCardId,
                                      onEditDone: controller.finishEditing,
                                      onEditCancel: controller.cancelEditing,
                                      onContextMenu: (id, position) => _showNodeMenu(id, position, remove),
                                      selectedMarkId: state.selectedMarkId,
                                      editingMarkId: state.editingMarkId,
                                      connectingFromId: state.connectingFromId,
                                      onSelectMark: controller.selectMark,
                                      onEditMark: controller.beginMarkEditing,
                                      onDeleteMark: controller.removeSelectedMark,
                                      onMarkEditDone: controller.finishMarkEditing,
                                      onMarkEditCancel: controller.cancelMarkEditing,
                                      onConnect: controller.connectTo,
                                      onAdjustSummary: controller.adjustSummaryRange,
                                      onUpdateRelation: controller.updateRelation,
                                      onReverseRelation: controller.reverseRelation,
                                      onCancelConnect: controller.cancelConnecting,
                                      onMarkContextMenu: _showMarkMenu,
                                      excerptTargetId: excerptTargetId,
                                      previewCardIds: ref.watch(assistantPreviewProvider(widget.studySetId)),
                                      expandedCardIds: state.expandedCardIds,
                                      onToggleExpanded: controller.toggleExpanded,
                                      onOpenDetails: controller.showDetails,
                                      onResize: controller.setCardWidth,
                                      previewStyle: _styleOpen ? _stylePreview : null,
                                      // The map makes way for the popover and shows all of itself.
                                      fitInsets: _styleOpen && !context.mmTablet
                                          ? EdgeInsets.only(
                                              top: toolbarTopInset,
                                              right: MMSizes.mapStylePopoverWidth + MMSpacing.m * 2,
                                              bottom: chrome.bottom + MMSizes.toolbarHeight,
                                            )
                                          : null,
                                    )
                                  : OutlineView(
                                      contentPadding: EdgeInsets.fromLTRB(
                                        16,
                                        toolbarTopInset + MMSpacing.s,
                                        16,
                                        chrome.bottom + 72,
                                      ),
                                      key: ValueKey(state.activeMapId),
                                      content: content,
                                      mapId: canvasMapId,
                                      rootTitle: canvasRootTitle,
                                      selectedCardId: state.selectedCardId,
                                      rootSelected: state.rootSelected,
                                      onSelectRoot: controller.selectMapRoot,
                                      onAssistant: MMPlatformCapabilities.current.assistant ? _openNodeAssistant : null,
                                      selectedCardIds: state.selectedCardIds,
                                      onToggleSelection: controller.toggleCardSelection,
                                      focusNode: _focus,
                                      onSelect: controller.selectCard,
                                      onReveal: controller.revealCard,
                                      onRename: rename,
                                      onDelete: remove,
                                      onAddChild: () => addTopic(asChild: true),
                                      onShift: controller.shiftSelected,
                                      onCommand: _command,
                                      editingCardId: state.editingCardId,
                                      onEditDone: controller.finishEditing,
                                      onEditCancel: controller.cancelEditing,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    LayoutId(
                      id: MapPaneSlot.header,
                      child: merged
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                styleAnchor(
                                  TapRegion(
                                    groupId: _styleRegion,
                                    child: WorkspaceToolbar(
                                      leadingPadding: phone ? null : MMSpacing.l,
                                      label: l.moreTools,
                                      items: [
                                        MMToolbarItem(
                                          id: 'map-view',
                                          priority: 70,
                                          child: phone
                                              ? MMToolbarButton(
                                                  icon: MMIcons.readerNavigation,
                                                  tooltip: outline ? l.mapView : l.outlineView,
                                                  selected: outline,
                                                  onPressed: expansion == null
                                                      ? () => controller.setMapView(
                                                          outline ? MapViewMode.map : MapViewMode.outline,
                                                        )
                                                      : null,
                                                )
                                              : MMSegmentedControl<MapViewMode>(
                                                  value: state.mapView,
                                                  segments: [
                                                    MMSegment(value: MapViewMode.map, label: l.mapView),
                                                    MMSegment(value: MapViewMode.outline, label: l.outlineView),
                                                  ],
                                                  onChanged: expansion == null ? controller.setMapView : null,
                                                ),
                                          menuEntry: MMDropdownItem<VoidCallback>(
                                            value: () =>
                                                controller.setMapView(outline ? MapViewMode.map : MapViewMode.outline),
                                            enabled: expansion == null,
                                            child: menuLabel(
                                              outline ? l.mapView : l.outlineView,
                                              Icon(outline ? MMIcons.mindMap : MMIcons.outline),
                                            ),
                                          ),
                                        ),
                                        if (phone) ...[
                                          MMToolbarItem(
                                            id: 'actual-size',
                                            priority: 70,
                                            child: SizedBox(
                                              width: MMSizes.thumbDockButton.width,
                                              height: MMSizes.thumbDockButton.height,
                                              child: MMInteractive(
                                                tooltip: l.pdfActualSize,
                                                semanticLabel: l.pdfActualSize,
                                                onTap: () => _paneChrome?.map?.execute('actual-size'),
                                                builder: (context, _) => Center(
                                                  child: _ZoomLabel(transform: _transform, style: t.callout),
                                                ),
                                              ),
                                            ),
                                            menuEntry: MMDropdownItem<VoidCallback>(
                                              value: () => _paneChrome?.map?.execute('actual-size'),
                                              child: menuLabel(l.pdfActualSize, const Icon(MMIcons.actualSize)),
                                            ),
                                          ),
                                          for (final command in [
                                            ('fit', MMIcons.fitMap, l.fitMap),
                                            ('zoom-out', MMIcons.zoomOut, l.zoomOut),
                                            ('zoom-in', MMIcons.zoomIn, l.zoomIn),
                                          ])
                                            MMToolbarItem(
                                              id: command.$1,
                                              priority: 50,
                                              child: MMToolbarButton(
                                                icon: command.$2,
                                                tooltip: command.$3,
                                                onPressed: () => _paneChrome?.map?.execute(command.$1),
                                              ),
                                              menuEntry: MMDropdownItem<VoidCallback>(
                                                value: () => _paneChrome?.map?.execute(command.$1),
                                                child: menuLabel(command.$3, Icon(command.$2)),
                                              ),
                                            ),
                                        ],
                                      ],
                                      trailingItems: [
                                        MMToolbarItem(
                                          id: 'map-locate-selected',
                                          priority: 1000,
                                          child: locateButton,
                                          menuEntry: MMDropdownItem<VoidCallback>(
                                            value: () =>
                                                viewCommand('center', () => _viewCommand(MindMapCommand.center)),
                                            child: menuLabel(l.centerCurrentNode, const Icon(MMIcons.locate)),
                                          ),
                                        ),
                                      ],
                                      menuEntries: [
                                        MMDropdownSubmenu<VoidCallback>.items(
                                          key: const ValueKey('map-switch-menu'),
                                          label: l.switchMap,
                                          icon: MMIcons.mindMap,
                                          width: MMSizes.dropdownWideWidth,
                                          enabled: loadedContent != null,
                                          itemBuilder: (context) => [
                                            for (final target in content.maps)
                                              MMDropdownItem<VoidCallback>(
                                                key: ValueKey('map-switch-${target.id}'),
                                                icon: MMIcons.mindMap,
                                                value: () => _runToolbarAction(() async {
                                                  _closeStyle();
                                                  await controller.selectMap(target.id);
                                                }),
                                                child: Semantics(
                                                  selected: target.id == state.activeMapId,
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          target.title.isEmpty ? l.mainMap : target.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: context.mmText.callout,
                                                        ),
                                                      ),
                                                      if (target.id == state.activeMapId)
                                                        const Icon(MMIcons.check, size: 14),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        MMDropdownItem<VoidCallback>(
                                          key: const ValueKey('map-style-menu'),
                                          value: _toggleStyle,
                                          enabled: map != null,
                                          child: TapRegion(
                                            groupId: _styleRegion,
                                            child: menuLabel(l.mapStyle, const Icon(MMIcons.mapStyle)),
                                          ),
                                        ),
                                        if (MMInput.touchInputOf(context))
                                          MMDropdownItem<VoidCallback>(
                                            value: () => setState(() => _touchSelection = !_touchSelection),
                                            child: menuLabel(l.mapMultiSelect, const Icon(MMIcons.areaSelect)),
                                          ),
                                        if (outline)
                                          MMDropdownItem<VoidCallback>(
                                            value: remove,
                                            enabled: state.selectedCardId != null,
                                            child: menuLabel(l.removeFromMap, const Icon(MMIcons.trash)),
                                          ),
                                      ],
                                      trailingMenuEntries: [
                                        if (ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled)))
                                          generateMapMenuItem(context, ref, widget.studySetId),
                                      ],
                                    ),
                                  ),
                                ),
                                if (ref.watch(mapCommandBarVisibleProvider) && !outline)
                                  Padding(
                                    padding: const EdgeInsets.only(top: MMSpacing.s),
                                    child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: commandBar),
                                  ),
                              ],
                            )
                          : MapHeader(
                              title: Text(
                                mapTitle.isEmpty ? l.mainMap : mapTitle,
                                style: t.headline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              commands: outline || !ref.watch(mapCommandBarVisibleProvider)
                                  ? null
                                  : SingleChildScrollView(scrollDirection: Axis.horizontal, child: commandBar),
                              controls: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: outline
                                    ? controls
                                    : MMGlass(
                                        key: const ValueKey('map-view-glass'),
                                        toolbar: true,
                                        padding: context.mmToolbarPadding,
                                        child: controls,
                                      ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (expansion?.isMapPlan == true)
                Positioned(
                  top: MMSizes.ideaPlanTopInset,
                  left: 16,
                  right: 16,
                  bottom: 100,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ExpansionPlanSheet(studySetId: widget.studySetId),
                  ),
                ),
              if (expansion != null && !expansion.isMapPlan)
                Positioned(
                  left: MMSpacing.m,
                  right: MMSpacing.m,
                  bottom: MMSizes.ideaBarBottomInset + chrome.bottom,
                  child: Center(
                    child: ExpansionBar(studySetId: widget.studySetId, onKeep: _keepExpansion),
                  ),
                ),
              if (mapGen != null && !diffReview && mapGen.needsTextDocumentId == null)
                Positioned(
                  left: MMSpacing.m,
                  right: MMSpacing.m,
                  bottom: MMSizes.ideaBarBottomInset + chrome.bottom,
                  child: Center(
                    child: MapGenerationBar(studySetId: widget.studySetId, onKeep: _keepMapGeneration),
                  ),
                ),
              if (diffReview)
                Positioned(
                  top: bottomDiff ? 0 : _headerGeometry.toolbarTopInset,
                  bottom: chrome.bottom,
                  right: 0,
                  left: bottomDiff ? 0 : null,
                  width: bottomDiff ? null : MMSizes.mapDiffPanelWidth,
                  child: bottomDiff
                      ? NotificationListener<DraggableScrollableNotification>(
                          onNotification: (notification) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _diffExtent != notification.extent) {
                                setState(() => _diffExtent = notification.extent);
                              }
                            });
                            return false;
                          },
                          child: DraggableScrollableSheet(
                            initialChildSize: MMSizes.bottomSheetMedium,
                            minChildSize: (MMSizes.toolbarHeight * 3 / paneConstraints.maxHeight).clamp(
                              0.0,
                              MMSizes.bottomSheetMedium,
                            ),
                            snap: true,
                            snapSizes: const [MMSizes.bottomSheetMedium],
                            shouldCloseOnMinExtent: false,
                            builder: (_, scroll) => MapDiffPanel(
                              studySetId: widget.studySetId,
                              onApply: _keepMapGeneration,
                              scrollController: scroll,
                            ),
                          ),
                        )
                      : MapDiffPanel(studySetId: widget.studySetId, onApply: _keepMapGeneration),
                ),
              if (ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled)) &&
                  expansion == null &&
                  mapGen == null &&
                  content.nodes.every((n) => n.mapId != state.activeMapId) &&
                  state.mapView == MapViewMode.map)
                Positioned(
                  top: _headerGeometry.toolbarTopInset,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MapEmptyState(studySetId: widget.studySetId, mapId: state.activeMapId),
                ),
              Positioned(
                key: const ValueKey('map-document-notice'),
                top: _headerGeometry.toolbarTopInset + MMSpacing.s,
                left: MMSpacing.m,
                right: MMSpacing.m,
                child: MapOcrBanner(
                  studySetId: widget.studySetId,
                  fallback: DocumentMapBanner(studySetId: widget.studySetId),
                ),
              ),
              if (state.mapView == MapViewMode.map && !phone)
                Positioned(
                  left: MMSpacing.m,
                  right: MMSpacing.m + (diffReview && !bottomDiff ? MMSizes.mapDiffPanelWidth : 0),
                  bottom:
                      MMSpacing.m +
                      chrome.bottom +
                      (diffReview && bottomDiff ? paneConstraints.maxHeight * _diffExtent : 0),
                  child: WorkspaceChromeBar(
                    bottom: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: excerptTargetId == null
                              ? const SizedBox.shrink()
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: paneConstraints.maxWidth * .45),
                                    child: LayoutBuilder(
                                      builder: (context, labelBounds) {
                                        // View controls take priority when the pane cannot
                                        // even fit the excerpt icon and its label gap.
                                        if (labelBounds.maxWidth < 12 + MMSpacing.xs) return const SizedBox.shrink();
                                        return Row(
                                          children: [
                                            Icon(MMIcons.syncToMap, size: 12, color: canvasColors.secondaryLabel),
                                            const SizedBox(width: MMSpacing.xs),
                                            Flexible(
                                              child: _ExcerptTargetLabel(
                                                title: excerptTargetId == rootNodeId
                                                    ? rootTitle
                                                    : content.card(excerptTargetId)?.title ?? '',
                                                style: t.footnote.copyWith(color: canvasColors.secondaryLabel),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: MMSpacing.s),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: (paneConstraints.maxWidth - MMSpacing.m * 2 - MMSpacing.s).clamp(
                              0.0,
                              double.infinity,
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MMGlass(
                                  toolbar: true,
                                  borderRadius: BorderRadius.circular(16),
                                  padding: context.mmToolbarPadding,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      MMIconButton(
                                        icon: MMIcons.fitMap,
                                        tooltip: l.fitMap,
                                        onPressed: () => viewCommand('fit', () => _viewCommand(MindMapCommand.fit)),
                                      ),
                                      MMIconButton(
                                        icon: MMIcons.zoomOut,
                                        tooltip: l.zoomOut,
                                        size: 26,
                                        iconSize: 13,
                                        color: c.label,
                                        onPressed: () => viewCommand('zoom-out', () => _zoom(1 / 1.25)),
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: MMSizes.touchTarget),
                                        padding: EdgeInsets.symmetric(horizontal: context.mmTablet ? MMSpacing.xs : 0),
                                        width: context.mmTablet ? null : 44,
                                        height: context.mmTablet ? MMSizes.touchTarget : null,
                                        child: MMInteractive(
                                          tooltip: l.pdfActualSize,
                                          semanticLabel: l.pdfActualSize,
                                          onTap: () => _zoom(1 / mapScale(_transform.value)),
                                          builder: (context, _) => context.mmTablet
                                              ? Center(
                                                  child: _ZoomLabel(transform: _transform, style: t.callout),
                                                )
                                              : _ZoomLabel(transform: _transform, style: t.callout),
                                        ),
                                      ),
                                      MMIconButton(
                                        icon: MMIcons.zoomIn,
                                        tooltip: l.zoomIn,
                                        size: 26,
                                        iconSize: 13,
                                        color: c.label,
                                        onPressed: () => viewCommand('zoom-in', () => _zoom(1.25)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    return mapPane;
  }
}

/// The current zoom. Gestures, "fit" and view following change the
/// transform without rebuilding the pane, and the canvas may adjust it while
/// laying out, so the label rebuilds itself — after the frame if needed.
class _ZoomLabel extends StatefulWidget {
  const _ZoomLabel({required this.transform, required this.style});

  final TransformationController transform;
  final TextStyle style;

  @override
  State<_ZoomLabel> createState() => _ZoomLabelState();
}

class _ZoomLabelState extends State<_ZoomLabel> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ZoomLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform == widget.transform) return;
    oldWidget.transform.removeListener(_changed);
    widget.transform.addListener(_changed);
  }

  @override
  void dispose() {
    widget.transform.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) =>
      Text('${(mapScale(widget.transform.value) * 100).round()}%', textAlign: TextAlign.center, style: widget.style);
}

class _ExcerptTargetLabel extends StatelessWidget {
  const _ExcerptTargetLabel({required this.title, required this.style});
  final String title;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => Semantics(
    label: title,
    child: SizedBox(
      width: double.infinity,
      height: MediaQuery.textScalerOf(context).scale(style.fontSize!) * 1.6,
      child: CustomPaint(
        painter: _TargetLabelPainter(title, style, Directionality.of(context), MediaQuery.textScalerOf(context)),
      ),
    ),
  );
}

class _TargetLabelPainter extends CustomPainter {
  _TargetLabelPainter(this.title, this.style, this.direction, this.scaler);
  final String title;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    text.paint(canvas, Offset(0, (size.height - text.height) / 2));
    text.dispose();
  }

  @override
  bool shouldRepaint(_TargetLabelPainter old) =>
      old.title != title || old.style != style || old.direction != direction || old.scaler != scaler;
}
