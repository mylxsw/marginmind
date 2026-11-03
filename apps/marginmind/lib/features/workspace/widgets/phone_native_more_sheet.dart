import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../../vocabulary/hint_controls.dart';
import '../../vocabulary/vocabulary_hints.dart';
import '../reader_margin.dart';
import '../workspace_controller.dart';
import '../workspace_pane_chrome_controller.dart';

/// Uses the same UIKit presenter as the reader's outline and bookmarks.
Future<void> showPhoneNativeMoreSheet(
  BuildContext context, {
  required String studySetId,
  WorkspacePaneChromeController? paneChrome,
  BuildContext? workspaceContext,
  VoidCallback? onOrganizeNotes,
  bool appearance = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final l = context.l10n;
  final controller = container.read(workspaceProvider(studySetId).notifier);
  Map<String, Object?> row(
    String id,
    String title,
    String icon, {
    bool enabled = true,
    bool? selected,
    String? value,
    bool inline = false,
  }) => {
    'id': id,
    'title': title,
    'icon': icon,
    'enabled': enabled,
    'selected': ?selected,
    'value': ?value,
    'inline': inline,
  };
  Map<String, Object?> content() {
    final state = container.read(workspaceProvider(studySetId));
    final docs = controller.content.documents;
    final doc = docs.where((d) => d.id == state.activeDocumentId).firstOrNull;
    final studySet = container.read(studySetProvider(studySetId));
    final settings = container.read(settingsProvider);
    final commands = paneChrome?.reader?.commands;
    final margin = commands?['reader-margin'];
    final nav = commands?['reader-navigation'];
    final crop = commands?['reader-crop'];
    final reading = commands?['reader-settings'];
    final caps = doc?.capabilities();
    final index = docs.indexWhere((d) => d.id == state.activeDocumentId);
    return {
      'title': doc?.title.isNotEmpty == true ? doc!.title : (studySet?.title ?? ''),
      'close': l.phoneMoreClose,
      'back': l.phoneMoreBack,
      'undo': l.undo,
      'canUndo': state.canUndo,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'appearance': appearance,
      'appearanceTitle': l.readerAppearance,
      'styles': [
        for (final (style, label) in [
          (MMReaderStyle.white, l.readerStyleWhite),
          (MMReaderStyle.paper, l.readerStylePaper),
          (MMReaderStyle.green, l.readerStyleGreen),
          (MMReaderStyle.dark, l.readerStyleDark),
        ])
          {
            ...row('style-${style.name}', label, 'textformat', selected: settings.readerStyle == style, inline: true),
            'paper': style.paperColor.toARGB32(),
            'ink': style.inkColor.toARGB32(),
          },
      ],
      'tiles': [
        row('appearance', l.readerAppearance, 'textformat', inline: true),
        row(
          'margin',
          l.marginNotes,
          'captions.bubble',
          enabled: margin?.enabled ?? (caps?.marginNotes == true),
          selected:
              margin?.selected ?? container.read(readerMarginProvider(studySetId)).openDocuments.contains(doc?.id),
          inline: true,
        ),
        row(
          'vocabulary-hints',
          l.vocabularyHints,
          'book.closed',
          enabled: doc != null,
          selected: doc != null && container.read(vocabularyHintProvider).modeFor(doc.id) != VocabularyHintMode.off,
          inline: true,
        ),
      ],
      'groups': [
        [
          row(
            'outline',
            l.phoneMoreOutlineAndBookmarks,
            'square.3.layers.3d',
            enabled:
                nav?.enabled ??
                (caps?.outline == true ||
                    caps?.bookmarks == true ||
                    caps?.thumbnails == true ||
                    caps?.annotate == true),
          ),
          row(
            'switch-document',
            l.switchDocument,
            'books.vertical',
            value: '${index >= 0 ? index + 1 : 1} / ${docs.isEmpty ? 1 : docs.length}',
          ),
          if (reading?.enabled == true || caps?.readingSettings == true)
            row('reading-settings', l.readingSettings, 'textformat.size'),
          row('crop', l.cropMargins, 'crop', enabled: crop?.enabled ?? (caps?.crop == true)),
        ],
        [
          if (settings.betaFeaturesEnabled) row('organize-notes', l.organizeNotes, 'note.text'),
          row('review', l.review, 'brain', value: (studySet?.dueCount ?? 0) > 0 ? '${studySet!.dueCount}' : null),
          row('vocabulary', l.vocabularyTitle, 'book.closed'),
        ],
      ],
    };
  }

  final selected = await MMNativePresentation.actions(
    content: content(),
    onAction: (action) async {
      if (!context.mounted) return {};
      final docId = container.read(workspaceProvider(studySetId)).activeDocumentId;
      if (action == 'appearance' || action == 'back') {
        appearance = action == 'appearance';
      } else if (action.startsWith('style-')) {
        final style = MMReaderStyle.values.where((s) => 'style-${s.name}' == action).firstOrNull;
        if (style != null) await container.read(settingsProvider.notifier).setReaderStyle(style);
      } else if (action == 'margin') {
        final command = paneChrome?.reader?.commands['reader-margin'];
        if (command != null) {
          if (command.enabled) command.invoke?.call();
        } else if (docId != null) {
          container.read(readerMarginProvider(studySetId).notifier).toggle(docId);
        }
        // Reader commands publish their selection when the pane rebuilds.
        await WidgetsBinding.instance.endOfFrame;
      } else if (action == 'vocabulary-hints' && docId != null) {
        await changeVocabularyHint(context, () async {
          final owner = container.read(vocabularyHintProvider.notifier);
          final prefs = container.read(vocabularyHintProvider);
          final hidden = prefs.hiddenDocuments.contains(docId);
          if (hidden) await owner.setDocumentHidden(docId, false);
          if (!hidden || prefs.mode == VocabularyHintMode.off) await owner.toggle();
        });
      }
      return context.mounted ? content() : {};
    },
  );
  if (!context.mounted) return;
  switch (selected) {
    case 'undo':
      controller.undo();
    case 'outline':
      final command = paneChrome?.reader?.commands['reader-navigation'];
      if (command?.enabled == true) {
        command!.invoke?.call();
      } else {
        final doc = controller.content.documents
            .where((d) => d.id == container.read(workspaceProvider(studySetId)).activeDocumentId)
            .firstOrNull;
        final caps = doc?.capabilities();
        controller.showReaderPanel(
          caps?.outline == true
              ? ReaderPanelMode.outline
              : caps?.bookmarks == true
              ? ReaderPanelMode.bookmarks
              : caps?.thumbnails == true
              ? ReaderPanelMode.thumbnails
              : ReaderPanelMode.annotations,
        );
      }
    case 'switch-document':
      paneChrome?.reader?.execute('reader-switch-document');
    case 'reading-settings':
      paneChrome?.reader?.execute('reader-settings');
    case 'crop':
      paneChrome?.reader?.execute('reader-crop');
    case 'organize-notes':
      if (onOrganizeNotes != null) {
        onOrganizeNotes();
      } else {
        final target = workspaceContext ?? context;
        if (target.mounted) await showNoteSetupSheet(target, null, studySetId);
      }
    case 'review':
      controller.activateTab(WorkspaceTab.review);
    case 'vocabulary':
      controller.activateTab(WorkspaceTab.vocabulary);
  }
}
