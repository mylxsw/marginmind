import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/l10n.dart';
import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../phone_reader_controls_controller.dart';
import '../workspace_pane_chrome_controller.dart';
import '../workspace_controller.dart';
import '../reflow_session.dart';
import '../workspace_browser.dart';
import 'highlight_color_button.dart';
import 'underline_tool_button.dart';
import 'reader_ink_toolbar.dart';
import 'reader_zoom_control.dart';

import 'workspace_toolbar.dart';

/// Reader command presentation, independent of PDF and reflow sessions.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({
    super.key,
    required this.items,
    required this.menuEntries,
    required this.label,
    required this.overflowLabel,
  });
  final List<MMToolbarItem> items;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final String label;
  final String overflowLabel;
  @override
  Widget build(BuildContext context) => usePhoneReaderControls(context)
      ? const SizedBox.shrink()
      : WorkspaceToolbar(
          items: items,
          menuEntries: menuEntries,
          label: label,
          overflowLabel: overflowLabel,
          menuIcon: Icon(MMIcons.more, semanticLabel: label),
        );
}

/// Stage 3 can replace this menu without changing the reader's command adapter.
List<PopupMenuEntry<VoidCallback>> phoneReaderMenuEntries(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  WorkspacePaneChromeController pane,
  PhoneReaderControlsController slots, {
  List<PopupMenuEntry<VoidCallback>> workspaceEntries = const [],
}) {
  final l = context.l10n;
  final provider = workspaceProvider(studySetId);
  final workspace = ref.read(provider.notifier);
  final settings = ref.read(settingsProvider.notifier);
  void showReader(VoidCallback action) {
    ref.read(workspaceBrowserProvider(studySetId).notifier).hide();
    workspace.setLayout(MMSplitMode.primary);
    action();
  }

  PopupMenuEntry<VoidCallback> live(Widget Function(BuildContext, WidgetRef) builder) =>
      _PhoneReaderMenuEntry(pane: pane, builder: builder);
  PopupMenuEntry<VoidCallback> command(String id, String label) => live(
    (context, ref) => MMDropdownItem<VoidCallback>(
      key: ValueKey(id),
      enabled: pane.reader?.commands[id]?.enabled == true,
      value: () => pane.reader?.execute(id),
      child: Text(label),
    ),
  );
  return [
    live(
      (context, ref) => MMDropdownItem<VoidCallback>(
        value: () => showReader(slots.openTools),
        enabled: ref.watch(provider.select((s) => s.activeDocumentId)) != null,
        child: Text(l.phoneReaderTools),
      ),
    ),
    live(
      (context, ref) => MMDropdownItem<VoidCallback>(
        value: () => showReader(slots.openScrub),
        enabled: ref.watch(provider.select((s) => s.activeDocumentId)) != null,
        child: Text(l.goToPage),
      ),
    ),
    MMDropdownItem<VoidCallback>(
      value: () {
        workspace.setTool(AnnotationTool.select);
        slots.exitTools();
      },
      child: Text(l.phoneReaderExitTools),
    ),
    live(
      (context, ref) => MMDropdownItem<VoidCallback>(
        value: () => workspace.undo(),
        enabled: ref.watch(provider.select((s) => s.canUndo)),
        child: Text(l.undo),
      ),
    ),
    const PopupMenuDivider(),
    ...workspaceEntries,
    const PopupMenuDivider(),
    live(
      (context, ref) => MMDropdownItem<VoidCallback>(
        enabled: pane.reader?.commands['reader-navigation']?.enabled == true,
        value: () => pane.reader?.execute('reader-navigation'),
        child: Text(
          ref.watch(provider.select((s) => s.readerPanelVisible)) ? l.hideReaderSidebar : l.showReaderSidebar,
        ),
      ),
    ),
    command('reader-switch-document', l.switchDocument),
    command('reader-settings', l.readingSettings),
    command('reader-margin', l.marginNotes),
    command('vocabulary-hint-toggle', l.vocabularyHints),
    command('reader-crop', l.cropMargins),
    live((context, ref) {
      final state = ref.watch(provider);
      final document = workspace.content.document(state.activeDocumentId ?? '');
      return PopupMenuItem<VoidCallback>(
        enabled: false,
        child: document?.contentManifest != null
            ? ReaderZoomSlider.source(
                key: ValueKey(document!.id),
                ratio: () {
                  final session = ref.read(reflowSessionProvider((studySetId, document.id)));
                  return session.zoom / session.widthZoom;
                },
                ready: () => ref.read(reflowSessionProvider((studySetId, document.id))).ready,
                onZoom: (ratio) {
                  final session = ref.read(reflowSessionProvider((studySetId, document.id)));
                  session.zoomTo(ratio * session.widthZoom);
                },
                enabled: workspace.activeCapabilities.zoom,
              )
            : ReaderZoomSlider(
                pdf: ref.read(readerPdfProvider(studySetId)),
                enabled: workspace.activeCapabilities.zoom,
              ),
      );
    }),
    command('reader-zoom-actualSize', l.pdfActualSize),
    command('reader-zoom-fitWidth', l.pdfFitWidth),
    command('reader-zoom-fitPage', l.pdfFitPage),
    const PopupMenuDivider(),
    for (final (style, label) in [
      (MMReaderStyle.white, l.readerStyleWhite),
      (MMReaderStyle.paper, l.readerStylePaper),
      (MMReaderStyle.green, l.readerStyleGreen),
      (MMReaderStyle.dark, l.readerStyleDark),
    ])
      live(
        (context, ref) => MMDropdownItem<VoidCallback>(
          key: ValueKey('phone-reader-style-${style.name}'),
          value: () => settings.setReaderStyle(style),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              if (ref.watch(settingsProvider.select((s) => s.readerStyle)) == style)
                Icon(MMIcons.check, size: MMSizes.dropdownIcon),
            ],
          ),
        ),
      ),
    const PopupMenuDivider(),
    live((context, ref) {
      final state = ref.watch(provider);
      return PopupMenuItem<VoidCallback>(
        enabled: false,
        child: Row(
          children: [
            HighlightColorButton(
              color: state.color,
              selected: state.tool == AnnotationTool.highlight,
              enabled: workspace.activeCapabilities.annotate,
              onOpen: () => workspace.setTool(AnnotationTool.highlight),
              onChanged: workspace.setColor,
            ),
            UnderlineToolButton(studySetId: studySetId, enabled: workspace.activeCapabilities.annotate),
          ],
        ),
      );
    }),
    live((context, ref) {
      final state = ref.watch(provider);
      if (state.tool != AnnotationTool.ink) return const SizedBox.shrink();
      return PopupMenuItem<VoidCallback>(
        enabled: false,
        child: ReaderInkToolbar(state: state, controller: workspace, onUndo: () => workspace.undo()),
      );
    }),
  ];
}

/// Popup routes retain their entries; watch inside the route rather than caching
/// the workspace snapshot from the More button's build.
class _PhoneReaderMenuEntry extends PopupMenuEntry<VoidCallback> {
  const _PhoneReaderMenuEntry({required this.pane, required this.builder});
  final WorkspacePaneChromeController pane;
  final Widget Function(BuildContext, WidgetRef) builder;
  @override
  double get height => MMSizes.touchTarget;
  @override
  bool represents(VoidCallback? value) => false;
  @override
  State<_PhoneReaderMenuEntry> createState() => _PhoneReaderMenuEntryState();
}

class _PhoneReaderMenuEntryState extends State<_PhoneReaderMenuEntry> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.pane,
    builder: (context, _) => Consumer(builder: (context, ref, _) => widget.builder(context, ref)),
  );
}
