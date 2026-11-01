import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A read-only, fit-width preview of every page in an in-memory PDF.
/// Pages are built lazily and rasterized for the current viewport and DPR;
/// this deliberately does not use the document's first-page thumbnail.
class MMPdfDataPreview extends StatelessWidget {
  const MMPdfDataPreview({
    super.key,
    required this.data,
    required this.sourceName,
    this.header,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final List<int> data;
  final String sourceName;
  final Widget? header;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  @override
  Widget build(BuildContext context) => PdfDocumentViewBuilder(
    documentRef: PdfDocumentRefData(
      data is Uint8List ? data as Uint8List : Uint8List.fromList(data),
      sourceName: sourceName,
      key: PdfDocumentRefKey(sourceName, [data]),
      useProgressiveLoading: false,
    ),
    loadingBuilder: loadingBuilder ?? (_) => const Center(child: CircularProgressIndicator()),
    errorBuilder: errorBuilder,
    builder: (context, document) {
      if (document == null) return const SizedBox.shrink();
      final offset = header == null ? 0 : 1;
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          key: const ValueKey('pdf-data-pages'),
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: document.pages.length + offset,
          itemBuilder: (context, index) {
            if (index < offset) return header!;
            final page = document.pages[index - offset];
            return Padding(
              key: ValueKey('pdf-data-page-${page.pageNumber}'),
              padding: const EdgeInsets.only(bottom: 16),
              child: AspectRatio(
                aspectRatio: page.width / page.height,
                child: PdfPageView(
                  document: document,
                  pageNumber: page.pageNumber,
                  backgroundColor: Colors.white,
                  decoration: const BoxDecoration(color: Colors.white),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
