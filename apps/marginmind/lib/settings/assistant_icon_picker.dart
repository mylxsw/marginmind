import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../shared/l10n.dart';
import 'app_settings.dart';

class AssistantIconPicker extends ConsumerWidget {
  const AssistantIconPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return MMSettingsRow(
      leading: Text(l.assistantIconTitle, style: context.mmText.body),
      trailing: MMSegmentedControl<MMAssistantPalette>(
        key: const ValueKey('settings-assistant-icon'),
        value: ref.watch(settingsProvider.select((settings) => settings.assistantIcon)),
        onChanged: ref.read(settingsProvider.notifier).setAssistantIcon,
        segments: [
          for (final (palette, label) in [
            (MMAssistantPalette.iris, l.assistantIconIris),
            (MMAssistantPalette.jade, l.assistantIconJade),
            (MMAssistantPalette.apricot, l.assistantIconApricot),
          ])
            MMSegment(
              value: palette,
              label: label,
              tooltip: label,
              child: MMAssistantIcon(
                key: ValueKey('assistant-icon-${palette.name}'),
                palette: palette,
                size: 20,
                animated: false,
              ),
            ),
        ],
      ),
    );
  }
}
