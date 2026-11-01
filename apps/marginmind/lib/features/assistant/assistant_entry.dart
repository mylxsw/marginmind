import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../research/research_controller.dart' show researchPanelProvider;
import '../research/research_origin.dart' show researchCardTitle;
import '../workspace/workspace_controller.dart';
import 'assistant_controller.dart';
import 'assistant_reader.dart';
import 'assistant_scope.dart';

/// The skills the quick actions and the `/` menu offer, in their order.
enum AssistantSkill { explain, translate, verify, summarize, quiz, organize, papers, videos }

extension AssistantSkillText on AssistantSkill {
  IconData get icon => switch (this) {
    AssistantSkill.explain => MMIcons.explain,
    AssistantSkill.translate => MMIcons.translate,
    AssistantSkill.verify => MMIcons.verify,
    AssistantSkill.summarize => MMIcons.summarize,
    AssistantSkill.quiz => MMIcons.review,
    AssistantSkill.organize => MMIcons.organize,
    AssistantSkill.papers => MMIcons.paper,
    AssistantSkill.videos => MMIcons.video,
  };

  /// The quick action's label.
  String label(AppLocalizations l) => switch (this) {
    AssistantSkill.explain => l.assistantSkillExplain,
    AssistantSkill.translate => l.assistantSkillTranslate,
    AssistantSkill.verify => l.assistantSkillVerify,
    AssistantSkill.summarize => l.assistantSkillSummarize,
    AssistantSkill.quiz => l.assistantSkillQuiz,
    AssistantSkill.organize => l.assistantSkillOrganize,
    AssistantSkill.papers => l.assistantSkillPapers,
    AssistantSkill.videos => l.assistantSkillVideos,
  };

  /// The `/` command, without the slash.
  String command(AppLocalizations l) => switch (this) {
    AssistantSkill.quiz => l.assistantSkillQuizShort,
    AssistantSkill.organize => l.assistantSkillOrganizeShort,
    _ => label(l),
  };

  /// What a quick action sends.
  String prompt(AppLocalizations l) => switch (this) {
    AssistantSkill.explain => l.assistantPromptExplain,
    AssistantSkill.translate => l.assistantPromptTranslate,
    AssistantSkill.verify => l.assistantPromptVerify,
    AssistantSkill.summarize => l.assistantPromptSummarize,
    AssistantSkill.quiz => l.assistantPromptQuiz,
    AssistantSkill.organize => l.assistantPromptOrganize,
    AssistantSkill.papers => l.assistantPromptPapers,
    AssistantSkill.videos => l.assistantPromptVideos,
  };

  /// Whether answers need the network to be checked.
  bool get online => this == AssistantSkill.verify || this == AssistantSkill.papers || this == AssistantSkill.videos;
}

/// The page being read and the selected card, attached unless left out. A
/// pane that is not shown gives nothing: the source alone attaches no node,
/// the map alone no page.
final assistantAutoContextsProvider = Provider.family<List<ContextItem>, String>((ref, studySetId) {
  final s = ref.watch(
    workspaceProvider(studySetId).select(
      (s) => (
        s.layout,
        s.activeDocumentId,
        s.selectedCardId,
        s.activeMapId,
        s.content,
        s.tabs.active?.kind,
        s.activeNoteId,
      ),
    ),
  );
  final (layout, documentId, cardId, mapId, content, kind, noteId) = s;
  if (content == null || kind != WorkspaceTabKind.documentMap || noteId != null) return const [];
  final pages = ref.watch(readingPagesProvider(studySetId));
  final document = documentId == null ? null : content.document(documentId);
  return [
    if (document != null && layout != MMSplitMode.secondary)
      pageContext(document: document, page: pages[document.id] ?? document.lastPage, auto: true),
    if (cardId != null && layout != MMSplitMode.primary && content.node(cardId, mapId: mapId) != null)
      nodeContext(mapId: mapId, nodeId: cardId, title: researchCardTitle(content, cardId), auto: true),
  ];
}, dependencies: [workspaceProvider, readingPagesProvider]);

/// The contexts the next message carries: the attached ones, then the
/// automatic ones the user did not leave out or attach already.
List<ContextItem> outgoingContexts(AssistantUi ui, List<ContextItem> auto) {
  bool same(ContextItem a, ContextItem b) =>
      a.kind == b.kind &&
      a.documentId == b.documentId &&
      a.page == b.page &&
      a.mapId == b.mapId &&
      a.nodeId == b.nodeId;
  return [
    ...ui.contexts,
    for (final a in auto)
      if (!ui.suppressed.contains(a.id) && !ui.contexts.any((c) => same(c, a))) a,
  ];
}

