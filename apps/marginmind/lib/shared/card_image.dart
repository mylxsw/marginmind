import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

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
  const CardImage(this.fileName, {super.key, this.fit = BoxFit.contain, this.semanticLabel});

  final String fileName;
  final BoxFit fit;
  final String? semanticLabel;

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
        cacheWidth: box.hasBoundedWidth && box.maxWidth >= 1 ? (box.maxWidth * ratio).ceil() : null,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
