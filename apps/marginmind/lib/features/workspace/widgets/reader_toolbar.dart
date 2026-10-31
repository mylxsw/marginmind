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
  final state = ref.read(workspaceProvider(studySetId));
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final reader = pane.reader;
  final document = workspace.content.document(state.activeDocumentId ?? '');
  void showReader(VoidCallback action) {
    ref.read(workspaceBrowserProvider(studySetId).notifier).hide();
    workspace.setLayout(MMSplitMode.primary);
    action();
  }

  PopupMenuEntry<VoidCallback> command(String id, String label) => MMDropdownItem<VoidCallback>(
    key: ValueKey(id),
    enabled: reader?.commands[id]?.enabled == true,
    value: () => pane.reader?.execute(id),
    child: Text(label),
  );
  return [
    MMDropdownItem(
      value: () {
        showReader(slots.openTools);
      },
      enabled: state.activeDocumentId != null,
      child: Text(l.phoneReaderTools),
    ),
    MMDropdownItem(
      value: () {
        showReader(slots.openScrub);
      },
      enabled: state.activeDocumentId != null,
      child: Text(l.goToPage),
    ),
    MMDropdownItem(
      value: () {
        workspace.setTool(AnnotationTool.select);
        slots.exitTools();
      },
      child: Text(l.phoneReaderExitTools),
    ),
    MMDropdownItem(value: () => workspace.undo(), enabled: state.canUndo, child: Text(l.undo)),
    const PopupMenuDivider(),
    ...workspaceEntries,
    const PopupMenuDivider(),
    command('reader-navigation', state.readerPanelVisible ? l.hideReaderSidebar : l.showReaderSidebar),
    command(l.switchDocument, l.switchDocument),
    command('reader-settings', l.readingSettings),
    command('reader-margin', l.marginNotes),
    command('vocabulary-hint-toggle', l.vocabularyHints),
    command('reader-crop', l.cropMargins),
    PopupMenuItem<VoidCallback>(
      enabled: false,
      child: document?.contentManifest != null
          ? ReaderZoomSlider.source(
              ratio: () {
                final session = ref.read(reflowSessionProvider((studySetId, document!.id)));
                return session.zoom / session.widthZoom;
              },
              ready: () => ref.read(reflowSessionProvider((studySetId, document!.id))).ready,
              onZoom: (ratio) {
                final session = ref.read(reflowSessionProvider((studySetId, document!.id)));
                session.zoomTo(ratio * session.widthZoom);
              },
              enabled: workspace.activeCapabilities.zoom,
            )
          : ReaderZoomSlider(pdf: ref.read(readerPdfProvider(studySetId)), enabled: workspace.activeCapabilities.zoom),
    ),
    for (final label in [l.pdfActualSize, l.pdfFitWidth, l.pdfFitPage]) command(label, label),
    const PopupMenuDivider(),
    for (final (style, label) in [
      (MMReaderStyle.white, l.readerStyleWhite),
      (MMReaderStyle.paper, l.readerStylePaper),
      (MMReaderStyle.green, l.readerStyleGreen),
      (MMReaderStyle.dark, l.readerStyleDark),
    ])
      MMDropdownItem<VoidCallback>(
        value: () => ref.read(settingsProvider.notifier).setReaderStyle(style),
        child: Text(label),
      ),
    const PopupMenuDivider(),
    PopupMenuItem<VoidCallback>(
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
    ),
    if (state.tool == AnnotationTool.ink)
      PopupMenuItem<VoidCallback>(
        enabled: false,
        child: ReaderInkToolbar(state: state, controller: workspace, onUndo: () => workspace.undo()),
      ),
  ];
}