/// Opens the assistant panel from [origin] with [contexts] attached. With
/// [text] the question is sent at once; otherwise the input takes focus.
void askAssistant(
  WidgetRef ref,
  String studySetId, {
  List<ContextItem> contexts = const [],
  Map<String, SourceAnchor> anchors = const {},
  String? text,
  String? skill,
  PanelOrigin origin = PanelOrigin.toolbar,
}) {
  if (!MMPlatformCapabilities.current.assistant) return;
  final ui = ref.read(assistantUiProvider(studySetId).notifier);
  for (final c in contexts) {
    ui.addContext(c, anchor: anchors[c.id]);
  }
  ui.showHistory(false);
  ref.read(researchPanelProvider(studySetId).notifier).closeNote();
  ref.read(workspaceProvider(studySetId).notifier).openPanel(RightPanel.assistant, origin: origin);
  if (text != null) {
    ui.ask(text, skill: skill);
  } else {
    ui.focus();
  }
}

/// Asks about a passage of a document: it is attached with its place.
void askAboutPassage(
  WidgetRef ref,
  String studySetId, {
  required String documentId,
  required List<AnnotationPage> pages,
  required String quote,
}) {
  if (pages.isEmpty || quote.trim().isEmpty) return;
  final item = selectionContext(documentId: documentId, page: pages.first.page, quote: quote);
  askAssistant(
    ref,
    studySetId,
    contexts: [item],
    anchors: {
      item.id: SourceAnchor(
        target: PdfTarget(documentId: documentId, pages: pages, quote: quote),
      ),
    },
    origin: PanelOrigin.reader,
  );
}

/// Asks about a node of the active map. [branch] attaches the node with
/// everything under it.
void askAboutNode(WidgetRef ref, String studySetId, String cardId, {bool branch = false, String? text, String? skill}) {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final mapId = ref.read(workspaceProvider(studySetId)).activeMapId;
  if (workspace.content.node(cardId, mapId: mapId) == null && cardId != assistantRootId) return;
  final title = cardId == assistantRootId
      ? mapTitle(ref, studySetId, mapId)
      : researchCardTitle(workspace.content, cardId);
  askAssistant(
    ref,
    studySetId,
    contexts: [
      nodeContext(
        mapId: mapId,
        nodeId: cardId,
        title: title,
        branch: branch,
        body: assistantNodeBody(workspace.content, cardId),
      ),
    ],
    text: text,
    skill: skill,
    origin: PanelOrigin.map,
  );
}

/// The map's title, or the study set's for an untitled map.
String mapTitle(WidgetRef ref, String studySetId, String mapId) {
  final title = ref.read(workspaceProvider(studySetId).notifier).content.map(mapId)?.title ?? '';
  return title.isNotEmpty ? title : (ref.read(studySetProvider(studySetId))?.title ?? '');
}

/// Sends [text] with the outgoing contexts. A leading `/command` picks its
/// skill; alone it sends the skill's own question. Ignored while an answer
/// is being written in any conversation (one run at a time per study set).
void assistantSend(WidgetRef ref, String studySetId, AppLocalizations l, String text, {String? skill}) {
  final controller = ref.read(assistantControllerProvider.notifier);
  if (controller.busy) return;
  var question = text.trim();
  if (skill == null && question.startsWith('/')) {
    for (final s in AssistantSkill.values) {
      final command = '/${s.command(l)}';
      if (question == command || question.startsWith('$command ')) {
        skill = s.name;
        question = question.substring(command.length).trim();
        if (question.isEmpty) question = s.prompt(l);
        break;
      }
    }
  }
  if (question.isEmpty) return;
  final ui = ref.read(assistantUiProvider(studySetId));
  final contexts = outgoingContexts(ui, ref.read(assistantAutoContextsProvider(studySetId)));
  try {
    unawaited(controller.send(question, contexts: contexts, skill: skill).catchError((Object _) {}));
  } on Object {
    return; // Too long or busy: the draft stays.
  }
  ref.read(assistantUiProvider(studySetId).notifier).sent();
}

/// ⌃⌘R and the toolbar button: opens the assistant with the input focused,
/// or closes it.
void toggleAssistant(WidgetRef ref, String studySetId) {
  if (ref.read(workspaceProvider(studySetId)).panel == RightPanel.assistant) {
    ref.read(workspaceProvider(studySetId).notifier).closePanel();
  } else {
    askAssistant(ref, studySetId);
  }
}
