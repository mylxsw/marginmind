import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

/// GUL-575 connects showAddWebPage here; a missing handler hides the entry.
typedef AddWebPageHandler = Future<void> Function(BuildContext context, WidgetRef ref, String studySetId);
final documentPlatformProvider = Provider<MMPlatformCapabilities>((ref) => MMPlatformCapabilities.current);
final addWebPageHandlerProvider = Provider<AddWebPageHandler?>((ref) => null);
final canAddWebPageProvider = Provider<bool>(
  (ref) => ref.watch(documentPlatformProvider).webBrowser && ref.watch(addWebPageHandlerProvider) != null,
);

Future<void> dispatchAddWebPage(BuildContext context, WidgetRef ref, String studySetId) async {
  if (!ref.read(canAddWebPageProvider)) return;
  await ref.read(addWebPageHandlerProvider)!(context, ref, studySetId);
}
