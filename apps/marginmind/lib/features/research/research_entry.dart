import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import 'research_intents.dart';
import 'research_origin.dart';
import 'widgets/research_launcher.dart';

/// Global bounds of [context]'s widget, to place the launcher beside it.
Rect? globalBounds(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Opens the launcher for a passage of a document: the origin takes the
/// passage's page geometry now, so later selections cannot change it.
/// [beforeShow] runs once the origin is ready (e.g. to put the selection
/// toolbar away); [context] must outlive it, so callers whose own widget
/// goes away pass their navigator's.
Future<void> researchPassage(
  BuildContext context,
  WidgetRef ref, {
  required String studySetId,
  required String documentId,
  required List<AnnotationPage> pages,
  required String quote,
  Rect? anchor,
  ResearchIntent? intent,
  VoidCallback? beforeShow,
}) async {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final document = workspace.content.document(documentId);
  if (document == null || pages.isEmpty || quote.trim().isEmpty) return;
  final pdf = ref.read(readerPdfProvider(studySetId));
  final rendering = ref.read(pdfRenderingEnabledProvider);
  final origin = await pdfOrigin(
    document: document,
    pages: pages,
    quote: quote,
    pageText: rendering ? pdf.pageText : null,
    outline: pdf.outline,
  );
  beforeShow?.call();
  if (!context.mounted) return;
  await showResearchLauncher(context, studySetId: studySetId, origin: origin, intent: intent, anchor: anchor);
}

/// Opens the launcher for a node of the active map.
Future<void> researchNode(
  BuildContext context,
  WidgetRef ref, {
  required String studySetId,
  required String cardId,
  Rect? anchor,
  ResearchIntent? intent,
}) async {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final mapId = ref.read(workspaceProvider(studySetId)).activeMapId;
  final content = workspace.content;
  if (content.card(cardId) == null || content.node(cardId, mapId: mapId) == null) return;
  final mapTitle = content.map(mapId)?.title ?? '';
  final rootTitle = mapTitle.isNotEmpty
      ? mapTitle
      : (ref.read(studySetProvider(studySetId))?.title ?? context.l10n.mainMap);
  final origin = nodeOrigin(content, cardId, mapId, rootTitle: rootTitle);
  if (origin.text.isEmpty) return;
  await showResearchLauncher(context, studySetId: studySetId, origin: origin, intent: intent, anchor: anchor);
}
