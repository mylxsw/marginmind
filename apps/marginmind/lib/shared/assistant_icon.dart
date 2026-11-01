import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../settings/app_settings.dart';

/// Assistant identity, following the user's saved colour preference.
class AssistantIcon extends ConsumerWidget {
  const AssistantIcon({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MMAssistantIcon(palette: ref.watch(settingsProvider.select((settings) => settings.assistantIcon)), size: size);
}
