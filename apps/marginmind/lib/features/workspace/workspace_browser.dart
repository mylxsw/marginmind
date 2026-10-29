import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../shared/l10n.dart';
import 'workspace_controller.dart';
import 'web_conversion.dart';

class WorkspaceBrowserState {
  const WorkspaceBrowserState({this.session, this.visible = false, this.replacingDocumentId, this.converting = false});
  final BrowserSession? session;
  final bool visible;
  final String? replacingDocumentId;
  final bool converting;
}

final workspaceBrowserProvider = NotifierProvider.autoDispose.family<WorkspaceBrowser, WorkspaceBrowserState, String>(
  WorkspaceBrowser.new,
);

/// GUL-577 installs the conversion sheet here. The browser owns navigation and
/// capture; the converter owns formats, previews and study-set persistence.
typedef BrowserConverter = Future<void> Function(BuildContext context, String studySetId, BrowserSession session);
final browserConverterProvider = Provider<BrowserConverter?>(
  (ref) =>
      (context, id, session) => showWebConversion(context, ref, id, session),
);

class WorkspaceBrowser extends Notifier<WorkspaceBrowserState> {
  WorkspaceBrowser(this.studySetId);
  final String studySetId;
  BrowserSession? _session;
  @override
  WorkspaceBrowserState build() {
    ref.onDispose(() {
      _session?.removeListener(_changed);
      _session?.dispose();
    });
    return const WorkspaceBrowserState();
  }

  void open(Uri url, {String? documentId}) {
    if (_session == null || _session!.disposed) {
      _session = BrowserSession(url, onDataCleared: close);
      _session!.addListener(_changed);
    } else {
      _session!.navigate(url);
    }
    state = WorkspaceBrowserState(session: _session, visible: true, replacingDocumentId: documentId);
    ref.read(workspaceProvider(studySetId).notifier).setLayout(MMSplitMode.primary);
  }

  void _changed() => state = WorkspaceBrowserState(
    session: _session,
    visible: state.visible,
    replacingDocumentId: state.replacingDocumentId,
    converting: state.converting,
  );

  void show() => state = WorkspaceBrowserState(
    session: _session,
    visible: true,
    replacingDocumentId: state.replacingDocumentId,
    converting: state.converting,
  );
  void hide() => state = WorkspaceBrowserState(
    session: _session,
    replacingDocumentId: state.replacingDocumentId,
    converting: state.converting,
  );
  bool beginConversion() {
    if (state.converting) return false;
    state = WorkspaceBrowserState(
      session: _session,
      visible: state.visible,
      replacingDocumentId: state.replacingDocumentId,
      converting: true,
    );
    return true;
  }

  void endConversion() => state = WorkspaceBrowserState(
    session: _session,
    visible: state.visible,
    replacingDocumentId: state.replacingDocumentId,
  );
  void close() {
    _session?.removeListener(_changed);
    _session?.dispose();
    _session = null;
    state = const WorkspaceBrowserState();
  }
}

String browserUrlError(BuildContext context, BrowserUrlError code) => switch (code) {
  BrowserUrlError.empty => context.l10n.webUrlEmpty,
  BrowserUrlError.invalid => context.l10n.webUrlInvalid,
  BrowserUrlError.scheme => context.l10n.webUrlScheme,
};

Future<void> showAddWebPage(BuildContext context, WidgetRef ref, String studySetId) async {
  if (!MMPlatformCapabilities.current.webBrowser) return;
  final url = await showMMSheet<Uri>(context: context, builder: (_) => const _AddressDialog());
  if (url != null && context.mounted) ref.read(workspaceBrowserProvider(studySetId).notifier).open(url);
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();
  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  BrowserUrlError? _error;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_selectAll);
  }

  void _selectAll() {
    if (_focus.hasFocus) _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    try {
      Navigator.of(context).pop(BrowserPolicy.normalize(_text.text));
    } on BrowserUrlException catch (error) {
      setState(() => _error = error.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MMBottomSheet.contains(context);
    final open = MMButton(label: context.l10n.open, variant: MMButtonVariant.primary, onPressed: _open);
    return MMSheet(
      title: context.l10n.addWebTitle,
      titleTrailing: compact ? open : null,
      actions: [
        MMButton(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        if (!compact) open,
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(MMIcons.web, size: MMSizes.dropdownIcon, color: context.mmColors.secondaryLabel),
              const SizedBox(width: MMSpacing.s),
              Expanded(
                child: MMTextField(
                  controller: _text,
                  focusNode: _focus,
                  placeholder: context.l10n.webUrlPlaceholder,
                  autofocus: true,
                  onSubmitted: (_) => _open(),
                ),
              ),
            ],
          ),
          Text(
            _error == null ? ' ' : browserUrlError(context, _error!),
            style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
          ),
        ],
      ),
    );
  }
}

/// The capture preview is the handoff boundary for GUL-577; it does not claim
/// to have saved a document. That task replaces this with its format sheet.
Future<void> previewBrowserCapture(BuildContext context, String studySetId, BrowserSession session) async {
  try {
    final capture = await session.capture(navigationId: session.navigationId);
    if (!context.mounted) return;
    await showMMSheet<void>(
      context: context,
      builder: (context) => MMSheet(
        title: context.l10n.browserConvert,
        actions: [MMButton(label: context.l10n.done, onPressed: () => Navigator.of(context).pop())],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(capture.title, style: context.mmText.headline),
            const SizedBox(height: MMSpacing.s),
            SelectableText(capture.url.toString(), style: context.mmText.body),
          ],
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong);
  }
}
