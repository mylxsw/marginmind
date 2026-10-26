import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mm_design/mm_design.dart';

import 'l10n.dart';

/// Resolves package image names (`images/<hash>.png`) to files for the
/// [CardImage]s below it, so map, outline and review need no repository.
class CardImageScope extends InheritedWidget {
  const CardImageScope({super.key, required this.resolve, required super.child});

  final String Function(String fileName) resolve;

  static String Function(String fileName)? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardImageScope>()?.resolve;

  @override
  bool updateShouldNotify(CardImageScope oldWidget) => oldWidget.resolve != resolve;
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
  });

  final String fileName;
  final BoxFit fit;
  final String? semanticLabel;
  final bool fullResolution;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final resolve = CardImageScope.maybeOf(context);
    final placeholder = ColoredBox(
      color: c.quaternaryFill,
      child: Center(child: Icon(MMIcons.areaSelect, size: 18, color: c.secondaryLabel)),
    );
    if (resolve == null) return placeholder;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // Captures are large; decode at the shown width to keep memory low.
    return LayoutBuilder(
      builder: (context, box) => Image.file(
        File(resolve(fileName)),
        fit: fit,
        cacheWidth: !fullResolution && box.hasBoundedWidth && box.maxWidth >= 1 ? (box.maxWidth * ratio).ceil() : null,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// A modal image preview. Its scope is captured before opening the route.
Future<void> showCardImagePreview(BuildContext context, String fileName) {
  final resolve = CardImageScope.maybeOf(context);
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
                        : CardImageScope(resolve: resolve, child: CardImage(fileName, fullResolution: true)),
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
