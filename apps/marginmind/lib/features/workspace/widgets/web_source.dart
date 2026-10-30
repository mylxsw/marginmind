import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';

/// Compact provenance in the saved PDF's existing page navigation badge.
class WebSourceAttribution extends StatelessWidget {
  const WebSourceAttribution({super.key, required this.document});
  final Document document;
  @override
  Widget build(BuildContext context) {
    final origin = document.origin;
    if (origin == null) return const SizedBox.shrink();
    final uri = Uri.parse(origin.url);
    final source = context.l10n.webSource(uri.host, origin.capturedAt.toLocal());
    final style = context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: MMInteractive(
            semanticLabel: context.l10n.openOriginalPage,
            onTap: () => const ExternalLinks().open(uri),
            builder: (context, state) => Text(
              uri.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(decoration: state.hovered ? TextDecoration.underline : null),
            ),
          ),
        ),
        Flexible(
          child: Text(source.substring(uri.host.length), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}
