import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'l10n.dart';

Uri normalizeWebInput(String input) => incomingShareUrl(input) ?? BrowserPolicy.normalize(input);

/// Clipboard access follows an explicit tap; never inspect it on app resume.
class PasteWebUrlButton extends StatelessWidget {
  const PasteWebUrlButton({super.key, required this.onPaste});
  final ValueChanged<Uri> onPaste;

  @override
  Widget build(BuildContext context) => MMButton(
    label: context.l10n.incomingSharePaste,
    onPressed: () async {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!context.mounted) return;
        final url = incomingShareUrl(data?.text ?? '');
        if (url == null) {
          MMHud.show(context, context.l10n.incomingShareClipboardEmpty);
        } else {
          onPaste(url);
        }
      } catch (_) {
        if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
      }
    },
  );
}
