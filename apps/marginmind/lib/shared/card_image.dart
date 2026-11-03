import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../settings/settings_window.dart';

import 'l10n.dart';

/// Resolves package image names (`images/<hash>.png`) to files for the
/// [CardImage]s below it, so map, outline and review need no repository.
class CardImageScope extends InheritedWidget {
  const CardImageScope({super.key, required this.resolve, this.studySetId, required super.child});

  final String Function(String fileName) resolve;
  final String? studySetId;

  static CardImageScope? scopeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CardImageScope>();

  static String Function(String fileName)? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardImageScope>()?.resolve;

  @override
  bool updateShouldNotify(CardImageScope oldWidget) =>
      oldWidget.resolve != resolve || oldWidget.studySetId != studySetId;
}

/// An image card's picture. A missing or unreadable file shows a quiet
/// placeholder of the same size instead of breaking the layout.
class CardImage extends StatelessWidget {
  const CardImage(
    this.fileName, {
    super.key,
    this.fit = BoxFit.contain,
    this.semanticLabel,
    this.fullResolution = false,
    this.displayScale = 1,
  });

  final String fileName;
  final BoxFit fit;
  final String? semanticLabel;
  final bool fullResolution;

  /// Scale applied by the containing canvas, in addition to screen density.
  final double displayScale;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final scope = CardImageScope.scopeOf(context);
    final resolve = scope?.resolve;
    final placeholder = ColoredBox(
      color: c.quaternaryFill,
      child: Center(child: Icon(MMIcons.areaSelect, size: 18, color: c.secondaryLabel)),
    );
    if (resolve == null) return placeholder;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // Include canvas zoom: layout constraints alone stay unchanged when the
    // map zooms. Half-step buckets reuse decodes through small zoom changes;
    // ResizeImage also keeps the result within the source's pixel dimensions.
    final scale = math.max(1.0, (displayScale * 2).ceil() / 2);
    Widget picture(ImageProvider image) => LayoutBuilder(
      builder: (context, box) => Image(
        image: ResizeImage.resizeIfNeeded(
          !fullResolution && box.hasBoundedWidth && box.maxWidth >= 1 ? (box.maxWidth * ratio * scale).ceil() : null,
          null,
          image,
        ),
        fit: fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: false,
        semanticLabel: semanticLabel,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
    Widget local() => picture(kIsWeb ? NetworkImage(resolve(fileName)) : FileImage(File(resolve(fileName))));
    if (scope?.studySetId == null) return local();
    return Consumer(
      builder: (context, ref, _) {
        final repo = ref.watch(contentRepositoryProvider);
        if (repo is! ReferencedResourceRepository) return local();
        final resource = ref.watch(_referencedImageProvider((scope!.studySetId!, fileName)));
        // Never keep a previously decoded image visible while revalidating.
        if (resource.isLoading) return placeholder;
        final value = resource.asData?.value;
        if (value?.availability == DocumentResourceAvailability.ready && value?.bytes != null) {
          return picture(MemoryImage(value!.bytes!));
        }
        return ColoredBox(
          color: c.quaternaryFill,
          child: Center(
            child: IconButton(
              tooltip: value?.availability == DocumentResourceAvailability.missing
                  ? context.l10n.syncResourceMissing
                  : context.l10n.syncResourceChanged,
              icon: Icon(MMIcons.warning, size: 18, color: c.secondaryLabel),
              onPressed: () => showSettings(context, tab: SettingsTab.sync),
            ),
          ),
        );
      },
    );
  }
}

/// A modal image preview. Its scope is captured before opening the route.
Future<void> showCardImagePreview(BuildContext context, String fileName) {
  final scope = CardImageScope.scopeOf(context);
  final resolve = scope?.resolve;
  if (MMInput.of(context).phone) {
    return showMMBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m),
              child: Row(
                children: [
                  Expanded(child: Text(context.l10n.previewImage, style: context.mmText.headline)),
                  MMIconButton(
                    icon: MMIcons.close,
                    tooltip: context.l10n.closePanel,
                    onPressed: () => Navigator.of(sheetContext).maybePop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.25,
                maxScale: 8,
                child: resolve == null
                    ? CardImage(fileName, fullResolution: true)
                    : CardImageScope(
                        resolve: resolve,
                        studySetId: scope?.studySetId,
                        child: CardImage(fileName, fullResolution: true),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: context.mmColors.card,
          insetPadding: const EdgeInsets.all(MMSpacing.xxl),
          child: Padding(
            padding: const EdgeInsets.all(MMSpacing.m),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: MMIconButton(
                    icon: MMIcons.close,
                    tooltip: context.l10n.closePanel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.25,
                    maxScale: 8,
                    child: resolve == null
                        ? CardImage(fileName, fullResolution: true)
                        : CardImageScope(
                            resolve: resolve,
                            studySetId: scope?.studySetId,
                            child: CardImage(fileName, fullResolution: true),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final _referencedImageProvider = StreamProvider.autoDispose.family<ReferencedResource, (String, String)>(
  retry: (_, _) => null,
  (ref, key) {
    final repo = ref.watch(contentRepositoryProvider) as ReferencedResourceRepository;
    return repo.watchReferencedResource(key.$1, key.$2);
  },
);
