import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';

/// Inline provenance shared by fixed and reflow web documents.
class WebSourceAttribution extends StatelessWidget {
  const WebSourceAttribution({super.key, required this.document});
  final Document document;
  @override
  Widget build(BuildContext context) {
    final origin = document.origin;
    if (origin == null) return const SizedBox.shrink();
    final uri = Uri.parse(origin.url);
    return MMInteractive(
      semanticLabel: context.l10n.openOriginalPage,
      onTap: () => const ExternalLinks().open(uri),
      builder: (context, state) => Text(
        context.l10n.webSource(uri.host, origin.capturedAt.toLocal()),
        style: context.mmText.footnote.copyWith(
          color: context.mmColors.secondaryLabel,
          decoration: state.hovered ? TextDecoration.underline : null,
        ),
      ),
    );
  }
}
