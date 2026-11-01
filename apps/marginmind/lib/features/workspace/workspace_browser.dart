import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../shared/l10n.dart';
import 'workspace_controller.dart';
import 'web_conversion.dart';

class BrowserTabSession {
  const BrowserTabSession(this.session, {this.replacingDocumentId});
  final BrowserSession session;
  final String? replacingDocumentId;
  WorkspaceTab get tab => WorkspaceTab(WorkspaceTabKind.browser, browserId: session.id);
  String get title => session.title.trim().isEmpty ? session.url.host : session.title;
}

class WorkspaceBrowserState {
  const WorkspaceBrowserState({
    this.session,
    this.visible = false,
    this.replacingDocumentId,
    this.converting = false,
    this.pages = const [],
  });
  final BrowserSession? session;
  final bool visible;
  final String? replacingDocumentId;
  final bool converting;
  final List<BrowserTabSession> pages;
  BrowserTabSession? page(int? id) => pages.where((p) => p.session.id == id).firstOrNull;
}

final workspaceBrowserProvider = NotifierProvider.autoDispose.family<WorkspaceBrowser, WorkspaceBrowserState, String>(
  WorkspaceBrowser.new,
  dependencies: [workspaceProvider],
);

/// GUL-577 installs the conversion sheet here. The browser owns navigation and
/// capture; the converter owns formats, previews and study-set persistence.
typedef BrowserConverter = Future<void> Function(BuildContext context, String studySetId, BrowserSession session);
final browserConverterProvider = Provider<BrowserConverter?>(
  (ref) =>
      (context, id, session) => showWebConversion(context, ref, id, session),
  dependencies: [workspaceBrowserProvider, workspaceProvider],
);

class WorkspaceBrowser extends Notifier<WorkspaceBrowserState> {
  WorkspaceBrowser(this.studySetId);
  final String studySetId;
  final _pages = <int, BrowserTabSession>{};
  int? _selectedId;
  bool _converting = false;

  @override
  WorkspaceBrowserState build() {
    ref.listen(workspaceProvider(studySetId).select((s) => s.tabs), (_, tabs) {
      final openIds = tabs.open.where((t) => t.kind == WorkspaceTabKind.browser).map((t) => t.browserId).toSet();
      for (final id in _pages.keys.toList()) {
        if (!openIds.contains(id)) _disposePage(id);
      }
      if (tabs.active?.kind == WorkspaceTabKind.browser) _selectedId = tabs.active!.browserId;
      _publish();
    });
    ref.onDispose(() {
      for (final page in _pages.values) {
        page.session.removeListener(_changed);
        page.session.dispose();
      }
      _pages.clear();
    });
    return const WorkspaceBrowserState();
  }

  void open(Uri url, {String? documentId}) {
    // Reopening the same URL activates its existing session without reloading it.
    final existing = _pages.values
        .where((p) => p.session.url == url && p.replacingDocumentId == documentId)
        .firstOrNull;
    if (existing != null) {
      show(existing.session.id);
      return;
    }
    late final BrowserSession session;
    session = BrowserSession(url, onDataCleared: () => close(session.id));
    session.addListener(_changed);
    final page = BrowserTabSession(session, replacingDocumentId: documentId);
    _pages[session.id] = page;
    _selectedId = session.id;
    _publish();
    ref.read(workspaceProvider(studySetId).notifier).activateTab(page.tab);
    _publish();
  }

  void _changed() => _publish();

  void _publish() {
    final page = _pages[_selectedId];
    state = WorkspaceBrowserState(
      session: page?.session,
      visible: page != null && ref.read(workspaceProvider(studySetId)).tabs.activeId == page.tab.id,
      replacingDocumentId: page?.replacingDocumentId,
      converting: _converting,
      pages: List.unmodifiable(_pages.values),
    );
  }

  void show([int? id]) {
    final page = _pages[id ?? _selectedId];
    if (page == null) return;
    _selectedId = page.session.id;
    ref.read(workspaceProvider(studySetId).notifier).activateTab(page.tab);
    _publish();
  }

  void hide() {
    if (state.visible) ref.read(workspaceProvider(studySetId).notifier).activateTab(WorkspaceTab.documents);
  }

  bool beginConversion([int? sessionId]) {
    if (_converting || (sessionId != null && !_pages.containsKey(sessionId))) return false;
    _converting = true;
    _publish();
    return true;
  }

  void endConversion() {
    _converting = false;
    _publish();
  }

  void _disposePage(int id) {
    final page = _pages.remove(id);
    page?.session.removeListener(_changed);
    page?.session.dispose();
    if (_selectedId == id) _selectedId = _pages.keys.lastOrNull;
  }

  void close([int? id]) {
    final page = _pages[id ?? _selectedId];
    if (page == null) return;
    ref.read(workspaceProvider(studySetId).notifier).closeTab(page.tab.id);
    // The workspace listener owns disposal, including closing tabs elsewhere.
    _publish();
  }
}

String browserUrlError(BuildContext context, BrowserUrlError code) => switch (code) {
  BrowserUrlError.empty => context.l10n.webUrlEmpty,
  BrowserUrlError.invalid => context.l10n.webUrlInvalid,
  BrowserUrlError.scheme => context.l10n.webUrlScheme,
};

Future<void> showAddWebPage(BuildContext context, WidgetRef ref, String studySetId) async {
  if (!MMPlatformCapabilities.current.webBrowser) return;
  final url = await showMMSheet<Uri>(context: context, width: 540, builder: (_) => const _AddressDialog());
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
      titleTrailing: compact
          ? open
          : MMIconButton(
              icon: MMIcons.close,
              tooltip: context.l10n.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
      actions: [
        MMButton(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        if (!compact) open,
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: _focus,
            builder: (context, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focus.requestFocus,
              child: Container(
                height: context.mmTouchPlatform ? MMSizes.touchTarget : 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.mmColors.quaternaryFill,
                  borderRadius: BorderRadius.circular(MMRadii.field),
                  border: Border.all(color: _focus.hasFocus ? context.mmColors.accent : context.mmColors.hairline),
                ),
                child: Row(
                  children: [
                    Icon(MMIcons.web, size: 18, color: context.mmColors.secondaryLabel),
                    Container(
                      height: 20,
                      width: MMSizes.hairline,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: context.mmColors.separator,
                    ),
                    Expanded(
                      child: MMTextField(
                        controller: _text,
                        focusNode: _focus,
                        semanticLabel: context.l10n.webUrlLabel,
                        placeholder: 'https://',
                        plain: true,
                        autofocus: true,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => _open(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
