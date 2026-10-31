import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../workspace/reader_ocr.dart';
import '../../workspace/widgets/reader_ocr_controls.dart';
import '../../workspace/workspace_controller.dart';
import '../map_generation_controller.dart';

/// The source notice stays above the canvas, independently of generation controls.
class MapOcrBanner extends ConsumerStatefulWidget {
  const MapOcrBanner({super.key, required this.studySetId, this.fallback = const SizedBox.shrink()});
  final String studySetId;
  final Widget fallback;
  @override
  ConsumerState<MapOcrBanner> createState() => _MapOcrBannerState();
}

class _MapOcrBannerState extends ConsumerState<MapOcrBanner> {
  String? _dismissed;
  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(mapGenerationControllerProvider(widget.studySetId));
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = ref.watch(workspaceContentProvider(widget.studySetId)) ?? workspace.content;
    final id =
        preview?.needsTextDocumentId ??
        ref.watch(workspaceProvider(widget.studySetId).select((s) => s.activeDocumentId));
    final doc = content.document(id ?? '');
    if (doc == null || doc.format != DocumentFormat.pdf) return widget.fallback;
    final source = workspace.filePath(doc);
    ref.watch(readerOcrInspectionProvider(source));
    final ocr = ref.watch(readerOcrProvider(source));
    if (preview?.needsTextDocumentId == null && (ocr.document?.textPages.isEmpty != true || _dismissed == source)) {
      return widget.fallback;
    }
    final c = context.mmColors, l = context.l10n;
    return Container(
      key: const ValueKey('map-ocr-banner'),
      height: MMSizes.mapDocumentBanner,
      padding: const EdgeInsets.only(left: MMSpacing.m, right: MMSpacing.xs),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: MMSizes.hairline),
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      child: Row(
        children: [
          Icon(MMReaderIcons.area, size: MMSpacing.l, color: c.icon),
          const SizedBox(width: MMSpacing.s),
          Expanded(
            child: Text(l.mapBannerNeedsOcr, style: context.mmText.body, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: MMSpacing.s),
          if (ocr.running)
            ReaderOcrProgress(source: source)
          else
            MMButton(
              key: const ValueKey('map-ocr-recognize'),
              label: l.ocrTitle,
              variant: MMButtonVariant.primary,
              onPressed: ref.read(pdfOcrServiceProvider).supported
                  ? () => showReaderOcrOptions(context, ref, widget.studySetId, documentId: doc.id)
                  : null,
            ),
          MMIconButton(
            key: const ValueKey('map-ocr-close'),
            icon: MMIcons.close,
            tooltip: l.closePanel,
            onPressed: () {
              setState(() => _dismissed = source);
              if (preview?.needsTextDocumentId != null) {
                ref.read(mapGenerationControllerProvider(widget.studySetId).notifier).discard();
              }
            },
          ),
        ],
      ),
    );
  }
}
