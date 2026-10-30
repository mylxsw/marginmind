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
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get done => 'Done';

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
  String get colorRed => 'Red';

  @override
  String get colorBlack => 'Black';

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
  String get toggleAreaTool => 'Toggle Area Select';

  @override
  String get toggleInkTool => 'Toggle Pen';

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
  String get inkFreehand => 'Freehand';

  @override
  String get inkEllipse => 'Circle';

  @override
  String get inkArrow => 'Arrow';

  @override
  String get inkEraser => 'Eraser';

  @override
  String get inkThin => 'Thin';

  @override
  String get inkMedium => 'Medium';

  @override
  String get inkBold => 'Bold';

  @override
  String get syncToMapOn => 'Sync excerpts to map: On';

  @override
  String get syncToMapOff => 'Sync excerpts to map: Off';

  @override
  String get annotationColor => 'Highlight Color';

  @override
  String get layoutReader => 'Source Only';

  @override
  String get layoutSplit => 'Split';

  @override
  String get layoutMap => 'Map Only';

  @override
  String get paneSource => 'Source';

  @override
  String get paneMap => 'Map';

  @override
  String get moreTools => 'More';

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
  String get readerEmptyMessage => 'Pick a document in the sidebar, or import one.';

  @override
  String get readerPlaceholder =>
      'PDF rendering arrives with the mm_pdf package. This page marks where it will appear.';

  @override
  String get mapEmptyTitle => 'Your excerpts will appear here';

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
  String get switchDocument => 'Switch Document';

  @override
  String get closeCurrentDocument => 'Close Current Document';

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
  String get excerptView => 'View';

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
  String get imageExcerpt => 'Image excerpt';

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
  String get reviewDoneTitle => 'All done for now';

  @override
  String reviewDoneMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards reviewed',
      one: '1 card reviewed',
    );
    return '$_temp0';
  }

  @override
  String get reviewNothingDueTitle => 'Nothing to review';

  @override
  String get showAnswer => 'Show Answer';

  @override
  String get startReview => 'Start Review';

  @override
  String get reviewBranch => 'Review Branch';

  @override
  String get reviewTag => 'Review Tag';

  @override
  String get suspendCard => 'Suspend Card';

  @override
  String get resumeCard => 'Resume Card';

  @override
  String get cardSuspended => 'Suspended';

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
  String get fitMap => 'Show Entire Map';

  @override
  String get centerCurrentNode => 'Locate Selected Node';

  @override
  String get cutNodes => 'Cut';

  @override
  String get pasteNodes => 'Paste';

  @override
  String get newMap => 'New Mind Map…';

  @override
  String get newMapName => 'Untitled Map';

  @override
  String get renameMap => 'Rename Mind Map…';

  @override
  String get deleteMap => 'Delete Mind Map';

  @override
  String addToNamedMap(String title) {
    return 'Add to “$title”';
  }

  @override
  String get cardTags => 'Tags…';

  @override
  String get sectionTags => 'Tags';

  @override
  String get addTag => 'Add Tag';

  @override
  String get removeTag => 'Remove Tag';

  @override
  String get allTags => 'All Tags';

  @override
  String get addRelation => 'Add Relationship';

  @override
  String get addSummary => 'Add Summary';

  @override
  String get newSummaryLabel => 'Summary';

  @override
  String get editMarkLabel => 'Edit Label';

  @override
  String get deleteRelation => 'Delete Relationship';

  @override
  String get deleteSummary => 'Delete Summary';

  @override
  String exportSummary(String label) {
    return 'Summary: $label';
  }

  @override
  String get exportRelations => 'Relationships';

  @override
  String get readerThumbnails => 'Thumbnails';

  @override
  String get readerOutline => 'Table of Contents';

  @override
  String get readerBookmarks => 'Bookmarks';

  @override
  String get readerAnnotations => 'Annotations';

  @override
  String get inkAnnotations => 'Hand-drawn annotations';

  @override
  String inkStrokeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count strokes', one: '1 stroke');
    return '$_temp0';
  }

  @override
  String get showReaderSidebar => 'Show Page Sidebar';

  @override
  String get hideReaderSidebar => 'Hide Page Sidebar';

  @override
  String get addBookmark => 'Add Bookmark';

  @override
  String get removeBookmark => 'Remove Bookmark';

  @override
  String get renameBookmark => 'Rename Bookmark…';

  @override
  String get deleteBookmark => 'Delete Bookmark';

  @override
  String get findInDocument => 'Find in Document';

  @override
  String get findNext => 'Find Next';

  @override
  String get findPrevious => 'Find Previous';

  @override
  String get noResults => 'No Results';

  @override
  String matchOf(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pageNumberField => 'Page Number';

  @override
  String get goBack => 'Back';

  @override
  String get firstPage => 'First Page';

  @override
  String get lastPage => 'Last Page';

  @override
  String get goToPage => 'Go to Page…';

  @override
  String get menuGo => 'Go';

  @override
  String get enterFullScreen => 'Enter Full Screen';

  @override
  String get exitFullScreen => 'Exit Full Screen';

  @override
  String get noBookmarks => 'No Bookmarks';

  @override
  String get noAnnotations => 'No Annotations';

  @override
  String get expandSection => 'Expand';

  @override
  String get collapseSection => 'Collapse';

  @override
  String get pdfActualSize => 'Actual Size';

  @override
  String get pdfFitWidth => 'Fit Width';

  @override
  String get pdfFitPage => 'Fit Page';

  @override
  String get statistics => 'Statistics';

  @override
  String get statsReviewed => 'Reviews';

  @override
  String get statsRetention => 'Retained';

  @override
  String get statsUpcoming => 'Next 30 Days';

  @override
  String get pdfOptions => 'PDF Options';

  @override
  String get readerStyleWhite => 'White';

  @override
  String get readerStyleDark => 'Dark';

  @override
  String get readerStylePaper => 'Paper';

  @override
  String get readerStyleGreen => 'Light Green';

  @override
  String get readerZoom => 'Page';

  @override
  String get readerAppearance => 'Reading Appearance';

  @override
  String get research => 'Research';

  @override
  String get showResearchPanel => 'Show Research Panel';

  @override
  String get hideResearchPanel => 'Hide Research Panel';

  @override
  String get researchEmptyTitle => 'Select text or a map node to research';

  @override
  String get showCardDetails => 'Show Details';

  @override
  String get hideCardDetails => 'Hide Details';

  @override
  String get closePanel => 'Close';

  @override
  String get expandCardText => 'Show Full Text';

  @override
  String get collapseCardText => 'Show Less';

  @override
  String get toggleCardText => 'Expand or Collapse Full Text';

  @override
  String get detailsExcerpt => 'Excerpt';

  @override
  String get detailsImage => 'Image';

  @override
  String get detailsNote => 'Note';

  @override
  String get detailsTopic => 'Topic';

  @override
  String get addTitle => 'Add Title';

  @override
  String revealSourcePage(int page) {
    return 'Reveal in Source · Page $page';
  }

  @override
  String get reviewStatusNew => 'Not reviewed yet';

  @override
  String reviewStatusScheduled(DateTime date, int count) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'reviewed $count times',
      one: 'reviewed once',
    );
    return 'Next $dateString · $_temp0';
  }

  @override
  String get insertImage => 'Insert Image…';

  @override
  String get imageFiles => 'PNG / JPEG Images';

  @override
  String get imageQuestion => 'Question';

  @override
  String get imageImportFailed => 'Could not import image. Choose a PNG or JPEG file.';

  @override
  String get imageInserted => 'Image inserted';

  @override
  String get dropImage => 'Drop to insert image';

  @override
  String get previewImage => 'Preview Image';

  @override
  String get ocrRecognize => 'Recognize Text…';

  @override
  String get ocrTitle => 'Recognize Text';

  @override
  String get ocrStart => 'Start Recognition';

  @override
  String get ocrNoText => 'No selectable text on this page';

  @override
  String get ocrRecognized => 'Recognized';

  @override
  String get ocrCancelled => 'Cancelled · Completed pages kept';

  @override
  String get ocrFailed => 'Recognition failed · Try again';

  @override
  String ocrProgress(int done, int total) {
    return 'Recognizing text $done/$total';
  }

  @override
  String get ocrScope => 'Pages';

  @override
  String get ocrAllPages => 'All pages';

  @override
  String get ocrCurrentPage => 'Current page';

  @override
  String get ocrPageRange => 'Page range';

  @override
  String get ocrLanguage => 'Language';

  @override
  String get ocrChineseEnglish => 'Chinese + English';

  @override
  String get ocrChinese => 'Chinese';

  @override
  String get ocrEnglish => 'English';

  @override
  String get ocrFirstPage => 'First page';

  @override
  String get ocrLastPage => 'Last page';

  @override
  String ocrInvalidRange(int count) {
    return 'Enter a range from 1 to $count';
  }

  @override
  String get ocrThisPage => 'Recognize This Page';

  @override
  String get ocrCancel => 'Cancel Text Recognition';

  @override
  String get exportTitle => 'Export Map';

  @override
  String get exportMap => 'Export Map…';

  @override
  String get exportBranch => 'Export This Branch…';

  @override
  String get exportAction => 'Export…';

  @override
  String get exportFormat => 'Format';

  @override
  String get exportRange => 'Range';

  @override
  String get exportWholeMap => 'Entire map';

  @override
  String get exportCurrentBranch => 'Current branch';

  @override
  String get exportAppearance => 'Appearance';

  @override
  String get exportLight => 'Light';

  @override
  String get exportDark => 'Dark';

  @override
  String get exportTransparent => 'Transparent';

  @override
  String get exportScale => 'Resolution';

  @override
  String get exportLarge => 'This image exceeds 8000 pixels. Some apps may not open it. Reduce the scale or use PDF.';

  @override
  String get exportReduced => 'Scale reduced automatically to fit image dimensions and memory limits.';

  @override
  String get exportLoading => 'Preparing export…';

  @override
  String get exportFailed => 'Export failed. Please try again.';

  @override
  String get exportRetry => 'Retry';

  @override
  String exportPixels(String width, String height) {
    return '$width × $height pixels';
  }

  @override
  String exportCentimeters(String width, String height) {
    return '$width × $height cm';
  }

  @override
  String get exportResearchNote => 'Research note';

  @override
  String get exportSource => 'Source';

  @override
  String get formatBold => 'Bold';

  @override
  String get formatItalic => 'Italic';

  @override
  String get formatBulletList => 'Bulleted List';

  @override
  String get formatNumberList => 'Numbered List';

  @override
  String get densityCompact => 'Compact';

  @override
  String get densityFull => 'Full';

  @override
  String get mapStyle => 'Style';

  @override
  String get mapStructureMind => 'Mind Map';

  @override
  String get mapStructureLogic => 'Logic Chart';

  @override
  String get mapStructureBrace => 'Brace Map';

  @override
  String get mapStructureTree => 'Tree Chart';

  @override
  String get mapPaletteSystem => 'System';

  @override
  String get mapPaletteRainbow => 'Colorful';

  @override
  String get mapPaletteFresh => 'Fresh';

  @override
  String get mapPaletteWarm => 'Warm';

  @override
  String get mapPaletteMorandi => 'Morandi';

  @override
  String get mapPaletteInk => 'Ink';

  @override
  String get cardWidthHandle => 'Card Width';

  @override
  String get resetCardWidth => 'Reset Width';

  @override
  String get detailsResearchNote => 'Research Note';

  @override
  String get researchSelection => 'Research Selection';

  @override
  String get researchSelectionEllipsis => 'Research Selection…';

  @override
  String get researchNode => 'Research Node';

  @override
  String researchNodeMenu(String title) {
    return 'Research “$title”';
  }

  @override
  String get researchIntentExplain => 'Explain';

  @override
  String get researchIntentInterpret => 'Interpret';

  @override
  String get researchIntentVerify => 'Verify';

  @override
  String get researchIntentVideo => 'Videos / Diagrams';

  @override
  String get researchIntentPaper => 'Find Papers';

  @override
  String get researchIntentDeep => 'Deep Research';

  @override
  String get researchIntentTranslate => 'Translate';

  @override
  String get researchRecommended => 'Suggested';

  @override
  String get researchQuestion => 'Question';

  @override
  String get researchQuestionPlaceholder => 'What do you want to find out?';

  @override
  String researchQuestionExplain(String term) {
    return 'What does “$term” mean? Give an example from the context.';
  }

  @override
  String get researchQuestionInterpret => 'What are this passage\'s claim, reasoning and assumptions?';

  @override
  String get researchQuestionVerify => 'Is this claim supported? Are there counterexamples or limits?';

  @override
  String researchQuestionVerifyQuote(String quote) {
    return '“$quote” — is this reliable? Are there counterexamples or limits?';
  }

  @override
  String researchQuestionVideo(String term) {
    return 'Find a clear video or diagram explaining “$term”';
  }

  @override
  String researchQuestionPaper(String term) {
    return 'What are the key studies on “$term”? Their findings and limits?';
  }

  @override
  String get researchQuestionTranslate => 'Translate this passage and explain its terms.';

  @override
  String get researchKeywords => 'Keywords';

  @override
  String get researchAddKeyword => 'Add keyword';

  @override
  String get researchSourcesLabel => 'Sources';

  @override
  String get researchKindWeb => 'Web';

  @override
  String get researchKindPaper => 'Papers';

  @override
  String get researchKindVideo => 'Videos';

  @override
  String get researchKindImage => 'Images';

  @override
  String get researchMethod => 'Method';

  @override
  String get researchMethodSearch => 'Search Only';

  @override
  String get researchMethodOffline => 'Ask AI';

  @override
  String get researchMethodWeb => 'Web Research';

  @override
  String get researchMethodSearchNote => 'No AI, no AI cost';

  @override
  String get researchMethodOfflineNote => 'Sends only the selection and its context; no web search';

  @override
  String researchMethodWebNote(int searches, int pages) {
    return 'Up to $searches searches and $pages pages';
  }

  @override
  String get researchSetUpAi => 'Set Up AI…';

  @override
  String get researchNoAi => 'No AI service set up';

  @override
  String get researchNoAiTitle => 'No AI service set up';

  @override
  String get researchNoWeb => 'This service can\'t search the web';

  @override
  String researchContextSummary(String parts, int count) {
    return 'Sent to AI: $parts (about $count characters)';
  }

  @override
  String get researchContextSelection => 'Selection';

  @override
  String get researchContextBefore => 'Previous passage';

  @override
  String get researchContextAfter => 'Next passage';

  @override
  String get researchContextChapter => 'Chapter';

  @override
  String get researchContextNode => 'Node';

  @override
  String get researchContextPath => 'Path';

  @override
  String get researchContextChildren => 'Cards below';

  @override
  String get researchRunningChoice => 'A research is running';

  @override
  String get researchAsNew => 'New Research';

  @override
  String get researchJoin => 'Add to Current Question';

  @override
  String get researchLater => 'Research Later';

  @override
  String get researchStart => 'Start Research';

  @override
  String get researchNeedQuestion => 'Write a question first';

  @override
  String get researchSavedForLater => 'Saved to Research Later';

  @override
  String get researchJoined => 'Added to the current research';

  @override
  String get researchSettings => 'Research Settings';

  @override
  String get researchBackToOrigin => 'Back to Where It Started';

  @override
  String get researchOriginGone => 'The original place was deleted';

  @override
  String get researchStageSearch => 'Searching';

  @override
  String get researchStageAnswer => 'Answering';

  @override
  String get researchStageWebAnswer => 'Searching and answering';

  @override
  String researchStageRead(int done, int total) {
    return 'Reading sources $done/$total';
  }

  @override
  String get researchRetry => 'Retry';

  @override
  String get researchRestart => 'Start Again';

  @override
  String get researchCancelled => 'Cancelled';

  @override
  String get researchInterrupted => 'Interrupted when the app quit';

  @override
  String get researchFailed => 'Failed';

  @override
  String get researchRunning => 'Running';

  @override
  String researchDoneAt(String time) {
    return 'Finished $time';
  }

  @override
  String researchUsedSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources used',
      one: '1 source used',
    );
    return '$_temp0';
  }

  @override
  String get researchErrorTimeout => 'Timed out';

  @override
  String get researchErrorUnavailable => 'Can\'t reach the service';

  @override
  String get researchErrorAuthentication => 'The API key was rejected';

  @override
  String get researchErrorBudget => 'Reached the limit';

  @override
  String get researchErrorRefusal => 'The AI declined to answer';

  @override
  String get researchErrorUnsupported => 'Not supported by this service';

  @override
  String get researchErrorInvalid => 'The request was not accepted';

  @override
  String get researchErrorProtocol => 'The answer was incomplete';

  @override
  String get researchTabAnswer => 'Answer';

  @override
  String get researchTabSources => 'Sources';

  @override
  String get researchTabSaved => 'Taken';

  @override
  String researchBadgeWeb(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources used',
      one: '1 source used',
    );
    return 'Web research · $_temp0';
  }

  @override
  String get researchBadgeOffline => 'Offline · no external sources, so no citations';

  @override
  String researchBadgeSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count sources', one: 'source');
    return 'Only the $_temp0 you chose; no web search';
  }

  @override
  String get researchViewSources => 'View Sources';

  @override
  String get researchNoSourceBasis => 'no source';

  @override
  String get researchEdited => 'edited';

  @override
  String researchQuoteFrom(int number) {
    return 'Source [$number] · original text';
  }

  @override
  String get researchEditPoint => 'Edit';

  @override
  String get researchAskPoint => 'Ask';

  @override
  String get researchSavePoint => 'Save';

  @override
  String researchAskAbout(String point) {
    return 'About “$point”: ';
  }

  @override
  String researchFailedSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count sources', one: '1 source');
    return '$_temp0 couldn\'t be read';
  }

  @override
  String researchChecked(int count) {
    return '$count selected';
  }

  @override
  String get researchClearChecked => 'Deselect';

  @override
  String get researchSaveNote => 'Save as Research Note…';

  @override
  String get researchNoAnswerSearch => 'Search only: no answer';

  @override
  String get researchNoAnswer => 'No answer yet';

  @override
  String researchAnswerFromChosen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Chosen Sources',
      one: '1 Chosen Source',
    );
    return 'Answer from $_temp0';
  }

  @override
  String get researchAnswering => 'Answering…';

  @override
  String get researchFollowUpPlaceholder => 'Ask a follow-up…';

  @override
  String get researchCanUseWeb => 'Web';

  @override
  String get researchOffline => 'Offline';

  @override
  String get researchSend => 'Send';

  @override
  String get researchFilterAll => 'All';

  @override
  String get researchReadUnread => 'Not read';

  @override
  String get researchReadSnippet => 'Search snippet';

  @override
  String get researchReadAbstract => 'Abstract only';

  @override
  String get researchReadFullText => 'Full text';

  @override
  String get researchReadTranscript => 'Transcript';

  @override
  String get researchReadFailed => 'Couldn\'t read';

  @override
  String get researchReadNoTranscript => 'No transcript';

  @override
  String get researchOpenAccess => 'Open access';

  @override
  String get researchSubscription => 'Subscription';

  @override
  String get researchUsedInAnswer => 'Used in answer';

  @override
  String researchMerged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reprints merged',
      one: '1 reprint merged',
    );
    return '$_temp0, not counted separately';
  }

  @override
  String get researchRead => 'Read';

  @override
  String get researchWhyFailed => 'Why';

  @override
  String get researchChoose => 'Add to Sources';

  @override
  String get researchChosen => 'Added';

  @override
  String get researchPasted => 'Pasted by you';

  @override
  String researchExternalSearch(String site, String query) {
    return 'Search “$query” on $site';
  }

  @override
  String get researchExternal => 'External';

  @override
  String researchSearching(String keywords) {
    return 'Searching: $keywords';
  }

  @override
  String get researchNoSources => 'No sources';

  @override
  String get researchOfflineNoSources => 'This research did not search the web';

  @override
  String get researchOpenPage => 'Open Page';

  @override
  String researchFetchedAt(String date) {
    return 'Fetched $date';
  }

  @override
  String get researchAiSummary => 'AI summary · not the source';

  @override
  String get researchSummarize => 'AI Summary';

  @override
  String get researchClipEvidence => 'Take as Evidence';

  @override
  String get researchWriteNote => 'Write Note…';

  @override
  String researchClipped(int count) {
    return 'Taken ($count)';
  }

  @override
  String get researchCantRead => 'Couldn\'t read the text';

  @override
  String get researchReadLogin => 'The page needs a sign-in';

  @override
  String get researchReadTimeout => 'The page took too long.';

  @override
  String get researchReadUnparseable => 'No article text was found.';

  @override
  String get researchReadUnsafe => 'This address is not allowed.';

  @override
  String get researchReadUnsupported => 'This is not a web page.';

  @override
  String get researchReadEncoding => 'The page\'s text encoding is not supported.';

  @override
  String get researchReadUnavailable => 'Couldn\'t reach the page.';

  @override
  String get researchPasteText => 'Paste Text…';

  @override
  String get researchSaveLinkOnly => 'Save Link Only';

  @override
  String get researchReadAgain => 'Read Again';

  @override
  String get researchAbstractOnly => 'Only the abstract was read';

  @override
  String get researchOpenPublisher => 'Publisher Page';

  @override
  String get researchPasteTitle => 'Paste Text';

  @override
  String get researchClipsTitle => 'Evidence (draft)';

  @override
  String get researchSavedNotes => 'Saved research notes';

  @override
  String get researchNoteFromClips => 'Write Note from Evidence…';

  @override
  String get researchNothingSaved => 'Nothing taken yet';

  @override
  String researchInSource(int page) {
    return 'Source · p. $page';
  }

  @override
  String researchInMap(String title) {
    return 'Map · $title';
  }

  @override
  String researchCitations(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count citations', one: '1 citation');
    return '$_temp0';
  }

  @override
  String get researchContinue => 'Continue';

  @override
  String get researchSaveTitle => 'Save Research Note';

  @override
  String get researchNoteTitle => 'Title';

  @override
  String get researchNoteBody => 'Text';

  @override
  String get researchNoteDefaultTitle => 'Research note';

  @override
  String researchCitationsLabel(int count) {
    return 'Citations ($count)';
  }

  @override
  String get researchNoExternalBasis => 'No external source';

  @override
  String get researchSaveTo => 'Save to';

  @override
  String get researchDestBoth => 'Source and Map';

  @override
  String get researchDestSource => 'Source Only';

  @override
  String get researchDestMap => 'Map Only';

  @override
  String get researchDestNoSource => 'Started from a node: no place in the source';

  @override
  String get researchAttachUnder => 'In the map under';

  @override
  String researchSplitPoints(int count) {
    return 'Split the $count points into child cards';
  }

  @override
  String get researchSaving => 'Saving';

  @override
  String get researchSavedBoth => 'Saved to the source and the map';

  @override
  String get researchSavedSource => 'Saved to the source';

  @override
  String get researchSavedMap => 'Saved to the map';

  @override
  String get researchShowInMap => 'Show in Map';

  @override
  String researchCardKind(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Research note · $count sources',
      one: 'Research note · 1 source',
      zero: 'Research note',
    );
    return '$_temp0';
  }

  @override
  String get researchCardOpen => 'Full note and citations';

  @override
  String researchNoteLabel(String title) {
    return 'Research note: $title';
  }

  @override
  String get researchLocateInMap => 'Locate in Map';

  @override
  String get researchOpenResearch => 'Open Research';

  @override
  String get researchPlaces => 'Shown in';

  @override
  String researchPlaceSource(String document, int page) {
    return '$document · p. $page';
  }

  @override
  String get researchLocate => 'Locate';

  @override
  String get researchDetach => 'Detach';

  @override
  String get researchNotInSource => 'Not attached to the source';

  @override
  String get researchNoteGone => 'This note was deleted';

  @override
  String get researchDeleteNote => 'Delete Research Note…';

  @override
  String get researchDeleteTitle => 'Delete this research note?';

  @override
  String researchDeleteMessage(int marks, int cards) {
    String _temp0 = intl.Intl.pluralLogic(
      marks,
      locale: localeName,
      other: 'Its $marks source marks go too. ',
      one: 'Its source mark goes too. ',
      zero: '',
    );
    String _temp1 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: 'Its $cards map cards go too.',
      one: 'Its map card goes too.',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String get researchService => 'AI service';

  @override
  String get researchServiceNone => 'None';

  @override
  String get researchServiceCompatible => 'Compatible';

  @override
  String get researchServiceIncomplete => 'Add the model to finish setting up this service';

  @override
  String get researchApiKey => 'API key';

  @override
  String get researchKeySaved => 'Saved in the Keychain';

  @override
  String get researchKeyFailed => 'Couldn\'t save to the Keychain';

  @override
  String get researchModel => 'Model';

  @override
  String get researchEndpoint => 'Address';

  @override
  String get researchPaperSearch => 'Paper search';

  @override
  String get researchLimits => 'Web research limits';

  @override
  String researchLimitSearches(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count searches', one: '1 search');
    return '$_temp0';
  }

  @override
  String researchLimitPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count pages', one: '1 page');
    return '$_temp0';
  }

  @override
  String researchLimitMinutes(int count) {
    return '$count min';
  }

  @override
  String get researchPrivacy => 'Privacy';

  @override
  String get researchShowContext => 'Show what will be sent before starting';

  @override
  String get researchBlockPrivate => 'Block local and private addresses';

  @override
  String get researchCache => 'Web cache';

  @override
  String get researchClearCache => 'Clear Cache';

  @override
  String get researchCacheCleared => 'Web cache cleared';

  @override
  String get researchInterruptedShort => 'Interrupted';

  @override
  String get researchAddReview => 'Add to review';

  @override
  String get researchSaveVideo => 'Save video link…';

  @override
  String get researchVideoUrl => 'Video URL';

  @override
  String get researchInvalidVideo => 'Enter a YouTube or Bilibili video URL.';

  @override
  String get researchViewMore => 'View more';

  @override
  String get researchHistory => 'Research history';

  @override
  String get researchDelete => 'Delete research';

  @override
  String get researchErrorUnsafeUrl => 'Address blocked by network validation';

  @override
  String get researchErrorTls => 'Could not establish a secure connection';

  @override
  String get researchFixAuthentication => 'Check your API key, model permissions and account balance, then retry.';

  @override
  String get researchFixRequest =>
      'Check the endpoint, model name and supported API protocol. Compatible services accept a base URL (such as https://example.com/v1) or a full chat/completions URL.';

  @override
  String get researchFixUnsafeUrl =>
      'Check the endpoint and proxy DNS settings. Web fetching blocks private addresses; proxy fake-IP addresses are supported only for explicitly configured HTTPS AI endpoints.';

  @override
  String get researchFixTls =>
      'Check the system clock, server certificate and proxy settings. Certificate failures are not retried automatically.';

  @override
  String get researchFixRateLimit =>
      'The provider limited requests or account usage. Bounded retries were attempted; wait before retrying or check your balance and quota.';

  @override
  String get researchFixConnection =>
      'Check your network, proxy and provider status, or increase the research time limit. Temporary connection failures get bounded retries; once the deadline expires or output starts, retry manually.';

  @override
  String get researchFixProtocol =>
      'The response was incomplete or used a different API format. Check streaming support. Existing output is preserved; retry manually.';

  @override
  String get researchFixBudget =>
      'A research input or output limit was reached. Narrow the question, select fewer sources or adjust research settings.';

  @override
  String researchDiagnosticCode(String code) {
    return 'Error code: $code';
  }

  @override
  String get assistant => 'Assistant';

  @override
  String get askAssistant => 'Ask Assistant';

  @override
  String get askAssistantEllipsis => 'Ask Assistant…';

  @override
  String get showAssistant => 'Show Assistant';

  @override
  String get hideAssistant => 'Hide Assistant';

  @override
  String get assistantNewConversation => 'New Conversation';

  @override
  String get assistantHistory => 'Conversations';

  @override
  String get assistantConversations => 'Conversations';

  @override
  String get assistantNoConversations => 'No conversations yet';

  @override
  String get assistantPlaceholder => 'Ask…';

  @override
  String get assistantConnectFirst => 'Configure a model first';

  @override
  String get assistantMention => 'Reference';

  @override
  String get assistantCommands => 'Commands';

  @override
  String get assistantOnline => 'Online';

  @override
  String get assistantOffline => 'Offline';

  @override
  String get assistantSend => 'Send';

  @override
  String get assistantStop => 'Stop';

  @override
  String get assistantPermissionTitle => 'Your permission is needed';

  @override
  String get assistantPermissionWaiting => 'Waiting for permission';

  @override
  String get assistantPermissionExplain =>
      'The assistant wants to read this content for context to answer your question.';

  @override
  String get assistantPermissionScope => 'Applies to this answer only. Content is read after you allow it.';

  @override
  String get assistantPermissionAllow => 'Allow for this answer';

  @override
  String get assistantPermissionDeny => 'Deny';

  @override
  String get assistantPermissionAllowed => 'Allowed for this answer';

  @override
  String get assistantPermissionDenied => 'Denied';

  @override
  String get assistantPermissionCancelled => 'Request cancelled';

  @override
  String assistantPermissionPages(String document, int from, int to) {
    return '$document · pages $from–$to';
  }

  @override
  String assistantPermissionSelection(String title) {
    return 'Selected text · $title';
  }

  @override
  String assistantPermissionBranch(String title) {
    return 'Map branch · $title';
  }

  @override
  String get assistantToolReadSelection => 'Reading the selection';

  @override
  String get assistantToolReadPages => 'Reading pages';

  @override
  String get assistantToolSearch => 'Searching the study set';

  @override
  String get assistantToolReadBranch => 'Reading the branch';

  @override
  String get assistantToolWebSearch => 'Searching the web';

  @override
  String get assistantToolPapers => 'Finding papers';

  @override
  String get assistantToolFetch => 'Reading a page';

  @override
  String get assistantToolPropose => 'Preparing changes';

  @override
  String get assistantToolSkills => 'Choosing an approach';

  @override
  String get assistantToolOther => 'Working';

  @override
  String get assistantNotOnline => 'Not checked online';

  @override
  String get assistantInsertChild => 'Insert as Child Node';

  @override
  String get assistantSaveNote => 'Take Note';

  @override
  String get assistantAnswerToMap => 'Turn into Mind Map';

  @override
  String assistantAnswerToMapPrompt(String answer) {
    return 'Turn the following answer into a mind map, preserving its main points and hierarchy. Propose map edits for review:\n\n$answer';
  }

  @override
  String get assistantSavedNote => 'Saved as Note';

  @override
  String get assistantLocate => 'Show';

  @override
  String get assistantRegenerate => 'Regenerate';

  @override
  String get assistantErrorNetwork => 'Network unavailable';

  @override
  String get assistantErrorKey => 'Invalid API key';

  @override
  String get assistantErrorService => 'Service temporarily unavailable';

  @override
  String get assistantErrorBudget => 'Over this answer\'s limit';

  @override
  String get assistantErrorRefused => 'The model declined to answer';

  @override
  String get assistantErrorToolProtocol => 'The model could not call tools correctly';

  @override
  String get assistantErrorFailed => 'Request failed';

  @override
  String get assistantStopped => 'Stopped';

  @override
  String get assistantInterrupted => 'Not finished when the app quit';

  @override
  String get assistantRetry => 'Retry';

  @override
  String get assistantUseLocal => 'Use Local Model';

  @override
  String get assistantOpenSettings => 'Open Settings';

  @override
  String get assistantContinue => 'Continue';

  @override
  String get assistantProposalTitle => 'Map changes';

  @override
  String get assistantProposalApplied => 'Applied';

  @override
  String get assistantProposalDismissed => 'Dismissed';

  @override
  String get assistantDismiss => 'Dismiss';

  @override
  String assistantApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Apply $count Changes',
      one: 'Apply 1 Change',
    );
    return '$_temp0';
  }

  @override
  String get assistantShowInMap => 'Show in Map';

  @override
  String get assistantReopen => 'Review Again';

  @override
  String get assistantTargetDeleted => 'Target deleted';

  @override
  String assistantAppliedHud(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Applied $count changes',
      one: 'Applied 1 change',
    );
    return '$_temp0';
  }

  @override
  String assistantPutInMap(String title) {
    return 'Put in map under “$title”';
  }

  @override
  String assistantAttachToSource(int page) {
    return 'Attach beside this sentence on page $page';
  }

  @override
  String get assistantNoteDefault => 'Note';

  @override
  String get assistantNoteTitle => 'Note title';

  @override
  String get assistantBack => 'Back';

  @override
  String get assistantKindWeb => 'Web';

  @override
  String get assistantKindPaper => 'Paper';

  @override
  String get assistantKindVideo => 'Video';

  @override
  String get assistantOpenInBrowser => 'Open in Browser';

  @override
  String assistantMapContext(String title) {
    return 'Map · $title';
  }

  @override
  String assistantBranchContext(String title) {
    return 'Branch · $title';
  }

  @override
  String assistantPageContext(String document, int page) {
    return 'p. $page · $document';
  }

  @override
  String assistantDocumentContext(String document) {
    return 'Whole · $document';
  }

  @override
  String get assistantWholeMap => 'Whole map';

  @override
  String get assistantAutoContext => 'Attached automatically';

  @override
  String get assistantRemoveContext => 'Remove';

  @override
  String assistantContextCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count references',
      one: '1 reference',
      zero: 'No references',
    );
    return '$_temp0';
  }

  @override
  String get assistantManageContexts => 'Manage references';

  @override
  String get assistantSelectionContext => 'Selected text';

  @override
  String get assistantMoreActions => 'More';

  @override
  String assistantCurrentPage(int page) {
    return 'Page $page';
  }

  @override
  String get assistantSkillExplain => 'Explain';

  @override
  String get assistantSkillTranslate => 'Translate';

  @override
  String get assistantSkillVerify => 'Verify';

  @override
  String get assistantSkillSummarize => 'Summarize';

  @override
  String get assistantSkillQuiz => 'Make Review Questions';

  @override
  String get assistantSkillQuizShort => 'Quiz';

  @override
  String get assistantSkillOrganize => 'Organize into Map';

  @override
  String get assistantSkillOrganizeShort => 'Organize';

  @override
  String get assistantSkillPapers => 'Find Papers';

  @override
  String get assistantSkillVideos => 'Find Videos';

  @override
  String get assistantPromptExplain => 'Explain this';

  @override
  String get assistantPromptTranslate => 'Translate this';

  @override
  String get assistantPromptVerify => 'Check whether this is right';

  @override
  String get assistantPromptSummarize => 'Summarize the key points';

  @override
  String get assistantPromptQuiz => 'Make a few review questions about this';

  @override
  String get assistantPromptOrganize => 'Organize this into the map';

  @override
  String get assistantPromptPapers => 'Find related papers';

  @override
  String get assistantPromptVideos => 'Find related videos';

  @override
  String assistantSuggestSummarize(int page) {
    return 'Summarize page $page';
  }

  @override
  String assistantSuggestExplain(String title) {
    return 'Explain “$title”';
  }

  @override
  String assistantSuggestVerify(int page) {
    return 'Check a claim on page $page';
  }

  @override
  String get assistantSuggestTranslate => 'Translate the selection';

  @override
  String assistantSuggestQuiz(String title) {
    return 'Make review questions for “$title”';
  }

  @override
  String get assistantSuggestOrganize => 'Organize this section into the map';

  @override
  String get assistantSavedKeyUnavailable => 'Could not read the API key. Enter it again and save.';

  @override
  String get assistantKeySaveUnavailable =>
      'The API key could not be saved. Its text remains in this form so you can retry. This does not mean the key is invalid.';

  @override
  String get assistantPasteKey => 'Paste API key';

  @override
  String get assistantCannotConnect => 'Cannot reach the service';

  @override
  String assistantQuestions(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count questions', one: '1 question');
    return '$_temp0';
  }

  @override
  String get assistantHasNote => 'has notes';

  @override
  String get assistantRunning => 'Answering';

  @override
  String get assistantUnfinished => 'Unfinished';

  @override
  String get assistantFailed => 'Failed';

  @override
  String get assistantDeleteEllipsis => 'Delete…';

  @override
  String get assistantDeleteTitle => 'Delete this conversation?';

  @override
  String get assistantDeleteMessage => 'Saved notes are kept.';

  @override
  String get assistantRenameConversation => 'Rename Conversation';

  @override
  String get assistantExplainTopic => 'Explain This Topic';

  @override
  String get assistantExplainCard => 'Explain This Card';

  @override
  String get assistantOrganizeBranch => 'Organize This Branch…';

  @override
  String get assistantQuizBranch => 'Make Review Questions for This Branch…';

  @override
  String get assistantVerifyCard => 'Verify This Card';

  @override
  String get assistantAskWith => 'Ask About It…';

  @override
  String get assistantAnchorGone => 'The original place was deleted';

  @override
  String get assistantOpenConversation => 'Open Conversation';

  @override
  String get assistantAskMore => 'Ask More';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsReading => 'Reading';

  @override
  String get settingsModels => 'Models';

  @override
  String get settingsWebSearch => 'Web Search';

  @override
  String get settingsDefaultModel => 'Default Model';

  @override
  String get settingsServices => 'Services';

  @override
  String settingsServiceModels(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count models on', one: '1 model on');
    return '$_temp0';
  }

  @override
  String get settingsServiceNoModels => 'No models yet';

  @override
  String get settingsServiceOff => 'Off';

  @override
  String get settingsName => 'Name';

  @override
  String get settingsAddress => 'Address';

  @override
  String get settingsShowKey => 'Show';

  @override
  String get settingsHideKey => 'Hide';

  @override
  String get settingsSetDefault => 'Make Default';

  @override
  String get settingsIsDefault => 'Default';

  @override
  String get settingsRemoveModel => 'Remove';

  @override
  String get settingsAddModel => 'Add Models…';

  @override
  String get settingsCustomAddress => 'Use Custom Address';

  @override
  String get settingsRemoveService => 'Remove Service';

  @override
  String settingsRemoveServiceTitle(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get settingsRemoveServiceMessage => 'Its API key is deleted too. Conversations stay.';

  @override
  String get settingsAddService => 'Add Service';

  @override
  String get settingsAddModelTitle => 'Add Models';

  @override
  String get settingsSearchModels => 'Search, or enter a model ID';

  @override
  String get settingsAdded => 'Added';

  @override
  String settingsAddManual(String id) {
    return 'Add “$id”';
  }

  @override
  String get settingsAdd => 'Add';

  @override
  String settingsAddCount(int count) {
    return 'Add $count';
  }

  @override
  String get settingsOpenAiCompatible => 'OpenAI Compatible';

  @override
  String get settingsOllamaLocal => 'Ollama (Local)';

  @override
  String get settingsSearchService => 'Search Service';

  @override
  String get settingsSearchUnconfigured => 'Not Configured';

  @override
  String get settingsAccountId => 'Account ID';

  @override
  String get settingsTokenInvalid => 'Invalid API token';

  @override
  String get settingsSearchUnreachable => 'Cannot reach the search service';

  @override
  String get assistantManageModels => 'Manage Models…';

  @override
  String get assistantModel => 'Model';

  @override
  String get assistantThinking => 'Thinking…';

  @override
  String assistantWorkedFor(int seconds) {
    return 'Worked for $seconds s';
  }

  @override
  String assistantToolFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tool calls failed',
      one: '1 tool call failed',
    );
    return '$_temp0';
  }

  @override
  String get assistantAnswerWithoutTools => 'Answer Without Tools';

  @override
  String get assistantSwitchModel => 'Switch Model and Retry';

  @override
  String get assistantCopyDiagnostics => 'Copy Diagnostics';

  @override
  String get assistantDetails => 'Details';

  @override
  String get assistantDiagnosticModel => 'Model';

  @override
  String get assistantDiagnosticHost => 'Host';

  @override
  String get assistantDiagnosticStatus => 'HTTP status';

  @override
  String get assistantDiagnosticTools => 'Failed tools';

  @override
  String get assistantDiagnosticReason => 'Stopped because';

  @override
  String get assistantDiagnosticRequest => 'Request ID';

  @override
  String get settingsVoice => 'Voice Input';

  @override
  String get voiceService => 'Speech provider';

  @override
  String get voiceDisabled => 'Disabled';

  @override
  String get voiceDoubao => 'Doubao Realtime ASR 2.0';

  @override
  String get voiceAliyun => 'Alibaba Cloud Realtime ASR';

  @override
  String get voiceAuthentication => 'Authentication';

  @override
  String get voiceResource => 'Resource type';

  @override
  String get voiceDuration => '2.0 Duration';

  @override
  String get voiceConcurrent => '2.0 Concurrent';

  @override
  String get voicePrivacy => 'Audio is sent to your selected provider. Credentials are stored in this Mac’s Keychain.';

  @override
  String get voiceTest => 'Test Connection';

  @override
  String get voiceSave => 'Save';

  @override
  String get voiceTestPassed => 'Connection successful';

  @override
  String get voiceSaved => 'Saved';

  @override
  String get voiceSaveError => 'Could not save. Check Keychain access.';

  @override
  String get voiceKeyError => 'Could not read credentials. Check Keychain access.';

  @override
  String get voiceConfigurationError => 'Complete your speech service settings and credentials.';

  @override
  String get voiceConnectionError => 'Could not connect. Check your network, credentials and service activation.';

  @override
  String get voicePermissionError => 'Microphone access denied. Allow access in System Settings.';

  @override
  String get voiceRecordingError => 'Recording interrupted. Check your microphone and try again.';

  @override
  String get voiceTimeoutError => 'The speech service timed out. Try again.';

  @override
  String get voiceEmptyError => 'No speech recognized. Try again.';

  @override
  String get voiceConnecting => 'Connecting to speech service…';

  @override
  String get voiceListening => 'Listening. Click to finish.';

  @override
  String get voiceFinishing => 'Finalizing transcription…';

  @override
  String get voiceCancel => 'Cancel voice input';

  @override
  String get voiceFinish => 'Finish Recording';

  @override
  String get voiceKeyPlaceholder => 'Paste credential';

  @override
  String get mapMultiSelect => 'Multiple Selection';

  @override
  String get voiceAppIdPlaceholder => 'Enter App ID';

  @override
  String get settingsNamePlaceholder => 'Enter service name';

  @override
  String get settingsAccountIdPlaceholder => 'Enter Account ID';

  @override
  String get settingsApiTokenPlaceholder => 'Paste API Token';

  @override
  String get settingsSaveFailed => 'Could not save. Please retry.';

  @override
  String get settingsSaving => 'Saving…';

  @override
  String get settingsUnsaved => 'Unsaved changes';

  @override
  String get settingsSaveBeforeModels => 'Save the service settings before fetching models';

  @override
  String get settingsRequiredFields => 'Complete the required fields before saving';

  @override
  String get assistantModelSetupTitle => 'Set up the AI assistant';

  @override
  String get assistantModelUnavailableTitle => 'Model temporarily unavailable';

  @override
  String get assistantConfigureModels => 'Configure Models';

  @override
  String get microphonePermission => 'Record audio for transcription.';

  @override
  String get localNetworkPermission => 'Connect to your local model service.';

  @override
  String get assistantOpenModelSettings => 'Open Model Settings →';

  @override
  String get assistantSetupHint => 'Add a model to get started';

  @override
  String get assistantKeyNeedsAttention => 'Re-enter your API key';

  @override
  String get assistantQuickTitle => 'AI Assistant';

  @override
  String get assistantQuickExplain => 'Explain Passage';

  @override
  String get assistantQuickSummarize => 'Summarize Key Points';

  @override
  String get assistantQuickOutline => 'Create an Outline';

  @override
  String get assistantQuickOutlinePrompt =>
      'Create a clear text outline of the selected passage, organizing its main ideas and hierarchy. Show the outline in your answer without modifying the mind map.';

  @override
  String get assistantQuickAsk => 'Or ask a question…';

  @override
  String get assistantQuickFollowUp => 'Ask more about this passage…';

  @override
  String get assistantQuickSidebar => 'Continue in Sidebar';

  @override
  String get assistantQuickBusy => 'Another conversation is answering. You can ask when it finishes.';

  @override
  String get assistantQuickChanged => 'This conversation has changed. Continue viewing it in the sidebar.';

  @override
  String get assistantQuickGenerated => 'AI-generated content';

  @override
  String get assistantQuickSelection => 'Selected Text';

  @override
  String get cropMargins => 'Crop Margins';

  @override
  String get uncropMargins => 'Uncrop Margins';

  @override
  String get cropAdjust => 'Adjust Crop';

  @override
  String get cropScopeAll => 'All Pages';

  @override
  String get cropScopeOddEven => 'Odd & Even';

  @override
  String get cropScopePage => 'This Page';

  @override
  String get cropAuto => 'Auto';

  @override
  String get cropNone => 'None';

  @override
  String get cropOddPages => 'Odd Pages';

  @override
  String get cropEvenPages => 'Even Pages';

  @override
  String get cropCustomPage => 'Custom';

  @override
  String cropHiddenAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotations will be hidden',
      one: '1 annotation will be hidden',
    );
    return '$_temp0';
  }

  @override
  String get croppedHud => 'Margins cropped';

  @override
  String get uncroppedHud => 'Crop removed';

  @override
  String get marginNotes => 'Margin Notes';

  @override
  String get marginNoteAction => 'Comment';

  @override
  String get writeMarginNote => '+ Comment';

  @override
  String get showMarginNotes => 'Show Margin Notes';

  @override
  String get hideMarginNotes => 'Hide Margin Notes';

  @override
  String get expandMargin => 'Show Margin';

  @override
  String get cropExpandMargin => 'Crop Margins and Show Notes';

  @override
  String get marginNoteDeleted => 'Comment Deleted';

  @override
  String get marginNoteAddedToMap => 'Added to Mind Map';

  @override
  String get compareReading => 'Side by Side';

  @override
  String get compareRecommended => 'Suggested';

  @override
  String compareAiTranslate(String language) {
    return 'AI Translate into $language';
  }

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageCodeZh => 'ZH';

  @override
  String get languageCodeEn => 'EN';

  @override
  String get compareAiOffline => 'Offline';

  @override
  String get compareAiNeedsOcr => 'Recognize text first';

  @override
  String get compareAiPending => 'Coming soon';

  @override
  String get compareTooNarrow => 'Window too narrow';

  @override
  String get compareExit => 'Exit Side by Side';

  @override
  String get compareSync => 'Sync Scrolling';

  @override
  String get compareAlign => 'Align Here';

  @override
  String get compareAlignedHud => 'Aligned';

  @override
  String get compareSwap => 'Swap Sides';

  @override
  String compareMapHiddenHud(String shortcut) {
    return 'Map hidden · $shortcut';
  }

  @override
  String compareTranslationProgress(int done, int total) {
    return 'Translating $done/$total';
  }

  @override
  String get compareTranslationSaved => 'Saved';

  @override
  String get compareTranslationFailed => 'Translation failed';

  @override
  String get compareTranslationPageEmpty => 'No text to translate on this page';

  @override
  String compareTranslationPageSaved(int page) {
    return 'Page $page saved';
  }

  @override
  String compareTranslationPageProgress(int page, int done, int total) {
    return 'Page $page · Translating $done/$total';
  }

  @override
  String get chooseHighlightColor => 'Choose Highlight Color';

  @override
  String get moreHighlightColors => 'More Colors';

  @override
  String get selectionTranslate => 'Translate';

  @override
  String get selectionTranslationDirection => 'Selection Translation Direction';

  @override
  String get selectionTranslationAutomatic => 'Automatic (Chinese ↔ English)';

  @override
  String get selectionTranslationEnglishToChinese => 'English → Chinese';

  @override
  String get selectionTranslationChineseToEnglish => 'Chinese → English';

  @override
  String get selectionTranslationLoading => 'Translating…';

  @override
  String get selectionTranslationFailed => 'Translation failed. Check your model settings or connection and retry.';

  @override
  String get selectionTranslationOffline =>
      'You are offline. Enable online access or select a local model, then retry.';

  @override
  String get selectionTranslationTooLong => 'Select a shorter passage to translate.';

  @override
  String get selectionTranslationCopy => 'Copy Translation';

  @override
  String get highlightCustomColor => 'Custom Color';

  @override
  String get highlightColorHue => 'Hue';

  @override
  String get highlightColorSaturationValue => 'Saturation and Brightness';

  @override
  String get highlightColorHex => 'Hex Color';

  @override
  String get highlightColorHexInvalid => 'Enter a six-digit hex color, such as #12A4B8';

  @override
  String get translationSourceLanguage => 'Source Language';

  @override
  String get translationTargetLanguage => 'Target Language';

  @override
  String get translationDetectLanguage => 'Detect Language';

  @override
  String get translationSwapLanguages => 'Swap Source and Translation';

  @override
  String get translationSameLanguage => 'Choose different source and target languages.';

  @override
  String get translationTraditionalChinese => 'Traditional Chinese';

  @override
  String get translationJapanese => 'Japanese';

  @override
  String get translationKorean => 'Korean';

  @override
  String get translationFrench => 'French';

  @override
  String get translationGerman => 'German';

  @override
  String get translationSpanish => 'Spanish';

  @override
  String get translationPortuguese => 'Portuguese';

  @override
  String get translationItalian => 'Italian';

  @override
  String get translationRussian => 'Russian';

  @override
  String get translationArabic => 'Arabic';

  @override
  String get translationChooseSourceToSwap => 'Select the source language to swap direction';

  @override
  String get translationChinese => 'Chinese';

  @override
  String get translationEnglish => 'English';

  @override
  String get editBookmark => 'Edit Bookmark…';

  @override
  String get addOutlineEntry => 'Add Outline Entry…';

  @override
  String get addOutlineChild => 'Add Subentry…';

  @override
  String get editOutlineEntry => 'Edit Outline Entry…';

  @override
  String get deleteOutlineEntry => 'Delete Outline Entry';

  @override
  String get deleteOutlineBranch => 'Delete Entry and Subentries';

  @override
  String get noOutlineEntries => 'No outline entries. Use + to add one.';

  @override
  String get outlineNoDestination => 'Use page 0 for a section without a destination.';

  @override
  String get readerEntryActions => 'Entry Actions';

  @override
  String get readerDragToMove => 'Drag to reorder';

  @override
  String get readerSortPageAscending => 'Page Number: Ascending';

  @override
  String get readerSortPageDescending => 'Page Number: Descending';

  @override
  String get readerSortTitle => 'By Name';

  @override
  String get bookmarkPageOccupied => 'This page already has a bookmark.';

  @override
  String readerInvalidPage(int count) {
    return 'Enter a valid page number up to $count.';
  }

  @override
  String get outlineDragHint => 'Drag above or below an entry to reorder; drag to its center to nest.';

  @override
  String get toolUnderline => 'Underline';

  @override
  String get lineSolid => 'Solid';

  @override
  String get lineDashed => 'Dashed';

  @override
  String get lineDotted => 'Dotted';

  @override
  String get lineWavy => 'Wavy';

  @override
  String get underlinedHud => 'Underlined';

  @override
  String get deleteUnderline => 'Delete Underline';

  @override
  String get underlineDeletedHud => 'Underline Deleted';

  @override
  String mergeNodes(int count) {
    return 'Merge $count nodes';
  }

  @override
  String splitNodes(int count) {
    return 'Split into $count nodes';
  }

  @override
  String selectedNodes(int count) {
    return '$count selected';
  }

  @override
  String get mergedNodes => 'Nodes merged';

  @override
  String mergeCleanup(int relations, int summaries) {
    return 'Removed $relations relationships and $summaries summaries';
  }

  @override
  String mergedSources(int count) {
    return '$count sources · Merged';
  }

  @override
  String get relationNeedsTwo => 'Select exactly two nodes';

  @override
  String get mapEditTooFewCards => 'Select at least two nodes';

  @override
  String get mapEditMissingCard => 'A selected node is unavailable';

  @override
  String get mapEditCenterTopic => 'The central topic cannot be used';

  @override
  String get mapEditImageCard => 'Image cards cannot be merged';

  @override
  String get mapEditSummaryTopic => 'Summary topics cannot be used';

  @override
  String get mapEditUnsupportedCard => 'This card type cannot be merged';

  @override
  String get mapEditNotMerged => 'This card has no segments to split';

  @override
  String get mapEditDifferentParents => 'Select nodes with the same parent';

  @override
  String get mapEditOverlappingSummary => 'This range overlaps an existing summary';

  @override
  String get mapEditMissingSummary => 'This summary is unavailable';

  @override
  String get nodeBarChild => 'Child';

  @override
  String get nodeBarSibling => 'Sibling';

  @override
  String get nodeBarNote => 'Note';

  @override
  String get nodeBarImage => 'Image';

  @override
  String get nodeBarAssistant => 'AI';

  @override
  String get selectionMerge => 'Merge';

  @override
  String get selectionSummary => 'Summary';

  @override
  String get selectionRelation => 'Relate';

  @override
  String get selectionDelete => 'Delete';

  @override
  String get relationArrowEnd => 'One-way arrow';

  @override
  String get relationArrowBoth => 'Two-way arrows';

  @override
  String get relationArrowNone => 'No arrows';

  @override
  String get relationReverse => 'Reverse direction';

  @override
  String get relationLineStyle => 'Solid / dashed';

  @override
  String summaryIncludedNodes(int count) {
    return 'Includes $count unselected nodes in between';
  }

  @override
  String get addWebPage => 'Add Web Page…';

  @override
  String get webUrlPlaceholder => 'URL';

  @override
  String get webUrlEmpty => 'Enter a URL';

  @override
  String get webUrlInvalid => 'Not a valid URL';

  @override
  String get webUrlScheme => 'Only http and https are supported';

  @override
  String get browserBack => 'Back';

  @override
  String get browserForward => 'Forward';

  @override
  String get browserReload => 'Reload';

  @override
  String get browserStop => 'Stop';

  @override
  String get browserClose => 'Close Page';

  @override
  String get browserConvert => 'Convert to Document…';

  @override
  String get browserConvertShort => 'Convert';

  @override
  String get webReadyPrompt => 'Convert to a document?';

  @override
  String get webStillLoading => 'Some content is still loading';

  @override
  String get webLater => 'Later';

  @override
  String get webErrorTitle => 'Can’t Open Page';

  @override
  String get webRetry => 'Try Again';

  @override
  String get settingsClearWebsiteData => 'Clear…';

  @override
  String get clearWebsiteDataConfirm => 'Clear all website data?';

  @override
  String get websiteDataCleared => 'Website data cleared';

  @override
  String get addWebTitle => 'Add Web Page';

  @override
  String get webKeepWaiting => 'Keep Waiting';

  @override
  String get webConvertAction => 'Convert';

  @override
  String get webErrorTimeout => 'The connection timed out';

  @override
  String get webErrorHost => 'Server not found';

  @override
  String get webErrorCertificate => 'Invalid certificate';

  @override
  String get webErrorOffline => 'You’re offline';

  @override
  String get settingsBrowserGroup => 'In-App Browser';

  @override
  String get settingsWebsiteData => 'Website Data';

  @override
  String get clearAction => 'Clear';

  @override
  String get browserUnsaved => 'Not Saved';

  @override
  String get addDocumentMenu => 'Add';

  @override
  String get documentFiles => 'Documents';

  @override
  String unsupportedFile(String name) {
    return '“$name” isn’t supported';
  }

  @override
  String get readingSettings => 'Reading Settings';

  @override
  String get cancelImport => 'Cancel Import';

  @override
  String get okAction => 'OK';

  @override
  String importFailedTitle(String name) {
    return 'Couldn’t Import “$name”';
  }

  @override
  String importFailedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents couldn’t be imported',
      one: '1 document couldn’t be imported',
    );
    return '$_temp0';
  }

  @override
  String get importErrorDrm => 'Protected by DRM';

  @override
  String get importErrorDamaged => 'The file is damaged';

  @override
  String get importErrorKfx => 'KFX isn’t supported';

  @override
  String get importErrorEmpty => 'No readable content';

  @override
  String get importErrorUnsupported => 'Unsupported format';

  @override
  String get readerFontSmaller => 'Smaller Text';

  @override
  String get readerFontLarger => 'Larger Text';

  @override
  String get readerLineTight => 'Tight';

  @override
  String get readerLineNormal => 'Normal';

  @override
  String get readerLineLoose => 'Loose';

  @override
  String get readerFontOriginal => 'Original';

  @override
  String get readerFontSerif => 'Serif';

  @override
  String get readerFontSans => 'Sans';

  @override
  String get readerModePaged => 'Pages';

  @override
  String get readerModeScroll => 'Scroll';

  @override
  String get readerPositionMissing => 'Source position not found';

  @override
  String get readerLoadFailed => 'Unable to open document';

  @override
  String get readerNeedsReview => 'Needs Review';

  @override
  String get readerRetry => 'Retry';

  @override
  String get readerNoOutline => 'No outline';

  @override
  String get readerSelectionStart => 'Selection start';

  @override
  String get readerSelectionEnd => 'Selection end';

  @override
  String get convertTitle => 'Convert to Document';

  @override
  String get convertTitlePlaceholder => 'Title';

  @override
  String get convertReadable => 'Reader';

  @override
  String get convertPdf => 'PDF';

  @override
  String get convertMarkdown => 'Markdown';

  @override
  String get docSaving => 'Saving';

  @override
  String docSaved(String title) {
    return 'Saved “$title”';
  }

  @override
  String get docSaveFailed => 'Couldn’t Save';

  @override
  String get docUpdated => 'Updated';

  @override
  String annotationsNeedReview(int count) {
    return 'Needs Review ($count)';
  }

  @override
  String annotationsNeedReviewHud(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count highlights need review',
      one: '1 highlight needs review',
    );
    return '$_temp0';
  }

  @override
  String get viewAction => 'View';

  @override
  String get openOriginalPage => 'Open Original Page';

  @override
  String get refetchPage => 'Refetch Page';

  @override
  String get browserUpdate => 'Update Document';

  @override
  String get webUpdatePrompt => 'Update the document?';

  @override
  String get webUpdateAction => 'Update';

  @override
  String webSource(String domain, DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$domain · $dateString';
  }

  @override
  String get annotationNotFound => 'Can’t find the original text';

  @override
  String get vocabularyTitle => 'Vocabulary';

  @override
  String get vocabularyLookup => 'Look up (T)';

  @override
  String get vocabularyTranslate => 'Translate (T)';

  @override
  String get vocabularyAdd => 'Add to vocabulary';

  @override
  String get vocabularyAdded => 'Added to vocabulary';

  @override
  String get vocabularyLearning => 'Learning';

  @override
  String get vocabularyKnown => 'Known';

  @override
  String get vocabularyView => 'View in vocabulary';

  @override
  String get vocabularyMarkKnown => 'Mark as known';

  @override
  String get vocabularyRemove => 'Remove from vocabulary';

  @override
  String get vocabularyExample => 'Save as example';

  @override
  String get vocabularySentence => 'Translate sentence';

  @override
  String get vocabularyDetails => 'Details ›';

  @override
  String get vocabularyLongSelection => 'Vocabulary accepts words and phrases of up to 8 words';

  @override
  String get vocabularySettings => 'Open settings';

  @override
  String get vocabularySpeak => 'Read aloud';

  @override
  String get vocabularySetup => 'No model configured';

  @override
  String get vocabularyOffline => 'Online access is off';

  @override
  String get vocabularyUK => 'UK';

  @override
  String get vocabularyUS => 'US';

  @override
  String get vocabularySearch => 'Search words and meanings';

  @override
  String get vocabularyThisSet => 'This study set';

  @override
  String get vocabularyAll => 'All';

  @override
  String get vocabularyToday => 'Today';

  @override
  String get vocabularyEarlier => 'Earlier';

  @override
  String get vocabularyNoMatch => 'No matching words';

  @override
  String get vocabularyEmpty => 'No words yet';

  @override
  String get vocabularyOccurrences => 'Occurrences in this document';

  @override
  String get vocabularySenses => 'Meanings';

  @override
  String get vocabularyRegenerate => 'Regenerate';

  @override
  String get vocabularyModelRequired => 'No model configured';

  @override
  String get vocabularyGloss => 'Inline meaning';

  @override
  String get vocabularyNote => 'Notes';

  @override
  String get vocabularyForms => 'Word forms';

  @override
  String get vocabularyForgetForm => 'Stop recognizing';

  @override
  String get vocabularyExamples => 'Examples';

  @override
  String get vocabularyNoExamples => 'No examples.';

  @override
  String get vocabularyReturn => 'Back to source';

  @override
  String get vocabularyOpenSet => 'Open study set ›';

  @override
  String get vocabularyDeleteExample => 'Delete example';

  @override
  String get vocabularyLearnAgain => 'Learn again';

  @override
  String get vocabularyDelete => 'Delete from vocabulary';

  @override
  String get vocabularyRemoved => 'Removed';

  @override
  String get vocabularyExampleDeleted => 'Example deleted';

  @override
  String get vocabularyRead => 'Read aloud';

  @override
  String get vocabularyUk => 'UK';

  @override
  String get vocabularyUs => 'US';

  @override
  String get vocabularyAddForm => 'Add';

  @override
  String get vocabularyHints => 'Vocabulary hints';

  @override
  String get vocabularyHintsOff => 'Off';

  @override
  String get vocabularyHintsUnderline => 'Underline';

  @override
  String get vocabularyHintsGloss => 'Meaning';

  @override
  String get vocabularyHintsHidden => 'Hide in this document';

  @override
  String get vocabularyHintsKnown => 'Mark known words';

  @override
  String get mapIdeaMenu => 'Expand Ideas with AI';

  @override
  String get mapIdeaExpand => 'Expand Ideas';

  @override
  String mapIdeaExpandEach(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Expand $count Topics',
      one: 'Expand 1 Topic',
    );
    return '$_temp0';
  }

  @override
  String get mapIdeaExpandMap => 'Expand Whole Map…';

  @override
  String get mapIdeaWholeMap => 'Expand Whole Map';

  @override
  String get mapIdeaBranchesOnly => 'New Branches Only';

  @override
  String get mapIdeaGroup => 'Group Under New Parent';

  @override
  String get mapIdeaFillSiblings => 'Fill In Siblings';

  @override
  String get mapIdeaDirection => 'Direction';

  @override
  String get mapIdeaDirectionAuto => 'Auto';

  @override
  String get mapIdeaDirectionWhy => 'Why';

  @override
  String get mapIdeaDirectionExample => 'Examples';

  @override
  String get mapIdeaDirectionCounter => 'Counterpoints';

  @override
  String get mapIdeaDirectionQuestion => 'Questions';

  @override
  String get mapIdeaDirectionAction => 'Actions';

  @override
  String get mapIdeaDepth => 'Depth';

  @override
  String mapIdeaDepthLevels(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count Levels', one: '1 Level');
    return '$_temp0';
  }

  @override
  String get mapIdeaAmount => 'Amount';

  @override
  String get mapIdeaAmountFew => 'Few';

  @override
  String get mapIdeaAmountSome => 'Some';

  @override
  String get mapIdeaAmountMany => 'Many';

  @override
  String get mapIdeaHint => 'Instructions';

  @override
  String get mapIdeaGrounded => 'Use Source';

  @override
  String mapIdeaExpanding(String title) {
    return 'Expanding “$title”';
  }

  @override
  String mapIdeaExpandingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Expanding $count Topics',
      one: 'Expanding 1 Topic',
    );
    return '$_temp0';
  }

  @override
  String get mapIdeaIncompleteDepth => 'Some branches are missing levels. Try again.';

  @override
  String get mapIdeaStopped => 'Stopped';

  @override
  String mapIdeaDraftCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count ideas', one: '1 idea');
    return '$_temp0';
  }

  @override
  String mapIdeaKeptCount(int kept, int total) {
    return '$kept of $total kept';
  }

  @override
  String get mapIdeaRegenerate => 'Try Others';

  @override
  String get mapIdeaAdjust => 'Adjust';

  @override
  String get mapIdeaRegenerateAdjusted => 'Regenerate';

  @override
  String get mapIdeaDiscard => 'Discard';

  @override
  String mapIdeaKeep(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'Keep $count', one: 'Keep 1');
    return '$_temp0';
  }

  @override
  String get mapIdeaDraftKeep => 'Keep';

  @override
  String get mapIdeaDraftSkip => 'Skip';

  @override
  String get mapIdeaDraftEdit => 'Edit';

  @override
  String get mapIdeaDraftMore => 'Expand Further';

  @override
  String mapIdeaDraftSemantics(String title, String state) {
    return 'AI draft, $title, $state';
  }

  @override
  String get mapIdeaDraftKept => 'kept';

  @override
  String get mapIdeaDraftSkipped => 'not kept';

  @override
  String get mapIdeaNewBranches => 'New Branches';

  @override
  String mapIdeaAddCount(int count) {
    return '+$count';
  }

  @override
  String get mapIdeaFewer => 'Fewer';

  @override
  String get mapIdeaMore => 'More';

  @override
  String get mapIdeaStart => 'Expand';

  @override
  String mapIdeaAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count topics',
      one: 'Added 1 topic',
    );
    return '$_temp0';
  }

  @override
  String get mapIdeaBlocked => 'Keep (↩) or discard (Esc) the AI drafts first';

  @override
  String get mapIdeaNothing => 'No new ideas here. Try another direction.';

  @override
  String get mapIdeaStoppedEmpty => 'Stopped before any ideas';

  @override
  String get mapIdeaBusy => 'The model is busy. Try again later.';

  @override
  String get notesTitle => 'Notes';

  @override
  String get organizeStudyNote => 'Organize Study Notes…';

  @override
  String get organizeNotes => 'Organize Notes';

  @override
  String get organizeSelection => 'Create Study Note';

  @override
  String get exportStudyNote => 'Export Note…';

  @override
  String get noteSetupTitle => 'Organize Study Notes';

  @override
  String get noteScope => 'Scope';

  @override
  String get noteMaterials => 'Materials';

  @override
  String get noteOrganization => 'Organization';

  @override
  String get noteDepth => 'AI Contribution';

  @override
  String get noteContext => 'Context';

  @override
  String get noteTemplate => 'Layout';

  @override
  String get noteSelected => 'Selected highlights';

  @override
  String get noteWhole => 'Entire study set';

  @override
  String get noteRecent => 'Last 7 days';

  @override
  String get noteHighlights => 'Highlights';

  @override
  String get noteOwn => 'My Notes';

  @override
  String get noteMapNotes => 'Map Notes';

  @override
  String get noteSavedAi => 'Saved AI Notes';

  @override
  String get noteImages => 'Image Cards';

  @override
  String get noteTheme => 'By Theme';

  @override
  String get noteSourceOrder => 'Source Order';

  @override
  String get noteMapOrder => 'Map Structure';

  @override
  String get noteLocal => 'Format Only';

  @override
  String get noteAiContext => 'Context & Summary';

  @override
  String get noteAiDeep => 'Deep Organization';

  @override
  String get noteNextPhase => 'Available in the next release';

  @override
  String get noteComplete => 'Complete Fragments';

  @override
  String get noteReading => 'Reading Notes';

  @override
  String get noteCornell => 'Cornell Notes';

  @override
  String get noteReview => 'Review Outline';

  @override
  String get noteGenerate => 'Create Note';

  @override
  String get noteEmptyScope => 'No highlights in this scope';

  @override
  String get noteGenerated => 'Note created';

  @override
  String get noteFailed => 'Could not create note';

  @override
  String get noteUnused => 'Unused';

  @override
  String get notePutBack => 'Put Back';

  @override
  String get noteRestored => 'Added to note';

  @override
  String get noteRemoved => 'Removed from note';

  @override
  String get noteExpandContext => 'Expand Context';

  @override
  String get noteCollapseContext => 'Collapse Context';

  @override
  String get noteNoText => 'No source text';

  @override
  String get noteMissingHighlight => 'Highlight deleted';

  @override
  String get noteMissingDocument => 'Source removed';

  @override
  String get noteNotIncluded => 'This highlight is not in the note';

  @override
  String get noteRemoveBlock => 'Remove from Note';

  @override
  String get noteSources => 'Sources';

  @override
  String get noteInclude => 'Include';

  @override
  String get noteCitationPage => 'Page Numbers';

  @override
  String get noteCitationFootnote => 'Footnotes';

  @override
  String get noteCitationNone => 'None';

  @override
  String get noteAiContent => 'AI Content';

  @override
  String get noteQuestions => 'Review Questions';

  @override
  String get noteSourceList => 'Source List';

  @override
  String get noteAiMarks => 'AI Labels';

  @override
  String get noteMark => 'Show';

  @override
  String get noteUnmark => 'Hide';

  @override
  String get noteCornellSummary => 'Summary';

  @override
  String noteContextSentences(int count) {
    return '$count surrounding sentences';
  }

  @override
  String noteCoverage(int count) {
    return 'All $count highlights cited · Original text preserved';
  }

  @override
  String noteUnusedCount(int count) {
    return '$count unused highlights';
  }

  @override
  String noteSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String noteRecallQuestion(String title, String location) {
    return 'What does $title $location say?';
  }

  @override
  String get noteSelectAll => 'Select All';

  @override
  String get noteDeselectAll => 'Deselect All';

  @override
  String get noteReviewAdded => 'Created 1 review card';

  @override
  String get noteExplain => 'Explain This Passage';

  @override
  String get noteCreateReview => 'Create Review Card';

  @override
  String get noteAddedToMap => 'Added to map';

  @override
  String get noteExport => 'Export';

  @override
  String get noteMarginSource => 'Margin Note';

  @override
  String notePage(int page) {
    return 'p.$page';
  }

  @override
  String noteSourceTitle(String title) {
    return '$title';
  }

  @override
  String get notePageSeparator => ', ';

  @override
  String noteSourcePage(String title, int page) {
    return '$title, p. $page';
  }

  @override
  String get noteOutlineTitle => 'Confirm outline';

  @override
  String get noteGenerating => 'Organizing note';

  @override
  String get noteStop => 'Stop';

  @override
  String get noteContinue => 'Continue organizing';

  @override
  String get noteLayoutOnly => 'Use original order';

  @override
  String get noteStepOutline => 'Grouping themes';

  @override
  String get noteAddSection => 'Add section';

  @override
  String get noteNewSection => 'New section';

  @override
  String get noteUnassigned => 'Unassigned';

  @override
  String get noteAiUnavailable => 'AI not configured';

  @override
  String get notePreviewOutline => 'Preview outline';

  @override
  String get noteAiFallback => 'AI organization failed; used original order';

  @override
  String get noteShowAi => 'Show AI markers';

  @override
  String get noteAiEdited => 'AI · Edited';

  @override
  String get noteRephrase => 'Rephrase';

  @override
  String get noteConcise => 'Make concise';

  @override
  String get noteExpand => 'Expand';

  @override
  String get noteMakeMine => 'Make it mine';

  @override
  String get noteRegenerate => 'Reorganize';

  @override
  String get noteAddAllReview => 'Add all to review';

  @override
  String noteStepWrite(int done, int total) {
    return 'Writing $done / $total · Checking references';
  }

  @override
  String noteSending(int highlights, int notes, int characters, String model) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: 'Send $highlights highlights and $notes notes (about $characters characters) to $model',
      zero: 'Send $highlights highlights (about $characters characters) to $model',
    );
    return '$_temp0';
  }

  @override
  String get noteStepCollect => 'Collect materials';

  @override
  String get noteStepContext => 'Gather context';

  @override
  String get noteStepCompose => 'Write';

  @override
  String get noteStepVerify => 'Check references';

  @override
  String get noteStopped => 'Stopped';

  @override
  String get noteLocked => 'Keep when updating';

  @override
  String get resizeCompanionPanel => 'Resize companion panel';

  @override
  String noteNewMaterials(int highlights, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: ', $notes new notes',
      one: ', 1 new note',
      zero: '',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: ', $notes new notes',
      one: ', 1 new note',
      zero: '',
    );
    String _temp2 = intl.Intl.pluralLogic(notes, locale: localeName, other: '$notes new notes', one: '1 new note');
    String _temp3 = intl.Intl.pluralLogic(
      highlights,
      locale: localeName,
      other: '$highlights new highlights$_temp0',
      one: '1 new highlight$_temp1',
      zero: '$_temp2',
    );
    return '$_temp3';
  }

  @override
  String get notePreviewUpdate => 'Preview Update';

  @override
  String get noteApplyUpdate => 'Apply Update';

  @override
  String get noteIgnoreUpdate => 'Ignore';

  @override
  String noteUpdateReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count additions', one: '1 addition');
    return '$_temp0';
  }

  @override
  String get noteUpdateStale => 'The note or its sources changed. Preview again.';

  @override
  String noteUpdateApplied(int count) {
    return 'Updated · $count added';
  }

  @override
  String get noteLocalPlacement => 'In source order';

  @override
  String get noteAddToReview => 'Add to Review';

  @override
  String noteUpdateChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count changes', one: '1 change');
    return '$_temp0';
  }
}
