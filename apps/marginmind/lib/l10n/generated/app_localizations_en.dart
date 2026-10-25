// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'MarginMind';

  @override
  String get libraryTitleAll => 'All Study Sets';

  @override
  String get libraryRecent => 'Recent';

  @override
  String get libraryStarred => 'Starred';

  @override
  String get libraryDue => 'Due for Review';

  @override
  String get librarySection => 'Library';

  @override
  String get libraryFolders => 'Folders';

  @override
  String get libraryUnfiled => 'Unfiled';

  @override
  String get libraryRecentlyDeleted => 'Recently Deleted';

  @override
  String librarySetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count study sets',
      one: '1 study set',
      zero: 'No study sets',
    );
    return '$_temp0';
  }

  @override
  String libraryDueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count cards due', one: '1 card due');
    return '$_temp0';
  }

  @override
  String get libraryContinue => 'Continue Learning';

  @override
  String get libraryAllHeading => 'All';

  @override
  String libraryLastPosition(String document, int page) {
    return 'Last read: $document · p. $page';
  }

  @override
  String get libraryNoDocumentsYet => 'No documents yet';

  @override
  String libraryCardMeta(int documents, int cards) {
    String _temp0 = intl.Intl.pluralLogic(documents, locale: localeName, other: '$documents docs', one: '1 doc');
    String _temp1 = intl.Intl.pluralLogic(cards, locale: localeName, other: '$cards cards', one: '1 card');
    return '$_temp0 · $_temp1';
  }

  @override
  String dueBadge(int count) {
    return '$count due';
  }

  @override
  String get relativeJustNow => 'Just now';

  @override
  String relativeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count minutes ago', one: '1 minute ago');
    return '$_temp0';
  }

  @override
  String relativeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count hours ago', one: '1 hour ago');
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'Yesterday';

  @override
  String relativeDays(int count) {
    return '$count days ago';
  }

  @override
  String relativeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count weeks ago', one: 'Last week');
    return '$_temp0';
  }

  @override
  String relativeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count months ago', one: 'Last month');
    return '$_temp0';
  }

  @override
  String get viewAsIcons => 'Icons';

  @override
  String get viewAsList => 'List';

  @override
  String get sortRecent => 'Recent';

  @override
  String get sortTitle => 'Name';

  @override
  String get sortCards => 'Card count';

  @override
  String sortBy(String field) {
    return 'By $field';
  }

  @override
  String get sortTooltip => 'Sort order';

  @override
  String get search => 'Search';

  @override
  String get searchLibrary => 'Search study sets';

  @override
  String get newStudySet => 'New Study Set';

  @override
  String get newFolder => 'New Folder';

  @override
  String get firstRunTitle => 'Start your first study set';

  @override
  String get firstRunMessage =>
      'Drop one or more PDFs here and MarginMind will create a study set for them. Your highlights, cards and mind maps all live inside it.';

  @override
  String get openSample => 'Open Sample Study Set';

  @override
  String get noResultTitle => 'No matching study sets';

  @override
  String noResultSearch(String query) {
    return 'No study set name contains “$query”.';
  }

  @override
  String get noResultFilter => 'Nothing here yet. Drag study sets onto a folder in the sidebar.';

  @override
  String get columnName => 'Name';

  @override
  String get columnFolder => 'Folder';

  @override
  String get columnDocuments => 'Docs';

  @override
  String get columnCards => 'Cards';

  @override
  String get columnDue => 'Due';

  @override
  String get columnLastOpened => 'Last Opened';

  @override
  String get star => 'Star';

  @override
  String get unstar => 'Remove Star';

  @override
  String get open => 'Open';

  @override
  String get sheetName => 'Name';

  @override
  String get sheetNamePlaceholder => 'e.g. Cognitive Psychology';

  @override
  String get sheetLocation => 'Location';

  @override
  String get sheetColor => 'Color';

  @override
  String get sheetImportAfterCreate => 'Import PDFs after creating…';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get done => 'Done';

  @override
  String createdHud(String name) {
    return 'Created “$name”';
  }

  @override
  String get colorYellow => 'Yellow';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPurple => 'Purple';

  @override
  String get showLibrary => 'Show Library';

  @override
  String get hideSidebar => 'Hide Sidebar';

  @override
  String get showSidebar => 'Show Sidebar';

  @override
  String get searchInSet => 'Search';

  @override
  String get sectionMaps => 'Mind Maps';

  @override
  String get sectionDocuments => 'Documents';

  @override
  String get sectionLearn => 'Learn';

  @override
  String get mainMap => 'Main Map';

  @override
  String get review => 'Review';

  @override
  String get tags => 'Tags';

  @override
  String get importDocument => 'Import Document…';

  @override
  String get noSidebarMatches => 'No matches';

  @override
  String get toggleAnnotationTool => 'Toggle Highlighter';

  @override
  String get toolSelect => 'Select';

  @override
  String get toolHighlight => 'Highlight';

  @override
  String get toolArea => 'Area Select';

  @override
  String get toolPen => 'Pen';

  @override
  String get toolText => 'Text';

  @override
  String get syncToMapOn => 'Sync excerpts to map: On';

  @override
  String get syncToMapOff => 'Sync excerpts to map: Off';

  @override
  String get layoutReader => 'Source Only';

  @override
  String get layoutSplit => 'Split';

  @override
  String get layoutMap => 'Map Only';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String pageNumber(int page) {
    return 'Page $page';
  }

  @override
  String pageOf(int page, int total) {
    return '$page / $total';
  }

  @override
  String get readerEmptyTitle => 'Open a document to start reading';

  @override
  String get readerEmptyMessage => 'Pick a document in the sidebar, or import a PDF into this study set.';

  @override
  String get readerPlaceholder =>
      'PDF rendering arrives with the mm_pdf package. This page marks where it will appear.';

  @override
  String get mapEmptyTitle => 'Your excerpts will appear here';

  @override
  String get mapEmptyMessage => 'Highlight a sentence in the source and it becomes a card under the selected topic.';

  @override
  String get mapView => 'Map';

  @override
  String get outlineView => 'Outline';

  @override
  String newExcerptTarget(String topic) {
    return 'New excerpts → $topic';
  }

  @override
  String get addTopic => 'Add Topic';

  @override
  String get addNote => 'Add Note';

  @override
  String get removeFromMap => 'Remove from Map';

  @override
  String get zoomIn => 'Zoom In';

  @override
  String get zoomOut => 'Zoom Out';

  @override
  String get previousPage => 'Previous Page';

  @override
  String get nextPage => 'Next Page';

  @override
  String get closeTab => 'Close Tab';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get settings => 'Settings…';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get menuFile => 'File';

  @override
  String get menuView => 'View';

  @override
  String get menuWindow => 'Window';

  @override
  String get menuHelp => 'Help';

  @override
  String get componentGallery => 'Component Gallery';

  @override
  String get galleryTitle => 'Component Gallery';

  @override
  String get gallerySubtitle => 'mm_design · tokens and components';

  @override
  String get galleryColors => 'Colors';

  @override
  String get galleryTypography => 'Typography';

  @override
  String get galleryControls => 'Controls';

  @override
  String get galleryFeedback => 'Feedback';

  @override
  String get galleryShowHud => 'Show HUD';

  @override
  String get galleryShowSheet => 'Show Sheet';

  @override
  String get galleryHudMessage => 'Excerpted to “Patterns of forgetting”';

  @override
  String get back => 'Back';

  @override
  String get importPdf => 'Import PDF…';

  @override
  String importedHud(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count documents',
      one: 'Imported 1 document',
    );
    return '$_temp0';
  }

  @override
  String importFailed(String name) {
    return 'Couldn’t open “$name” as a PDF';
  }

  @override
  String get pdfFiles => 'PDF documents';

  @override
  String get excerptAction => 'Excerpt to Map';

  @override
  String get highlightAction => 'Highlight';

  @override
  String get copyAction => 'Copy';

  @override
  String get addToMapAction => 'Add to Map';

  @override
  String get deleteHighlight => 'Delete Highlight';

  @override
  String excerptedHud(String target) {
    return 'Excerpted to “$target”';
  }

  @override
  String get highlightedHud => 'Highlighted';

  @override
  String get copiedHud => 'Copied';

  @override
  String get removedHud => 'Removed from the map; the highlight stays in the source';

  @override
  String get highlightDeletedHud => 'Highlight deleted';

  @override
  String get rename => 'Rename…';

  @override
  String get renameTitle => 'Rename';

  @override
  String get editNote => 'Edit Note';

  @override
  String get save => 'Save';

  @override
  String get newTopicName => 'New Topic';

  @override
  String get newNoteText => 'New note';

  @override
  String get untitledExcerpt => 'Untitled excerpt';

  @override
  String get revealSource => 'Reveal in Source';

  @override
  String get menuMap => 'Map';

  @override
  String documentPages(int count) {
    return '$count pages';
  }

  @override
  String get sampleSetTitle => 'Sample: Forgetting & Spaced Repetition';

  @override
  String get sampleTopic1 => 'How we forget';

  @override
  String get sampleTopic2 => 'Spaced repetition';

  @override
  String get sampleTopic3 => 'Active recall';

  @override
  String get readerHintHighlight => 'Drag across text to excerpt it';

  @override
  String get readerHintSelect => 'Select text, then choose an action';

  @override
  String get outlineEmpty => 'Nothing in the outline yet';

  @override
  String get sampleDocTitle => 'Sample chapter: The forgetting curve';

  @override
  String get somethingWentWrong => 'Something went wrong. Please try again.';

  @override
  String get addChildTopic => 'Add Child Topic';

  @override
  String get backToStudySet => 'Back to Study Set';

  @override
  String get collapseNode => 'Collapse';

  @override
  String get expandNode => 'Expand';

  @override
  String get delete => 'Delete';

  @override
  String get deleteEllipsis => 'Delete…';

  @override
  String deleteStudySetTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get deleteStudySetMessage =>
      'Its documents, highlights, cards and review history will be deleted. This can’t be undone.';

  @override
  String deletedHud(String title) {
    return 'Deleted “$title”';
  }

  @override
  String get documentRemovedHud => 'Document removed';

  @override
  String get dropToCreateSet => 'Drop to create a study set';

  @override
  String get dropToImport => 'Drop to import into this study set';

  @override
  String get dropOnlyPdf => 'Only PDF files can be imported';

  @override
  String get exportMarkdown => 'Export Map as Markdown…';

  @override
  String get exportOpml => 'Export Map as OPML…';

  @override
  String get exportedHud => 'Exported';

  @override
  String get menuEdit => 'Edit';

  @override
  String get moveUp => 'Move Up';

  @override
  String get moveDown => 'Move Down';

  @override
  String get rateAgain => 'Again';

  @override
  String get rateHard => 'Hard';

  @override
  String get rateGood => 'Good';

  @override
  String get rateEasy => 'Easy';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get undoneHud => 'Undone';

  @override
  String get redoneHud => 'Redone';

  @override
  String get remove => 'Remove';

  @override
  String get removeDocumentEllipsis => 'Remove from Study Set…';

  @override
  String removeDocumentTitle(String title) {
    return 'Remove “$title”?';
  }

  @override
  String removeDocumentMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count highlights and their excerpt cards will be removed too. You can undo this with ⌘Z.',
      one: 'Its highlight and excerpt card will be removed too. You can undo this with ⌘Z.',
      zero: 'The document will be removed from this study set.',
    );
    return '$_temp0';
  }

  @override
  String get renameEllipsis => 'Rename…';

  @override
  String get renameDocument => 'Rename Document';

  @override
  String get renameStudySet => 'Rename Study Set';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review $count Cards',
      one: 'Review 1 Card',
    );
    return '$_temp0';
  }

  @override
  String get reviewTitle => 'Review';

  @override
  String reviewRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count left', one: '1 left');
    return '$_temp0';
  }

  @override
  String get reviewProgress => 'Review progress';

  @override
  String get reviewPromptExcerpt => 'Recall this excerpt';

  @override
  String get reviewPromptNote => 'Recall this note';

  @override
  String get reviewQuestionTip => 'Tip: rename an excerpt to a question and it becomes the prompt here.';

  @override
  String get reviewDoneTitle => 'All done for now';

  @override
  String reviewDoneMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You reviewed $count cards. Come back when more are due.',
      one: 'You reviewed 1 card. Come back when more are due.',
    );
    return '$_temp0';
  }

  @override
  String get reviewNothingDueTitle => 'Nothing to review';

  @override
  String get reviewNothingDueMessage => 'Excerpts and notes in the mind map show up here when they’re due.';

  @override
  String get showAnswer => 'Show Answer';

  @override
  String get startReview => 'Start Review';

  @override
  String get sectionCards => 'Cards';

  @override
  String intervalMinutes(int count) {
    return '$count min';
  }

  @override
  String intervalHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count hours', one: '1 hour');
    return '$_temp0';
  }

  @override
  String intervalDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count days', one: '1 day');
    return '$_temp0';
  }

  @override
  String intervalMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count months', one: '1 month');
    return '$_temp0';
  }

  @override
  String excerptInColor(String color) {
    return 'Excerpt in $color';
  }

  @override
  String get locateCard => 'Locate Card';

  @override
  String get excerptWithNote => 'Excerpt with Note';

  @override
  String get noteText => 'Note';

  @override
  String get addSiblingAfter => 'Add Sibling After';

  @override
  String get addSiblingBefore => 'Add Sibling Before';

  @override
  String get promoteNode => 'Promote Node';

  @override
  String get insertParentNode => 'Insert Parent';

  @override
  String get toggleNodeFold => 'Toggle Collapse';

  @override
  String get fitMap => 'Fit Map to Window';

  @override
  String get centerCurrentNode => 'Center on Current Node';

  @override
  String get cutNodes => 'Cut';

  @override
  String get pasteNodes => 'Paste';
}
