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
  String get readerZoom => 'Page Fit';

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
  String get researchMethodSearchNote => 'No AI, no AI cost.';

  @override
  String get researchMethodOfflineNote => 'Sends only the context below; no web search.';

  @override
  String researchMethodWebNote(int searches, int pages) {
    return 'Up to $searches searches and $pages pages.';
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
  String get researchErrorRateLimited => 'Too many requests; try again later';

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
    return '$_temp0 could not be read and are not evidence.';
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
  String get researchReadLogin => 'The page needs a sign-in. Sign-ins and paywalls are not bypassed.';

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
  String get researchAbstractOnly => 'Only the abstract was read; answers don\'t treat it as read in full.';

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
}
