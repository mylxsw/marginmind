import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

IconData documentIcon(Document document) => document.origin != null
    ? MMIcons.web
    : switch (document.format) {
        DocumentFormat.epub || DocumentFormat.mobi || DocumentFormat.azw3 => MMIcons.ebook,
        DocumentFormat.markdown => MMIcons.markdown,
        DocumentFormat.web => MMIcons.web,
        _ => MMIcons.document,
      };
