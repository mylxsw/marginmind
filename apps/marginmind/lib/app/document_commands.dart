import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

import '../features/workspace/workspace_browser.dart';

/// Shared entry point; overriding the handler with null hides the command.
typedef AddWebPageHandler = Future<void> Function(BuildContext context, WidgetRef ref, String studySetId);
final documentPlatformProvider = Provider<MMPlatformCapabilities>((ref) => MMPlatformCapabilities.current);
final addWebPageHandlerProvider = Provider<AddWebPageHandler?>((ref) => showAddWebPage);
final canAddWebPageProvider = Provider<bool>(
  (ref) => ref.watch(documentPlatformProvider).webBrowser && ref.watch(addWebPageHandlerProvider) != null,
);

Future<void> dispatchAddWebPage(BuildContext context, WidgetRef ref, String studySetId) async {
  if (!ref.read(canAddWebPageProvider)) return;
  await ref.read(addWebPageHandlerProvider)!(context, ref, studySetId);
}
