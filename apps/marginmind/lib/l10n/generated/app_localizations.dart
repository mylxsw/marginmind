import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Foliarc'**
  String get appName;

  /// No description provided for @libraryTitleAll.
  ///
  /// In en, this message translates to:
  /// **'All Study Sets'**
  String get libraryTitleAll;

  /// No description provided for @libraryRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get libraryRecent;

  /// No description provided for @libraryStarred.
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get libraryStarred;

  /// No description provided for @libraryDue.
  ///
  /// In en, this message translates to:
  /// **'Due for Review'**
  String get libraryDue;

  /// No description provided for @librarySection.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get librarySection;

  /// No description provided for @libraryFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get libraryFolders;

  /// No description provided for @libraryUnfiled.
  ///
  /// In en, this message translates to:
  /// **'Unfiled'**
  String get libraryUnfiled;

  /// No description provided for @libraryRecentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get libraryRecentlyDeleted;

  /// No description provided for @librarySetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No study sets} =1{1 study set} other{{count} study sets}}'**
  String librarySetCount(int count);

  /// No description provided for @libraryDueCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 card due} other{{count} cards due}}'**
  String libraryDueCount(int count);

  /// No description provided for @libraryContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue Learning'**
  String get libraryContinue;

  /// No description provided for @libraryAllHeading.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryAllHeading;

  /// No description provided for @libraryLastPosition.
  ///
  /// In en, this message translates to:
  /// **'Last read: {document} · p. {page}'**
  String libraryLastPosition(String document, int page);

  /// No description provided for @libraryNoDocumentsYet.
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get libraryNoDocumentsYet;

  /// No description provided for @libraryCardMeta.
  ///
  /// In en, this message translates to:
  /// **'{documents, plural, =1{1 doc} other{{documents} docs}} · {cards, plural, =1{1 card} other{{cards} cards}}'**
  String libraryCardMeta(int documents, int cards);

  /// No description provided for @dueBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} due'**
  String dueBadge(int count);

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeJustNow;

  /// No description provided for @relativeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String relativeMinutes(int count);

  /// No description provided for @relativeHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String relativeHours(int count);

  /// No description provided for @relativeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get relativeYesterday;

  /// No description provided for @relativeDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String relativeDays(int count);

  /// No description provided for @relativeWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Last week} other{{count} weeks ago}}'**
  String relativeWeeks(int count);

  /// No description provided for @relativeMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Last month} other{{count} months ago}}'**
  String relativeMonths(int count);

  /// No description provided for @viewAsIcons.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get viewAsIcons;

  /// No description provided for @viewAsList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get viewAsList;

  /// No description provided for @sortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sortRecent;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortTitle;

  /// No description provided for @sortCards.
  ///
  /// In en, this message translates to:
  /// **'Card count'**
  String get sortCards;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'By {field}'**
  String sortBy(String field);

  /// No description provided for @sortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort order'**
  String get sortTooltip;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Search study sets'**
  String get searchLibrary;

  /// No description provided for @newStudySet.
  ///
  /// In en, this message translates to:
  /// **'New Study Set'**
  String get newStudySet;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @openSample.
  ///
  /// In en, this message translates to:
  /// **'Open Sample Study Set'**
  String get openSample;

  /// No description provided for @noResultTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching study sets'**
  String get noResultTitle;

  /// No description provided for @noResultSearch.
  ///
  /// In en, this message translates to:
  /// **'No study set name contains “{query}”.'**
  String noResultSearch(String query);

  /// No description provided for @noResultFilter.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. Drag study sets onto a folder in the sidebar.'**
  String get noResultFilter;

  /// No description provided for @columnName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get columnName;

  /// No description provided for @columnFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get columnFolder;

  /// No description provided for @columnDocuments.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get columnDocuments;

  /// No description provided for @columnCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get columnCards;

  /// No description provided for @columnDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get columnDue;

  /// No description provided for @columnLastOpened.
  ///
  /// In en, this message translates to:
  /// **'Last Opened'**
  String get columnLastOpened;

  /// No description provided for @star.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get star;

  /// No description provided for @unstar.
  ///
  /// In en, this message translates to:
  /// **'Remove Star'**
  String get unstar;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @sheetName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sheetName;

  /// No description provided for @sheetNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cognitive Psychology'**
  String get sheetNamePlaceholder;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorYellow;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get colorBlack;

  /// No description provided for @showLibrary.
  ///
  /// In en, this message translates to:
  /// **'Show Library'**
  String get showLibrary;

  /// No description provided for @hideSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide Sidebar'**
  String get hideSidebar;

  /// No description provided for @showSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show Sidebar'**
  String get showSidebar;

  /// No description provided for @searchInSet.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchInSet;

  /// No description provided for @sectionMaps.
  ///
  /// In en, this message translates to:
  /// **'Mind Maps'**
  String get sectionMaps;

  /// No description provided for @sectionDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get sectionDocuments;

  /// No description provided for @sectionLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get sectionLearn;

  /// No description provided for @mainMap.
  ///
  /// In en, this message translates to:
  /// **'Main Map'**
  String get mainMap;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @importDocument.
  ///
  /// In en, this message translates to:
  /// **'Import Document…'**
  String get importDocument;

  /// No description provided for @noSidebarMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noSidebarMatches;

  /// No description provided for @toggleAnnotationTool.
  ///
  /// In en, this message translates to:
  /// **'Toggle Highlighter'**
  String get toggleAnnotationTool;

  /// No description provided for @toggleAreaTool.
  ///
  /// In en, this message translates to:
  /// **'Toggle Area Select'**
  String get toggleAreaTool;

  /// No description provided for @toggleInkTool.
  ///
  /// In en, this message translates to:
  /// **'Toggle Pen'**
  String get toggleInkTool;

  /// No description provided for @toolSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get toolSelect;

  /// No description provided for @toolHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get toolHighlight;

  /// No description provided for @toolArea.
  ///
  /// In en, this message translates to:
  /// **'Area Select'**
  String get toolArea;

  /// No description provided for @toolPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get toolPen;

  /// No description provided for @toolText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolText;

  /// No description provided for @inkFreehand.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get inkFreehand;

  /// No description provided for @inkEllipse.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get inkEllipse;

  /// No description provided for @inkArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get inkArrow;

  /// No description provided for @inkEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get inkEraser;

  /// No description provided for @inkThin.
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get inkThin;

  /// No description provided for @inkMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get inkMedium;

  /// No description provided for @inkBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get inkBold;

  /// No description provided for @syncToMapOn.
  ///
  /// In en, this message translates to:
  /// **'Sync excerpts to map: On'**
  String get syncToMapOn;

  /// No description provided for @syncToMapOff.
  ///
  /// In en, this message translates to:
  /// **'Sync excerpts to map: Off'**
  String get syncToMapOff;

  /// No description provided for @annotationColor.
  ///
  /// In en, this message translates to:
  /// **'Highlight Color'**
  String get annotationColor;

  /// No description provided for @layoutReader.
  ///
  /// In en, this message translates to:
  /// **'Source Only'**
  String get layoutReader;

  /// No description provided for @layoutSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get layoutSplit;

  /// No description provided for @layoutMap.
  ///
  /// In en, this message translates to:
  /// **'Map Only'**
  String get layoutMap;

  /// No description provided for @paneSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get paneSource;

  /// No description provided for @paneMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get paneMap;

  /// No description provided for @moreTools.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTools;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @pageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String pageNumber(int page);

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'{page} / {total}'**
  String pageOf(int page, int total);

  /// No description provided for @readerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Open a document to start reading'**
  String get readerEmptyTitle;

  /// No description provided for @readerEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Pick a document in the sidebar, or import one.'**
  String get readerEmptyMessage;

  /// No description provided for @readerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'PDF rendering arrives with the mm_pdf package. This page marks where it will appear.'**
  String get readerPlaceholder;

  /// No description provided for @mapEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your excerpts will appear here'**
  String get mapEmptyTitle;

  /// No description provided for @mapView.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapView;

  /// No description provided for @outlineView.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineView;

  /// No description provided for @newExcerptTarget.
  ///
  /// In en, this message translates to:
  /// **'New excerpts → {topic}'**
  String newExcerptTarget(String topic);

  /// No description provided for @addTopic.
  ///
  /// In en, this message translates to:
  /// **'Add Topic'**
  String get addTopic;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get addNote;

  /// No description provided for @removeFromMap.
  ///
  /// In en, this message translates to:
  /// **'Remove from Map'**
  String get removeFromMap;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get zoomOut;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get nextPage;

  /// No description provided for @switchDocument.
  ///
  /// In en, this message translates to:
  /// **'Switch Document'**
  String get switchDocument;

  /// No description provided for @closeCurrentDocument.
  ///
  /// In en, this message translates to:
  /// **'Close Current Document'**
  String get closeCurrentDocument;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get closeTab;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get settings;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @componentGallery.
  ///
  /// In en, this message translates to:
  /// **'Component Gallery'**
  String get componentGallery;

  /// No description provided for @galleryTitle.
  ///
  /// In en, this message translates to:
  /// **'Component Gallery'**
  String get galleryTitle;

  /// No description provided for @gallerySubtitle.
  ///
  /// In en, this message translates to:
  /// **'mm_design · tokens and components'**
  String get gallerySubtitle;

  /// No description provided for @galleryColors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get galleryColors;

  /// No description provided for @galleryTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get galleryTypography;

  /// No description provided for @galleryControls.
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get galleryControls;

  /// No description provided for @galleryFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get galleryFeedback;

  /// No description provided for @galleryShowHud.
  ///
  /// In en, this message translates to:
  /// **'Show HUD'**
  String get galleryShowHud;

  /// No description provided for @galleryShowSheet.
  ///
  /// In en, this message translates to:
  /// **'Show Sheet'**
  String get galleryShowSheet;

  /// No description provided for @galleryHudMessage.
  ///
  /// In en, this message translates to:
  /// **'Excerpted to “Patterns of forgetting”'**
  String get galleryHudMessage;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @importPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF…'**
  String get importPdf;

  /// No description provided for @importedHud.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 document} other{Imported {count} documents}}'**
  String importedHud(int count);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open “{name}” as a PDF'**
  String importFailed(String name);

  /// No description provided for @pdfFiles.
  ///
  /// In en, this message translates to:
  /// **'PDF documents'**
  String get pdfFiles;

  /// No description provided for @excerptAction.
  ///
  /// In en, this message translates to:
  /// **'Excerpt to Map'**
  String get excerptAction;

  /// No description provided for @highlightAction.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlightAction;

  /// No description provided for @copyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

  /// No description provided for @addToMapAction.
  ///
  /// In en, this message translates to:
  /// **'Add to Map'**
  String get addToMapAction;

  /// No description provided for @deleteHighlight.
  ///
  /// In en, this message translates to:
  /// **'Delete Highlight'**
  String get deleteHighlight;

  /// No description provided for @excerptedHud.
  ///
  /// In en, this message translates to:
  /// **'Excerpted to “{target}”'**
  String excerptedHud(String target);

  /// No description provided for @excerptView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get excerptView;

  /// No description provided for @highlightedHud.
  ///
  /// In en, this message translates to:
  /// **'Highlighted'**
  String get highlightedHud;

  /// No description provided for @copiedHud.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedHud;

  /// No description provided for @removedHud.
  ///
  /// In en, this message translates to:
  /// **'Removed from the map; the highlight stays in the source'**
  String get removedHud;

  /// No description provided for @highlightDeletedHud.
  ///
  /// In en, this message translates to:
  /// **'Highlight deleted'**
  String get highlightDeletedHud;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get rename;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameTitle;

  /// No description provided for @mapNodeNoteCount.
  ///
  /// In en, this message translates to:
  /// **'Notes · {count}'**
  String mapNodeNoteCount(int count);

  /// No description provided for @deleteMapNote.
  ///
  /// In en, this message translates to:
  /// **'Delete Note'**
  String get deleteMapNote;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNote;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @newTopicName.
  ///
  /// In en, this message translates to:
  /// **'New Topic'**
  String get newTopicName;

  /// No description provided for @newNoteText.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNoteText;

  /// No description provided for @untitledExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Untitled excerpt'**
  String get untitledExcerpt;

  /// No description provided for @imageExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Image excerpt'**
  String get imageExcerpt;

  /// No description provided for @revealSource.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Source'**
  String get revealSource;

  /// No description provided for @menuMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get menuMap;

  /// No description provided for @documentPages.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String documentPages(int count);

  /// No description provided for @sampleSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample: Forgetting & Spaced Repetition'**
  String get sampleSetTitle;

  /// No description provided for @sampleTopic1.
  ///
  /// In en, this message translates to:
  /// **'How we forget'**
  String get sampleTopic1;

  /// No description provided for @sampleTopic2.
  ///
  /// In en, this message translates to:
  /// **'Spaced repetition'**
  String get sampleTopic2;

  /// No description provided for @sampleTopic3.
  ///
  /// In en, this message translates to:
  /// **'Active recall'**
  String get sampleTopic3;

  /// No description provided for @readerHintHighlight.
  ///
  /// In en, this message translates to:
  /// **'Drag across text to excerpt it'**
  String get readerHintHighlight;

  /// No description provided for @readerHintSelect.
  ///
  /// In en, this message translates to:
  /// **'Select text, then choose an action'**
  String get readerHintSelect;

  /// No description provided for @outlineEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the outline yet'**
  String get outlineEmpty;

  /// No description provided for @sampleDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample chapter: The forgetting curve'**
  String get sampleDocTitle;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @addChildTopic.
  ///
  /// In en, this message translates to:
  /// **'Add Child Topic'**
  String get addChildTopic;

  /// No description provided for @backToStudySet.
  ///
  /// In en, this message translates to:
  /// **'Back to Study Set'**
  String get backToStudySet;

  /// No description provided for @collapseNode.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapseNode;

  /// No description provided for @expandNode.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expandNode;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get deleteEllipsis;

  /// No description provided for @deleteStudySetTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{title}”?'**
  String deleteStudySetTitle(String title);

  /// No description provided for @deleteStudySetMessage.
  ///
  /// In en, this message translates to:
  /// **'Its documents, highlights, cards and review history will be deleted. This can’t be undone.'**
  String get deleteStudySetMessage;

  /// No description provided for @deletedHud.
  ///
  /// In en, this message translates to:
  /// **'Deleted “{title}”'**
  String deletedHud(String title);

  /// No description provided for @documentRemovedHud.
  ///
  /// In en, this message translates to:
  /// **'Document removed'**
  String get documentRemovedHud;

  /// No description provided for @dropToCreateSet.
  ///
  /// In en, this message translates to:
  /// **'Drop to create a study set'**
  String get dropToCreateSet;

  /// No description provided for @dropToImport.
  ///
  /// In en, this message translates to:
  /// **'Drop to import into this study set'**
  String get dropToImport;

  /// No description provided for @dropOnlyPdf.
  ///
  /// In en, this message translates to:
  /// **'Only PDF files can be imported'**
  String get dropOnlyPdf;

  /// No description provided for @exportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export Map as Markdown…'**
  String get exportMarkdown;

  /// No description provided for @exportOpml.
  ///
  /// In en, this message translates to:
  /// **'Export Map as OPML…'**
  String get exportOpml;

  /// No description provided for @exportedHud.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exportedHud;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get moveDown;

  /// No description provided for @rateAgain.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get rateAgain;

  /// No description provided for @rateHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get rateHard;

  /// No description provided for @rateGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get rateGood;

  /// No description provided for @rateEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get rateEasy;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @undoneHud.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get undoneHud;

  /// No description provided for @redoneHud.
  ///
  /// In en, this message translates to:
  /// **'Redone'**
  String get redoneHud;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removeDocumentEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Remove from Study Set…'**
  String get removeDocumentEllipsis;

  /// No description provided for @removeDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove “{title}”?'**
  String removeDocumentTitle(String title);

  /// No description provided for @removeDocumentMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{The document will be removed from this study set.} =1{Its highlight and excerpt card will be removed too. You can undo this with ⌘Z.} other{Its {count} highlights and their excerpt cards will be removed too. You can undo this with ⌘Z.}}'**
  String removeDocumentMessage(int count);

  /// No description provided for @renameEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get renameEllipsis;

  /// No description provided for @renameDocument.
  ///
  /// In en, this message translates to:
  /// **'Rename Document'**
  String get renameDocument;

  /// No description provided for @renameStudySet.
  ///
  /// In en, this message translates to:
  /// **'Rename Study Set'**
  String get renameStudySet;

  /// No description provided for @reviewCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review 1 Card} other{Review {count} Cards}}'**
  String reviewCount(int count);

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewTitle;

  /// No description provided for @reviewRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 left} other{{count} left}}'**
  String reviewRemaining(int count);

  /// No description provided for @reviewProgress.
  ///
  /// In en, this message translates to:
  /// **'Review progress'**
  String get reviewProgress;

  /// No description provided for @reviewDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'All done for now'**
  String get reviewDoneTitle;

  /// No description provided for @reviewDoneMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 card reviewed} other{{count} cards reviewed}}'**
  String reviewDoneMessage(int count);

  /// No description provided for @reviewNothingDueTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review'**
  String get reviewNothingDueTitle;

  /// No description provided for @showAnswer.
  ///
  /// In en, this message translates to:
  /// **'Show Answer'**
  String get showAnswer;

  /// No description provided for @startReview.
  ///
  /// In en, this message translates to:
  /// **'Start Review'**
  String get startReview;

  /// No description provided for @reviewBranch.
  ///
  /// In en, this message translates to:
  /// **'Review Branch'**
  String get reviewBranch;

  /// No description provided for @reviewTag.
  ///
  /// In en, this message translates to:
  /// **'Review Tag'**
  String get reviewTag;

  /// No description provided for @suspendCard.
  ///
  /// In en, this message translates to:
  /// **'Suspend Card'**
  String get suspendCard;

  /// No description provided for @resumeCard.
  ///
  /// In en, this message translates to:
  /// **'Resume Card'**
  String get resumeCard;

  /// No description provided for @cardSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get cardSuspended;

  /// No description provided for @sectionCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get sectionCards;

  /// No description provided for @intervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String intervalMinutes(int count);

  /// No description provided for @intervalHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String intervalHours(int count);

  /// No description provided for @intervalDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String intervalDays(int count);

  /// No description provided for @intervalMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String intervalMonths(int count);

  /// No description provided for @excerptInColor.
  ///
  /// In en, this message translates to:
  /// **'Excerpt in {color}'**
  String excerptInColor(String color);

  /// No description provided for @locateCard.
  ///
  /// In en, this message translates to:
  /// **'Locate Card'**
  String get locateCard;

  /// No description provided for @excerptWithNote.
  ///
  /// In en, this message translates to:
  /// **'Excerpt with Note'**
  String get excerptWithNote;

  /// No description provided for @addSiblingAfter.
  ///
  /// In en, this message translates to:
  /// **'Add Sibling After'**
  String get addSiblingAfter;

  /// No description provided for @addSiblingBefore.
  ///
  /// In en, this message translates to:
  /// **'Add Sibling Before'**
  String get addSiblingBefore;

  /// No description provided for @promoteNode.
  ///
  /// In en, this message translates to:
  /// **'Promote Node'**
  String get promoteNode;

  /// No description provided for @insertParentNode.
  ///
  /// In en, this message translates to:
  /// **'Insert Parent'**
  String get insertParentNode;

  /// No description provided for @toggleNodeFold.
  ///
  /// In en, this message translates to:
  /// **'Toggle Collapse'**
  String get toggleNodeFold;

  /// No description provided for @fitMap.
  ///
  /// In en, this message translates to:
  /// **'Show Entire Map'**
  String get fitMap;

  /// No description provided for @centerCurrentNode.
  ///
  /// In en, this message translates to:
  /// **'Locate Selected Node'**
  String get centerCurrentNode;

  /// No description provided for @cutNodes.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cutNodes;

  /// No description provided for @pasteNodes.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteNodes;

  /// No description provided for @newMap.
  ///
  /// In en, this message translates to:
  /// **'New Mind Map…'**
  String get newMap;

  /// No description provided for @newMapName.
  ///
  /// In en, this message translates to:
  /// **'Untitled Map'**
  String get newMapName;

  /// No description provided for @renameMap.
  ///
  /// In en, this message translates to:
  /// **'Rename Mind Map…'**
  String get renameMap;

  /// No description provided for @deleteMap.
  ///
  /// In en, this message translates to:
  /// **'Delete Mind Map'**
  String get deleteMap;

  /// No description provided for @addToNamedMap.
  ///
  /// In en, this message translates to:
  /// **'Add to “{title}”'**
  String addToNamedMap(String title);

  /// No description provided for @cardTags.
  ///
  /// In en, this message translates to:
  /// **'Tags…'**
  String get cardTags;

  /// No description provided for @sectionTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get sectionTags;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add Tag'**
  String get addTag;

  /// No description provided for @removeTag.
  ///
  /// In en, this message translates to:
  /// **'Remove Tag'**
  String get removeTag;

  /// No description provided for @allTags.
  ///
  /// In en, this message translates to:
  /// **'All Tags'**
  String get allTags;

  /// No description provided for @backToMap.
  ///
  /// In en, this message translates to:
  /// **'Back to Map'**
  String get backToMap;

  /// No description provided for @viewInMap.
  ///
  /// In en, this message translates to:
  /// **'View in Map'**
  String get viewInMap;

  /// No description provided for @tagNodesInMap.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 related node · Current map} other{{count} related nodes · Current map}}'**
  String tagNodesInMap(int count);

  /// No description provided for @tagNoNodes.
  ///
  /// In en, this message translates to:
  /// **'No nodes with this tag'**
  String get tagNoNodes;

  /// No description provided for @addRelation.
  ///
  /// In en, this message translates to:
  /// **'Add Relationship'**
  String get addRelation;

  /// No description provided for @addSummary.
  ///
  /// In en, this message translates to:
  /// **'Add Summary'**
  String get addSummary;

  /// No description provided for @newSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get newSummaryLabel;

  /// No description provided for @editMarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit Label'**
  String get editMarkLabel;

  /// No description provided for @deleteRelation.
  ///
  /// In en, this message translates to:
  /// **'Delete Relationship'**
  String get deleteRelation;

  /// No description provided for @deleteSummary.
  ///
  /// In en, this message translates to:
  /// **'Delete Summary'**
  String get deleteSummary;

  /// No description provided for @exportSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary: {label}'**
  String exportSummary(String label);

  /// No description provided for @exportRelations.
  ///
  /// In en, this message translates to:
  /// **'Relationships'**
  String get exportRelations;

  /// No description provided for @readerThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get readerThumbnails;

  /// No description provided for @readerOutline.
  ///
  /// In en, this message translates to:
  /// **'Table of Contents'**
  String get readerOutline;

  /// No description provided for @readerBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get readerBookmarks;

  /// No description provided for @readerAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get readerAnnotations;

  /// No description provided for @inkAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Hand-drawn annotations'**
  String get inkAnnotations;

  /// No description provided for @inkStrokeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stroke} other{{count} strokes}}'**
  String inkStrokeCount(int count);

  /// No description provided for @showReaderSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show Page Sidebar'**
  String get showReaderSidebar;

  /// No description provided for @hideReaderSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide Page Sidebar'**
  String get hideReaderSidebar;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add Bookmark'**
  String get addBookmark;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove Bookmark'**
  String get removeBookmark;

  /// No description provided for @renameBookmark.
  ///
  /// In en, this message translates to:
  /// **'Rename Bookmark…'**
  String get renameBookmark;

  /// No description provided for @deleteBookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete Bookmark'**
  String get deleteBookmark;

  /// No description provided for @findInDocument.
  ///
  /// In en, this message translates to:
  /// **'Find in Document'**
  String get findInDocument;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Find Next'**
  String get findNext;

  /// No description provided for @findPrevious.
  ///
  /// In en, this message translates to:
  /// **'Find Previous'**
  String get findPrevious;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No Results'**
  String get noResults;

  /// No description provided for @matchOf.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String matchOf(int current, int total);

  /// No description provided for @pageNumberField.
  ///
  /// In en, this message translates to:
  /// **'Page Number'**
  String get pageNumberField;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get goBack;

  /// No description provided for @firstPage.
  ///
  /// In en, this message translates to:
  /// **'First Page'**
  String get firstPage;

  /// No description provided for @lastPage.
  ///
  /// In en, this message translates to:
  /// **'Last Page'**
  String get lastPage;

  /// No description provided for @goToPage.
  ///
  /// In en, this message translates to:
  /// **'Go to Page…'**
  String get goToPage;

  /// No description provided for @menuGo.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get menuGo;

  /// No description provided for @enterFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Enter Full Screen'**
  String get enterFullScreen;

  /// No description provided for @exitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Full Screen'**
  String get exitFullScreen;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No Bookmarks'**
  String get noBookmarks;

  /// No description provided for @noAnnotations.
  ///
  /// In en, this message translates to:
  /// **'No Annotations'**
  String get noAnnotations;

  /// No description provided for @expandSection.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expandSection;

  /// No description provided for @collapseSection.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapseSection;

  /// No description provided for @pdfActualSize.
  ///
  /// In en, this message translates to:
  /// **'Actual Size'**
  String get pdfActualSize;

  /// No description provided for @pdfFitWidth.
  ///
  /// In en, this message translates to:
  /// **'Fit Width'**
  String get pdfFitWidth;

  /// No description provided for @pdfFitPage.
  ///
  /// In en, this message translates to:
  /// **'Fit Page'**
  String get pdfFitPage;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @statsReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get statsReviewed;

  /// No description provided for @statsRetention.
  ///
  /// In en, this message translates to:
  /// **'Retained'**
  String get statsRetention;

  /// No description provided for @statsUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Next 30 Days'**
  String get statsUpcoming;

  /// No description provided for @pdfOptions.
  ///
  /// In en, this message translates to:
  /// **'PDF Options'**
  String get pdfOptions;

  /// No description provided for @readerStyleWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerStyleWhite;

  /// No description provided for @readerStyleDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerStyleDark;

  /// No description provided for @readerStylePaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get readerStylePaper;

  /// No description provided for @readerStyleGreen.
  ///
  /// In en, this message translates to:
  /// **'Light Green'**
  String get readerStyleGreen;

  /// No description provided for @readerZoom.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get readerZoom;

  /// No description provided for @readerAppearance.
  ///
  /// In en, this message translates to:
  /// **'Reading Appearance'**
  String get readerAppearance;

  /// No description provided for @readerTheme.
  ///
  /// In en, this message translates to:
  /// **'Reading Theme'**
  String get readerTheme;

  /// No description provided for @readerTextLayout.
  ///
  /// In en, this message translates to:
  /// **'Text & Layout…'**
  String get readerTextLayout;

  /// No description provided for @readerPageFit.
  ///
  /// In en, this message translates to:
  /// **'Page Fit'**
  String get readerPageFit;

  /// No description provided for @readerMenuReading.
  ///
  /// In en, this message translates to:
  /// **'Reading Tools'**
  String get readerMenuReading;

  /// No description provided for @readerMenuPage.
  ///
  /// In en, this message translates to:
  /// **'Display Settings'**
  String get readerMenuPage;

  /// No description provided for @readerMenuTools.
  ///
  /// In en, this message translates to:
  /// **'Tools & Workspace'**
  String get readerMenuTools;

  /// No description provided for @research.
  ///
  /// In en, this message translates to:
  /// **'Research'**
  String get research;

  /// No description provided for @showResearchPanel.
  ///
  /// In en, this message translates to:
  /// **'Show Research Panel'**
  String get showResearchPanel;

  /// No description provided for @hideResearchPanel.
  ///
  /// In en, this message translates to:
  /// **'Hide Research Panel'**
  String get hideResearchPanel;

  /// No description provided for @researchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Select text or a map node to research'**
  String get researchEmptyTitle;

  /// No description provided for @showCardDetails.
  ///
  /// In en, this message translates to:
  /// **'Show Details'**
  String get showCardDetails;

  /// No description provided for @hideCardDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide Details'**
  String get hideCardDetails;

  /// No description provided for @closePanel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closePanel;

  /// No description provided for @expandCardText.
  ///
  /// In en, this message translates to:
  /// **'Show Full Text'**
  String get expandCardText;

  /// No description provided for @collapseCardText.
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get collapseCardText;

  /// No description provided for @toggleCardText.
  ///
  /// In en, this message translates to:
  /// **'Expand or Collapse Full Text'**
  String get toggleCardText;

  /// No description provided for @detailsExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Excerpt'**
  String get detailsExcerpt;

  /// No description provided for @detailsImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get detailsImage;

  /// No description provided for @detailsNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get detailsNote;

  /// No description provided for @detailsTopic.
  ///
  /// In en, this message translates to:
  /// **'Topic'**
  String get detailsTopic;

  /// No description provided for @addTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Title'**
  String get addTitle;

  /// No description provided for @revealSourcePage.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Source · Page {page}'**
  String revealSourcePage(int page);

  /// No description provided for @reviewStatusNew.
  ///
  /// In en, this message translates to:
  /// **'Not reviewed yet'**
  String get reviewStatusNew;

  /// No description provided for @reviewStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Next {date} · {count, plural, =1{reviewed once} other{reviewed {count} times}}'**
  String reviewStatusScheduled(DateTime date, int count);

  /// No description provided for @insertImage.
  ///
  /// In en, this message translates to:
  /// **'Insert Image…'**
  String get insertImage;

  /// No description provided for @imageFiles.
  ///
  /// In en, this message translates to:
  /// **'PNG / JPEG Images'**
  String get imageFiles;

  /// No description provided for @imageQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get imageQuestion;

  /// No description provided for @imageImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not import image. Choose a PNG or JPEG file.'**
  String get imageImportFailed;

  /// No description provided for @imageInserted.
  ///
  /// In en, this message translates to:
  /// **'Image inserted'**
  String get imageInserted;

  /// No description provided for @dropImage.
  ///
  /// In en, this message translates to:
  /// **'Drop to insert image'**
  String get dropImage;

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'Preview Image'**
  String get previewImage;

  /// No description provided for @ocrRecognize.
  ///
  /// In en, this message translates to:
  /// **'Recognize Text…'**
  String get ocrRecognize;

  /// No description provided for @ocrTitle.
  ///
  /// In en, this message translates to:
  /// **'Recognize Text'**
  String get ocrTitle;

  /// No description provided for @ocrStart.
  ///
  /// In en, this message translates to:
  /// **'Start Recognition'**
  String get ocrStart;

  /// No description provided for @ocrNoText.
  ///
  /// In en, this message translates to:
  /// **'No selectable text on this page'**
  String get ocrNoText;

  /// No description provided for @ocrRecognized.
  ///
  /// In en, this message translates to:
  /// **'Recognized'**
  String get ocrRecognized;

  /// No description provided for @ocrCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled · Completed pages kept'**
  String get ocrCancelled;

  /// No description provided for @ocrFailed.
  ///
  /// In en, this message translates to:
  /// **'Recognition failed · Try again'**
  String get ocrFailed;

  /// No description provided for @ocrProgress.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text {done}/{total}'**
  String ocrProgress(int done, int total);

  /// No description provided for @ocrScope.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get ocrScope;

  /// No description provided for @ocrAllPages.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get ocrAllPages;

  /// No description provided for @ocrCurrentPage.
  ///
  /// In en, this message translates to:
  /// **'Current page'**
  String get ocrCurrentPage;

  /// No description provided for @ocrPageRange.
  ///
  /// In en, this message translates to:
  /// **'Page range'**
  String get ocrPageRange;

  /// No description provided for @ocrLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get ocrLanguage;

  /// No description provided for @ocrChineseEnglish.
  ///
  /// In en, this message translates to:
  /// **'Chinese + English'**
  String get ocrChineseEnglish;

  /// No description provided for @ocrChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get ocrChinese;

  /// No description provided for @ocrEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get ocrEnglish;

  /// No description provided for @ocrFirstPage.
  ///
  /// In en, this message translates to:
  /// **'First page'**
  String get ocrFirstPage;

  /// No description provided for @ocrLastPage.
  ///
  /// In en, this message translates to:
  /// **'Last page'**
  String get ocrLastPage;

  /// No description provided for @ocrInvalidRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a range from 1 to {count}'**
  String ocrInvalidRange(int count);

  /// No description provided for @ocrThisPage.
  ///
  /// In en, this message translates to:
  /// **'Recognize This Page'**
  String get ocrThisPage;

  /// No description provided for @ocrCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel Text Recognition'**
  String get ocrCancel;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Map'**
  String get exportTitle;

  /// No description provided for @exportMap.
  ///
  /// In en, this message translates to:
  /// **'Export Map…'**
  String get exportMap;

  /// No description provided for @exportBranch.
  ///
  /// In en, this message translates to:
  /// **'Export This Branch…'**
  String get exportBranch;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get exportAction;

  /// No description provided for @exportFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exportFormat;

  /// No description provided for @exportRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get exportRange;

  /// No description provided for @exportWholeMap.
  ///
  /// In en, this message translates to:
  /// **'Entire map'**
  String get exportWholeMap;

  /// No description provided for @exportCurrentBranch.
  ///
  /// In en, this message translates to:
  /// **'Current branch'**
  String get exportCurrentBranch;

  /// No description provided for @exportAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get exportAppearance;

  /// No description provided for @exportLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get exportLight;

  /// No description provided for @exportDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get exportDark;

  /// No description provided for @exportTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get exportTransparent;

  /// No description provided for @exportScale.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get exportScale;

  /// No description provided for @exportLarge.
  ///
  /// In en, this message translates to:
  /// **'This image exceeds 8000 pixels. Some apps may not open it. Reduce the scale or use PDF.'**
  String get exportLarge;

  /// No description provided for @exportReduced.
  ///
  /// In en, this message translates to:
  /// **'Scale reduced automatically to fit image dimensions and memory limits.'**
  String get exportReduced;

  /// No description provided for @exportLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing export…'**
  String get exportLoading;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get exportFailed;

  /// No description provided for @exportRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get exportRetry;

  /// No description provided for @exportPixels.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} pixels'**
  String exportPixels(String width, String height);

  /// No description provided for @exportCentimeters.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} cm'**
  String exportCentimeters(String width, String height);

  /// No description provided for @exportResearchNote.
  ///
  /// In en, this message translates to:
  /// **'Research note'**
  String get exportResearchNote;

  /// No description provided for @exportSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get exportSource;

  /// No description provided for @formatBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get formatBold;

  /// No description provided for @formatItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get formatItalic;

  /// No description provided for @formatBulletList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted List'**
  String get formatBulletList;

  /// No description provided for @formatNumberList.
  ///
  /// In en, this message translates to:
  /// **'Numbered List'**
  String get formatNumberList;

  /// No description provided for @densityCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get densityCompact;

  /// No description provided for @densityFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get densityFull;

  /// No description provided for @switchMap.
  ///
  /// In en, this message translates to:
  /// **'Switch Map'**
  String get switchMap;

  /// No description provided for @mapStyle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get mapStyle;

  /// No description provided for @mapStructureMind.
  ///
  /// In en, this message translates to:
  /// **'Mind Map'**
  String get mapStructureMind;

  /// No description provided for @mapStructureLogic.
  ///
  /// In en, this message translates to:
  /// **'Logic Chart'**
  String get mapStructureLogic;

  /// No description provided for @mapStructureBrace.
  ///
  /// In en, this message translates to:
  /// **'Brace Map'**
  String get mapStructureBrace;

  /// No description provided for @mapStructureTree.
  ///
  /// In en, this message translates to:
  /// **'Tree Chart'**
  String get mapStructureTree;

  /// No description provided for @mapPaletteSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get mapPaletteSystem;

  /// No description provided for @mapPaletteRainbow.
  ///
  /// In en, this message translates to:
  /// **'Colorful'**
  String get mapPaletteRainbow;

  /// No description provided for @mapPaletteFresh.
  ///
  /// In en, this message translates to:
  /// **'Fresh'**
  String get mapPaletteFresh;

  /// No description provided for @mapPaletteWarm.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get mapPaletteWarm;

  /// No description provided for @mapPaletteMorandi.
  ///
  /// In en, this message translates to:
  /// **'Morandi'**
  String get mapPaletteMorandi;

  /// No description provided for @mapPaletteInk.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get mapPaletteInk;

  /// No description provided for @cardWidthHandle.
  ///
  /// In en, this message translates to:
  /// **'Card Width'**
  String get cardWidthHandle;

  /// No description provided for @resetCardWidth.
  ///
  /// In en, this message translates to:
  /// **'Reset Width'**
  String get resetCardWidth;

  /// No description provided for @detailsResearchNote.
  ///
  /// In en, this message translates to:
  /// **'Research Note'**
  String get detailsResearchNote;

  /// No description provided for @researchSelection.
  ///
  /// In en, this message translates to:
  /// **'Research Selection'**
  String get researchSelection;

  /// No description provided for @researchSelectionEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Research Selection…'**
  String get researchSelectionEllipsis;

  /// No description provided for @researchNode.
  ///
  /// In en, this message translates to:
  /// **'Research Node'**
  String get researchNode;

  /// No description provided for @researchNodeMenu.
  ///
  /// In en, this message translates to:
  /// **'Research “{title}”'**
  String researchNodeMenu(String title);

  /// No description provided for @researchIntentExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get researchIntentExplain;

  /// No description provided for @researchIntentInterpret.
  ///
  /// In en, this message translates to:
  /// **'Interpret'**
  String get researchIntentInterpret;

  /// No description provided for @researchIntentVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get researchIntentVerify;

  /// No description provided for @researchIntentVideo.
  ///
  /// In en, this message translates to:
  /// **'Videos / Diagrams'**
  String get researchIntentVideo;

  /// No description provided for @researchIntentPaper.
  ///
  /// In en, this message translates to:
  /// **'Find Papers'**
  String get researchIntentPaper;

  /// No description provided for @researchIntentDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep Research'**
  String get researchIntentDeep;

  /// No description provided for @researchIntentTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get researchIntentTranslate;

  /// No description provided for @researchRecommended.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get researchRecommended;

  /// No description provided for @researchQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get researchQuestion;

  /// No description provided for @researchQuestionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What do you want to find out?'**
  String get researchQuestionPlaceholder;

  /// No description provided for @researchQuestionExplain.
  ///
  /// In en, this message translates to:
  /// **'What does “{term}” mean? Give an example from the context.'**
  String researchQuestionExplain(String term);

  /// No description provided for @researchQuestionInterpret.
  ///
  /// In en, this message translates to:
  /// **'What are this passage\'s claim, reasoning and assumptions?'**
  String get researchQuestionInterpret;

  /// No description provided for @researchQuestionVerify.
  ///
  /// In en, this message translates to:
  /// **'Is this claim supported? Are there counterexamples or limits?'**
  String get researchQuestionVerify;

  /// No description provided for @researchQuestionVerifyQuote.
  ///
  /// In en, this message translates to:
  /// **'“{quote}” — is this reliable? Are there counterexamples or limits?'**
  String researchQuestionVerifyQuote(String quote);

  /// No description provided for @researchQuestionVideo.
  ///
  /// In en, this message translates to:
  /// **'Find a clear video or diagram explaining “{term}”'**
  String researchQuestionVideo(String term);

  /// No description provided for @researchQuestionPaper.
  ///
  /// In en, this message translates to:
  /// **'What are the key studies on “{term}”? Their findings and limits?'**
  String researchQuestionPaper(String term);

  /// No description provided for @researchQuestionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate this passage and explain its terms.'**
  String get researchQuestionTranslate;

  /// No description provided for @researchKeywords.
  ///
  /// In en, this message translates to:
  /// **'Keywords'**
  String get researchKeywords;

  /// No description provided for @researchAddKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add keyword'**
  String get researchAddKeyword;

  /// No description provided for @researchSourcesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get researchSourcesLabel;

  /// No description provided for @researchKindWeb.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get researchKindWeb;

  /// No description provided for @researchKindPaper.
  ///
  /// In en, this message translates to:
  /// **'Papers'**
  String get researchKindPaper;

  /// No description provided for @researchKindVideo.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get researchKindVideo;

  /// No description provided for @researchKindImage.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get researchKindImage;

  /// No description provided for @researchMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get researchMethod;

  /// No description provided for @researchMethodSearch.
  ///
  /// In en, this message translates to:
  /// **'Search Only'**
  String get researchMethodSearch;

  /// No description provided for @researchMethodOffline.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get researchMethodOffline;

  /// No description provided for @researchMethodWeb.
  ///
  /// In en, this message translates to:
  /// **'Web Research'**
  String get researchMethodWeb;

  /// No description provided for @researchMethodSearchNote.
  ///
  /// In en, this message translates to:
  /// **'No AI, no AI cost'**
  String get researchMethodSearchNote;

  /// No description provided for @researchMethodOfflineNote.
  ///
  /// In en, this message translates to:
  /// **'Sends only the selection and its context; no web search'**
  String get researchMethodOfflineNote;

  /// No description provided for @researchMethodWebNote.
  ///
  /// In en, this message translates to:
  /// **'Up to {searches} searches and {pages} pages'**
  String researchMethodWebNote(int searches, int pages);

  /// No description provided for @researchSetUpAi.
  ///
  /// In en, this message translates to:
  /// **'Set Up AI…'**
  String get researchSetUpAi;

  /// No description provided for @researchNoAi.
  ///
  /// In en, this message translates to:
  /// **'No AI service set up'**
  String get researchNoAi;

  /// No description provided for @researchNoAiTitle.
  ///
  /// In en, this message translates to:
  /// **'No AI service set up'**
  String get researchNoAiTitle;

  /// No description provided for @researchNoWeb.
  ///
  /// In en, this message translates to:
  /// **'This service can\'t search the web'**
  String get researchNoWeb;

  /// No description provided for @researchContextSummary.
  ///
  /// In en, this message translates to:
  /// **'Sent to AI: {parts} (about {count} characters)'**
  String researchContextSummary(String parts, int count);

  /// No description provided for @researchContextSelection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get researchContextSelection;

  /// No description provided for @researchContextBefore.
  ///
  /// In en, this message translates to:
  /// **'Previous passage'**
  String get researchContextBefore;

  /// No description provided for @researchContextAfter.
  ///
  /// In en, this message translates to:
  /// **'Next passage'**
  String get researchContextAfter;

  /// No description provided for @researchContextChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get researchContextChapter;

  /// No description provided for @researchContextNode.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get researchContextNode;

  /// No description provided for @researchContextPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get researchContextPath;

  /// No description provided for @researchContextChildren.
  ///
  /// In en, this message translates to:
  /// **'Cards below'**
  String get researchContextChildren;

  /// No description provided for @researchRunningChoice.
  ///
  /// In en, this message translates to:
  /// **'A research is running'**
  String get researchRunningChoice;

  /// No description provided for @researchAsNew.
  ///
  /// In en, this message translates to:
  /// **'New Research'**
  String get researchAsNew;

  /// No description provided for @researchJoin.
  ///
  /// In en, this message translates to:
  /// **'Add to Current Question'**
  String get researchJoin;

  /// No description provided for @researchLater.
  ///
  /// In en, this message translates to:
  /// **'Research Later'**
  String get researchLater;

  /// No description provided for @researchStart.
  ///
  /// In en, this message translates to:
  /// **'Start Research'**
  String get researchStart;

  /// No description provided for @researchNeedQuestion.
  ///
  /// In en, this message translates to:
  /// **'Write a question first'**
  String get researchNeedQuestion;

  /// No description provided for @researchSavedForLater.
  ///
  /// In en, this message translates to:
  /// **'Saved to Research Later'**
  String get researchSavedForLater;

  /// No description provided for @researchJoined.
  ///
  /// In en, this message translates to:
  /// **'Added to the current research'**
  String get researchJoined;

  /// No description provided for @researchSettings.
  ///
  /// In en, this message translates to:
  /// **'Research Settings'**
  String get researchSettings;

  /// No description provided for @researchBackToOrigin.
  ///
  /// In en, this message translates to:
  /// **'Back to Where It Started'**
  String get researchBackToOrigin;

  /// No description provided for @researchOriginGone.
  ///
  /// In en, this message translates to:
  /// **'The original place was deleted'**
  String get researchOriginGone;

  /// No description provided for @researchStageSearch.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get researchStageSearch;

  /// No description provided for @researchStageAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answering'**
  String get researchStageAnswer;

  /// No description provided for @researchStageWebAnswer.
  ///
  /// In en, this message translates to:
  /// **'Searching and answering'**
  String get researchStageWebAnswer;

  /// No description provided for @researchStageRead.
  ///
  /// In en, this message translates to:
  /// **'Reading sources {done}/{total}'**
  String researchStageRead(int done, int total);

  /// No description provided for @researchRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get researchRetry;

  /// No description provided for @researchRestart.
  ///
  /// In en, this message translates to:
  /// **'Start Again'**
  String get researchRestart;

  /// No description provided for @researchCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get researchCancelled;

  /// No description provided for @researchInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted when the app quit'**
  String get researchInterrupted;

  /// No description provided for @researchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get researchFailed;

  /// No description provided for @researchRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get researchRunning;

  /// No description provided for @researchDoneAt.
  ///
  /// In en, this message translates to:
  /// **'Finished {time}'**
  String researchDoneAt(String time);

  /// No description provided for @researchUsedSources.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 source used} other{{count} sources used}}'**
  String researchUsedSources(int count);

  /// No description provided for @researchErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get researchErrorTimeout;

  /// No description provided for @researchErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the service'**
  String get researchErrorUnavailable;

  /// No description provided for @researchErrorAuthentication.
  ///
  /// In en, this message translates to:
  /// **'The API key was rejected'**
  String get researchErrorAuthentication;

  /// No description provided for @researchErrorBudget.
  ///
  /// In en, this message translates to:
  /// **'Reached the limit'**
  String get researchErrorBudget;

  /// No description provided for @researchErrorRefusal.
  ///
  /// In en, this message translates to:
  /// **'The AI declined to answer'**
  String get researchErrorRefusal;

  /// No description provided for @researchErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported by this service'**
  String get researchErrorUnsupported;

  /// No description provided for @researchErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'The request was not accepted'**
  String get researchErrorInvalid;

  /// No description provided for @researchErrorProtocol.
  ///
  /// In en, this message translates to:
  /// **'The answer was incomplete'**
  String get researchErrorProtocol;

  /// No description provided for @researchTabAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get researchTabAnswer;

  /// No description provided for @researchTabSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get researchTabSources;

  /// No description provided for @researchTabSaved.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get researchTabSaved;

  /// No description provided for @researchBadgeWeb.
  ///
  /// In en, this message translates to:
  /// **'Web research · {count, plural, =1{1 source used} other{{count} sources used}}'**
  String researchBadgeWeb(int count);

  /// No description provided for @researchBadgeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline · no external sources, so no citations'**
  String get researchBadgeOffline;

  /// No description provided for @researchBadgeSources.
  ///
  /// In en, this message translates to:
  /// **'Only the {count, plural, =1{source} other{{count} sources}} you chose; no web search'**
  String researchBadgeSources(int count);

  /// No description provided for @researchViewSources.
  ///
  /// In en, this message translates to:
  /// **'View Sources'**
  String get researchViewSources;

  /// No description provided for @researchNoSourceBasis.
  ///
  /// In en, this message translates to:
  /// **'no source'**
  String get researchNoSourceBasis;

  /// No description provided for @researchEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get researchEdited;

  /// No description provided for @researchQuoteFrom.
  ///
  /// In en, this message translates to:
  /// **'Source [{number}] · original text'**
  String researchQuoteFrom(int number);

  /// No description provided for @researchEditPoint.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get researchEditPoint;

  /// No description provided for @researchAskPoint.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get researchAskPoint;

  /// No description provided for @researchSavePoint.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get researchSavePoint;

  /// No description provided for @researchAskAbout.
  ///
  /// In en, this message translates to:
  /// **'About “{point}”: '**
  String researchAskAbout(String point);

  /// No description provided for @researchFailedSources.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 source} other{{count} sources}} couldn\'t be read'**
  String researchFailedSources(int count);

  /// No description provided for @researchChecked.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String researchChecked(int count);

  /// No description provided for @researchClearChecked.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get researchClearChecked;

  /// No description provided for @researchSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Save as Research Note…'**
  String get researchSaveNote;

  /// No description provided for @researchNoAnswerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search only: no answer'**
  String get researchNoAnswerSearch;

  /// No description provided for @researchNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No answer yet'**
  String get researchNoAnswer;

  /// No description provided for @researchAnswerFromChosen.
  ///
  /// In en, this message translates to:
  /// **'Answer from {count, plural, =1{1 Chosen Source} other{{count} Chosen Sources}}'**
  String researchAnswerFromChosen(int count);

  /// No description provided for @researchAnswering.
  ///
  /// In en, this message translates to:
  /// **'Answering…'**
  String get researchAnswering;

  /// No description provided for @researchFollowUpPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Ask a follow-up…'**
  String get researchFollowUpPlaceholder;

  /// No description provided for @researchCanUseWeb.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get researchCanUseWeb;

  /// No description provided for @researchOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get researchOffline;

  /// No description provided for @researchSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get researchSend;

  /// No description provided for @researchFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get researchFilterAll;

  /// No description provided for @researchReadUnread.
  ///
  /// In en, this message translates to:
  /// **'Not read'**
  String get researchReadUnread;

  /// No description provided for @researchReadSnippet.
  ///
  /// In en, this message translates to:
  /// **'Search snippet'**
  String get researchReadSnippet;

  /// No description provided for @researchReadAbstract.
  ///
  /// In en, this message translates to:
  /// **'Abstract only'**
  String get researchReadAbstract;

  /// No description provided for @researchReadFullText.
  ///
  /// In en, this message translates to:
  /// **'Full text'**
  String get researchReadFullText;

  /// No description provided for @researchReadTranscript.
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get researchReadTranscript;

  /// No description provided for @researchReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read'**
  String get researchReadFailed;

  /// No description provided for @researchReadNoTranscript.
  ///
  /// In en, this message translates to:
  /// **'No transcript'**
  String get researchReadNoTranscript;

  /// No description provided for @researchOpenAccess.
  ///
  /// In en, this message translates to:
  /// **'Open access'**
  String get researchOpenAccess;

  /// No description provided for @researchSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get researchSubscription;

  /// No description provided for @researchUsedInAnswer.
  ///
  /// In en, this message translates to:
  /// **'Used in answer'**
  String get researchUsedInAnswer;

  /// No description provided for @researchMerged.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 reprint merged} other{{count} reprints merged}}, not counted separately'**
  String researchMerged(int count);

  /// No description provided for @researchRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get researchRead;

  /// No description provided for @researchWhyFailed.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get researchWhyFailed;

  /// No description provided for @researchChoose.
  ///
  /// In en, this message translates to:
  /// **'Add to Sources'**
  String get researchChoose;

  /// No description provided for @researchChosen.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get researchChosen;

  /// No description provided for @researchPasted.
  ///
  /// In en, this message translates to:
  /// **'Pasted by you'**
  String get researchPasted;

  /// No description provided for @researchExternalSearch.
  ///
  /// In en, this message translates to:
  /// **'Search “{query}” on {site}'**
  String researchExternalSearch(String site, String query);

  /// No description provided for @researchExternal.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get researchExternal;

  /// No description provided for @researchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching: {keywords}'**
  String researchSearching(String keywords);

  /// No description provided for @researchNoSources.
  ///
  /// In en, this message translates to:
  /// **'No sources'**
  String get researchNoSources;

  /// No description provided for @researchOfflineNoSources.
  ///
  /// In en, this message translates to:
  /// **'This research did not search the web'**
  String get researchOfflineNoSources;

  /// No description provided for @researchOpenPage.
  ///
  /// In en, this message translates to:
  /// **'Open Page'**
  String get researchOpenPage;

  /// No description provided for @researchFetchedAt.
  ///
  /// In en, this message translates to:
  /// **'Fetched {date}'**
  String researchFetchedAt(String date);

  /// No description provided for @researchAiSummary.
  ///
  /// In en, this message translates to:
  /// **'AI summary · not the source'**
  String get researchAiSummary;

  /// No description provided for @researchSummarize.
  ///
  /// In en, this message translates to:
  /// **'AI Summary'**
  String get researchSummarize;

  /// No description provided for @researchClipEvidence.
  ///
  /// In en, this message translates to:
  /// **'Take as Evidence'**
  String get researchClipEvidence;

  /// No description provided for @researchWriteNote.
  ///
  /// In en, this message translates to:
  /// **'Write Note…'**
  String get researchWriteNote;

  /// No description provided for @researchClipped.
  ///
  /// In en, this message translates to:
  /// **'Taken ({count})'**
  String researchClipped(int count);

  /// No description provided for @researchCantRead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the text'**
  String get researchCantRead;

  /// No description provided for @researchReadLogin.
  ///
  /// In en, this message translates to:
  /// **'The page needs a sign-in'**
  String get researchReadLogin;

  /// No description provided for @researchReadTimeout.
  ///
  /// In en, this message translates to:
  /// **'The page took too long.'**
  String get researchReadTimeout;

  /// No description provided for @researchReadUnparseable.
  ///
  /// In en, this message translates to:
  /// **'No article text was found.'**
  String get researchReadUnparseable;

  /// No description provided for @researchReadUnsafe.
  ///
  /// In en, this message translates to:
  /// **'This address is not allowed.'**
  String get researchReadUnsafe;

  /// No description provided for @researchReadUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This is not a web page.'**
  String get researchReadUnsupported;

  /// No description provided for @researchReadEncoding.
  ///
  /// In en, this message translates to:
  /// **'The page\'s text encoding is not supported.'**
  String get researchReadEncoding;

  /// No description provided for @researchReadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the page.'**
  String get researchReadUnavailable;

  /// No description provided for @researchPasteText.
  ///
  /// In en, this message translates to:
  /// **'Paste Text…'**
  String get researchPasteText;

  /// No description provided for @researchSaveLinkOnly.
  ///
  /// In en, this message translates to:
  /// **'Save Link Only'**
  String get researchSaveLinkOnly;

  /// No description provided for @researchReadAgain.
  ///
  /// In en, this message translates to:
  /// **'Read Again'**
  String get researchReadAgain;

  /// No description provided for @researchAbstractOnly.
  ///
  /// In en, this message translates to:
  /// **'Only the abstract was read'**
  String get researchAbstractOnly;

  /// No description provided for @researchOpenPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher Page'**
  String get researchOpenPublisher;

  /// No description provided for @researchPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Text'**
  String get researchPasteTitle;

  /// No description provided for @researchClipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence (draft)'**
  String get researchClipsTitle;

  /// No description provided for @researchSavedNotes.
  ///
  /// In en, this message translates to:
  /// **'Saved research notes'**
  String get researchSavedNotes;

  /// No description provided for @researchNoteFromClips.
  ///
  /// In en, this message translates to:
  /// **'Write Note from Evidence…'**
  String get researchNoteFromClips;

  /// No description provided for @researchNothingSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing taken yet'**
  String get researchNothingSaved;

  /// No description provided for @researchInSource.
  ///
  /// In en, this message translates to:
  /// **'Source · p. {page}'**
  String researchInSource(int page);

  /// No description provided for @researchInMap.
  ///
  /// In en, this message translates to:
  /// **'Map · {title}'**
  String researchInMap(String title);

  /// No description provided for @researchCitations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 citation} other{{count} citations}}'**
  String researchCitations(int count);

  /// No description provided for @researchContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get researchContinue;

  /// No description provided for @researchSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Research Note'**
  String get researchSaveTitle;

  /// No description provided for @researchNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get researchNoteTitle;

  /// No description provided for @researchNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get researchNoteBody;

  /// No description provided for @researchNoteDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Research note'**
  String get researchNoteDefaultTitle;

  /// No description provided for @researchCitationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Citations ({count})'**
  String researchCitationsLabel(int count);

  /// No description provided for @researchNoExternalBasis.
  ///
  /// In en, this message translates to:
  /// **'No external source'**
  String get researchNoExternalBasis;

  /// No description provided for @researchSaveTo.
  ///
  /// In en, this message translates to:
  /// **'Save to'**
  String get researchSaveTo;

  /// No description provided for @researchDestBoth.
  ///
  /// In en, this message translates to:
  /// **'Source and Map'**
  String get researchDestBoth;

  /// No description provided for @researchDestSource.
  ///
  /// In en, this message translates to:
  /// **'Source Only'**
  String get researchDestSource;

  /// No description provided for @researchDestMap.
  ///
  /// In en, this message translates to:
  /// **'Map Only'**
  String get researchDestMap;

  /// No description provided for @researchDestNoSource.
  ///
  /// In en, this message translates to:
  /// **'Started from a node: no place in the source'**
  String get researchDestNoSource;

  /// No description provided for @researchAttachUnder.
  ///
  /// In en, this message translates to:
  /// **'In the map under'**
  String get researchAttachUnder;

  /// No description provided for @researchSplitPoints.
  ///
  /// In en, this message translates to:
  /// **'Split the {count} points into child cards'**
  String researchSplitPoints(int count);

  /// No description provided for @researchSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get researchSaving;

  /// No description provided for @researchSavedBoth.
  ///
  /// In en, this message translates to:
  /// **'Saved to the source and the map'**
  String get researchSavedBoth;

  /// No description provided for @researchSavedSource.
  ///
  /// In en, this message translates to:
  /// **'Saved to the source'**
  String get researchSavedSource;

  /// No description provided for @researchSavedMap.
  ///
  /// In en, this message translates to:
  /// **'Saved to the map'**
  String get researchSavedMap;

  /// No description provided for @researchShowInMap.
  ///
  /// In en, this message translates to:
  /// **'Show in Map'**
  String get researchShowInMap;

  /// No description provided for @researchCardKind.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Research note} =1{Research note · 1 source} other{Research note · {count} sources}}'**
  String researchCardKind(int count);

  /// No description provided for @researchCardOpen.
  ///
  /// In en, this message translates to:
  /// **'Full note and citations'**
  String get researchCardOpen;

  /// No description provided for @researchNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Research note: {title}'**
  String researchNoteLabel(String title);

  /// No description provided for @researchLocateInMap.
  ///
  /// In en, this message translates to:
  /// **'Locate in Map'**
  String get researchLocateInMap;

  /// No description provided for @researchOpenResearch.
  ///
  /// In en, this message translates to:
  /// **'Open Research'**
  String get researchOpenResearch;

  /// No description provided for @researchPlaces.
  ///
  /// In en, this message translates to:
  /// **'Shown in'**
  String get researchPlaces;

  /// No description provided for @researchPlaceSource.
  ///
  /// In en, this message translates to:
  /// **'{document} · p. {page}'**
  String researchPlaceSource(String document, int page);

  /// No description provided for @researchLocate.
  ///
  /// In en, this message translates to:
  /// **'Locate'**
  String get researchLocate;

  /// No description provided for @researchDetach.
  ///
  /// In en, this message translates to:
  /// **'Detach'**
  String get researchDetach;

  /// No description provided for @researchNotInSource.
  ///
  /// In en, this message translates to:
  /// **'Not attached to the source'**
  String get researchNotInSource;

  /// No description provided for @researchNoteGone.
  ///
  /// In en, this message translates to:
  /// **'This note was deleted'**
  String get researchNoteGone;

  /// No description provided for @researchDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete Research Note…'**
  String get researchDeleteNote;

  /// No description provided for @researchDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this research note?'**
  String get researchDeleteTitle;

  /// No description provided for @researchDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'{marks, plural, =0{} =1{Its source mark goes too. } other{Its {marks} source marks go too. }}{cards, plural, =0{} =1{Its map card goes too.} other{Its {cards} map cards go too.}}'**
  String researchDeleteMessage(int marks, int cards);

  /// No description provided for @researchService.
  ///
  /// In en, this message translates to:
  /// **'AI service'**
  String get researchService;

  /// No description provided for @researchServiceNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get researchServiceNone;

  /// No description provided for @researchServiceCompatible.
  ///
  /// In en, this message translates to:
  /// **'Compatible'**
  String get researchServiceCompatible;

  /// No description provided for @researchServiceIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Add the model to finish setting up this service'**
  String get researchServiceIncomplete;

  /// No description provided for @researchApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get researchApiKey;

  /// No description provided for @researchKeySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved in the Keychain'**
  String get researchKeySaved;

  /// No description provided for @researchKeyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save to the Keychain'**
  String get researchKeyFailed;

  /// No description provided for @researchModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get researchModel;

  /// No description provided for @researchEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get researchEndpoint;

  /// No description provided for @researchPaperSearch.
  ///
  /// In en, this message translates to:
  /// **'Paper search'**
  String get researchPaperSearch;

  /// No description provided for @researchLimits.
  ///
  /// In en, this message translates to:
  /// **'Web research limits'**
  String get researchLimits;

  /// No description provided for @researchLimitSearches.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 search} other{{count} searches}}'**
  String researchLimitSearches(int count);

  /// No description provided for @researchLimitPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String researchLimitPages(int count);

  /// No description provided for @researchLimitMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String researchLimitMinutes(int count);

  /// No description provided for @researchPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get researchPrivacy;

  /// No description provided for @researchShowContext.
  ///
  /// In en, this message translates to:
  /// **'Show what will be sent before starting'**
  String get researchShowContext;

  /// No description provided for @researchBlockPrivate.
  ///
  /// In en, this message translates to:
  /// **'Block local and private addresses'**
  String get researchBlockPrivate;

  /// No description provided for @researchCache.
  ///
  /// In en, this message translates to:
  /// **'Web cache'**
  String get researchCache;

  /// No description provided for @researchClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get researchClearCache;

  /// No description provided for @researchCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Web cache cleared'**
  String get researchCacheCleared;

  /// No description provided for @researchInterruptedShort.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get researchInterruptedShort;

  /// No description provided for @researchAddReview.
  ///
  /// In en, this message translates to:
  /// **'Add to review'**
  String get researchAddReview;

  /// No description provided for @researchSaveVideo.
  ///
  /// In en, this message translates to:
  /// **'Save video link…'**
  String get researchSaveVideo;

  /// No description provided for @researchVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Video URL'**
  String get researchVideoUrl;

  /// No description provided for @researchInvalidVideo.
  ///
  /// In en, this message translates to:
  /// **'Enter a YouTube or Bilibili video URL.'**
  String get researchInvalidVideo;

  /// No description provided for @researchViewMore.
  ///
  /// In en, this message translates to:
  /// **'View more'**
  String get researchViewMore;

  /// No description provided for @researchHistory.
  ///
  /// In en, this message translates to:
  /// **'Research history'**
  String get researchHistory;

  /// No description provided for @researchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete research'**
  String get researchDelete;

  /// No description provided for @researchErrorUnsafeUrl.
  ///
  /// In en, this message translates to:
  /// **'Address blocked by network validation'**
  String get researchErrorUnsafeUrl;

  /// No description provided for @researchErrorTls.
  ///
  /// In en, this message translates to:
  /// **'Could not establish a secure connection'**
  String get researchErrorTls;

  /// No description provided for @researchFixAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Check your API key, model permissions and account balance, then retry.'**
  String get researchFixAuthentication;

  /// No description provided for @researchFixRequest.
  ///
  /// In en, this message translates to:
  /// **'Check the endpoint, model name and supported API protocol. Compatible services accept a base URL (such as https://example.com/v1) or a full chat/completions URL.'**
  String get researchFixRequest;

  /// No description provided for @researchFixUnsafeUrl.
  ///
  /// In en, this message translates to:
  /// **'Check the endpoint and proxy DNS settings. Web fetching blocks private addresses; proxy fake-IP addresses are supported only for explicitly configured HTTPS AI endpoints.'**
  String get researchFixUnsafeUrl;

  /// No description provided for @researchFixTls.
  ///
  /// In en, this message translates to:
  /// **'Check the system clock, server certificate and proxy settings. Certificate failures are not retried automatically.'**
  String get researchFixTls;

  /// No description provided for @researchFixRateLimit.
  ///
  /// In en, this message translates to:
  /// **'The provider limited requests or account usage. Bounded retries were attempted; wait before retrying or check your balance and quota.'**
  String get researchFixRateLimit;

  /// No description provided for @researchFixConnection.
  ///
  /// In en, this message translates to:
  /// **'Check your network, proxy and provider status, or increase the research time limit. Temporary connection failures get bounded retries; once the deadline expires or output starts, retry manually.'**
  String get researchFixConnection;

  /// No description provided for @researchFixProtocol.
  ///
  /// In en, this message translates to:
  /// **'The response was incomplete or used a different API format. Check streaming support. Existing output is preserved; retry manually.'**
  String get researchFixProtocol;

  /// No description provided for @researchFixBudget.
  ///
  /// In en, this message translates to:
  /// **'A research input or output limit was reached. Narrow the question, select fewer sources or adjust research settings.'**
  String get researchFixBudget;

  /// No description provided for @researchDiagnosticCode.
  ///
  /// In en, this message translates to:
  /// **'Error code: {code}'**
  String researchDiagnosticCode(String code);

  /// No description provided for @assistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistant;

  /// No description provided for @askAssistant.
  ///
  /// In en, this message translates to:
  /// **'Ask Assistant'**
  String get askAssistant;

  /// No description provided for @askAssistantEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Ask Assistant…'**
  String get askAssistantEllipsis;

  /// No description provided for @showAssistant.
  ///
  /// In en, this message translates to:
  /// **'Show Assistant'**
  String get showAssistant;

  /// No description provided for @hideAssistant.
  ///
  /// In en, this message translates to:
  /// **'Hide Assistant'**
  String get hideAssistant;

  /// No description provided for @assistantNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get assistantNewConversation;

  /// No description provided for @assistantHistory.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get assistantHistory;

  /// No description provided for @assistantConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get assistantConversations;

  /// No description provided for @assistantNoConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get assistantNoConversations;

  /// No description provided for @assistantPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Ask…'**
  String get assistantPlaceholder;

  /// No description provided for @assistantConnectFirst.
  ///
  /// In en, this message translates to:
  /// **'Configure a model first'**
  String get assistantConnectFirst;

  /// No description provided for @assistantMention.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get assistantMention;

  /// No description provided for @assistantCommands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get assistantCommands;

  /// No description provided for @assistantOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get assistantOnline;

  /// No description provided for @assistantOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get assistantOffline;

  /// No description provided for @assistantSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get assistantSend;

  /// No description provided for @assistantStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get assistantStop;

  /// No description provided for @assistantPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Your permission is needed'**
  String get assistantPermissionTitle;

  /// No description provided for @assistantPermissionWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for permission'**
  String get assistantPermissionWaiting;

  /// No description provided for @assistantPermissionExplain.
  ///
  /// In en, this message translates to:
  /// **'The assistant wants to read this content for context to answer your question.'**
  String get assistantPermissionExplain;

  /// No description provided for @assistantPermissionScope.
  ///
  /// In en, this message translates to:
  /// **'Applies to this answer only. Content is read after you allow it.'**
  String get assistantPermissionScope;

  /// No description provided for @assistantPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow for this answer'**
  String get assistantPermissionAllow;

  /// No description provided for @assistantPermissionDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get assistantPermissionDeny;

  /// No description provided for @assistantPermissionAllowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed for this answer'**
  String get assistantPermissionAllowed;

  /// No description provided for @assistantPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get assistantPermissionDenied;

  /// No description provided for @assistantPermissionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get assistantPermissionCancelled;

  /// No description provided for @assistantPermissionPages.
  ///
  /// In en, this message translates to:
  /// **'{document} · pages {from}–{to}'**
  String assistantPermissionPages(String document, int from, int to);

  /// No description provided for @assistantPermissionSelection.
  ///
  /// In en, this message translates to:
  /// **'Selected text · {title}'**
  String assistantPermissionSelection(String title);

  /// No description provided for @assistantPermissionBranch.
  ///
  /// In en, this message translates to:
  /// **'Map branch · {title}'**
  String assistantPermissionBranch(String title);

  /// No description provided for @assistantToolReadSelection.
  ///
  /// In en, this message translates to:
  /// **'Reading the selection'**
  String get assistantToolReadSelection;

  /// No description provided for @assistantToolReadPages.
  ///
  /// In en, this message translates to:
  /// **'Reading pages'**
  String get assistantToolReadPages;

  /// No description provided for @assistantToolSearch.
  ///
  /// In en, this message translates to:
  /// **'Searching the study set'**
  String get assistantToolSearch;

  /// No description provided for @assistantToolReadBranch.
  ///
  /// In en, this message translates to:
  /// **'Reading the branch'**
  String get assistantToolReadBranch;

  /// No description provided for @assistantToolWebSearch.
  ///
  /// In en, this message translates to:
  /// **'Searching the web'**
  String get assistantToolWebSearch;

  /// No description provided for @assistantToolPapers.
  ///
  /// In en, this message translates to:
  /// **'Finding papers'**
  String get assistantToolPapers;

  /// No description provided for @assistantToolFetch.
  ///
  /// In en, this message translates to:
  /// **'Reading a page'**
  String get assistantToolFetch;

  /// No description provided for @assistantToolPropose.
  ///
  /// In en, this message translates to:
  /// **'Preparing changes'**
  String get assistantToolPropose;

  /// No description provided for @assistantToolSkills.
  ///
  /// In en, this message translates to:
  /// **'Choosing an approach'**
  String get assistantToolSkills;

  /// No description provided for @assistantToolOther.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get assistantToolOther;

  /// No description provided for @assistantNotOnline.
  ///
  /// In en, this message translates to:
  /// **'Not checked online'**
  String get assistantNotOnline;

  /// No description provided for @assistantInsertChild.
  ///
  /// In en, this message translates to:
  /// **'Insert as Child Node'**
  String get assistantInsertChild;

  /// No description provided for @assistantSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Take Note'**
  String get assistantSaveNote;

  /// No description provided for @assistantAnswerToMap.
  ///
  /// In en, this message translates to:
  /// **'Turn into Mind Map'**
  String get assistantAnswerToMap;

  /// No description provided for @assistantAnswerToMapPrompt.
  ///
  /// In en, this message translates to:
  /// **'Turn the following answer into a mind map, preserving its main points and hierarchy. Propose map edits for review:\n\n{answer}'**
  String assistantAnswerToMapPrompt(String answer);

  /// No description provided for @assistantSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Saved as Note'**
  String get assistantSavedNote;

  /// No description provided for @assistantLocate.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get assistantLocate;

  /// No description provided for @assistantRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get assistantRegenerate;

  /// No description provided for @assistantErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable'**
  String get assistantErrorNetwork;

  /// No description provided for @assistantErrorKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid API key'**
  String get assistantErrorKey;

  /// No description provided for @assistantErrorService.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily unavailable'**
  String get assistantErrorService;

  /// No description provided for @assistantErrorBudget.
  ///
  /// In en, this message translates to:
  /// **'Over this answer\'s limit'**
  String get assistantErrorBudget;

  /// No description provided for @assistantErrorRefused.
  ///
  /// In en, this message translates to:
  /// **'The model declined to answer'**
  String get assistantErrorRefused;

  /// No description provided for @assistantErrorToolProtocol.
  ///
  /// In en, this message translates to:
  /// **'The model could not call tools correctly'**
  String get assistantErrorToolProtocol;

  /// No description provided for @assistantErrorFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get assistantErrorFailed;

  /// No description provided for @assistantStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get assistantStopped;

  /// No description provided for @assistantInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Not finished when the app quit'**
  String get assistantInterrupted;

  /// No description provided for @assistantRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get assistantRetry;

  /// No description provided for @assistantUseLocal.
  ///
  /// In en, this message translates to:
  /// **'Use Local Model'**
  String get assistantUseLocal;

  /// No description provided for @assistantOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get assistantOpenSettings;

  /// No description provided for @assistantContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get assistantContinue;

  /// No description provided for @assistantProposalTitle.
  ///
  /// In en, this message translates to:
  /// **'Map changes'**
  String get assistantProposalTitle;

  /// No description provided for @assistantProposalApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get assistantProposalApplied;

  /// No description provided for @assistantProposalDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get assistantProposalDismissed;

  /// No description provided for @assistantDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get assistantDismiss;

  /// No description provided for @assistantApply.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Apply 1 Change} other{Apply {count} Changes}}'**
  String assistantApply(int count);

  /// No description provided for @assistantShowInMap.
  ///
  /// In en, this message translates to:
  /// **'Show in Map'**
  String get assistantShowInMap;

  /// No description provided for @assistantReopen.
  ///
  /// In en, this message translates to:
  /// **'Review Again'**
  String get assistantReopen;

  /// No description provided for @assistantTargetDeleted.
  ///
  /// In en, this message translates to:
  /// **'Target deleted'**
  String get assistantTargetDeleted;

  /// No description provided for @assistantAppliedHud.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Applied 1 change} other{Applied {count} changes}}'**
  String assistantAppliedHud(int count);

  /// No description provided for @assistantPutInMap.
  ///
  /// In en, this message translates to:
  /// **'Put in map under “{title}”'**
  String assistantPutInMap(String title);

  /// No description provided for @assistantAttachToSource.
  ///
  /// In en, this message translates to:
  /// **'Attach beside this sentence on page {page}'**
  String assistantAttachToSource(int page);

  /// No description provided for @assistantNoteDefault.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get assistantNoteDefault;

  /// No description provided for @assistantNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Note title'**
  String get assistantNoteTitle;

  /// No description provided for @assistantBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get assistantBack;

  /// No description provided for @assistantKindWeb.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get assistantKindWeb;

  /// No description provided for @assistantKindPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get assistantKindPaper;

  /// No description provided for @assistantKindVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get assistantKindVideo;

  /// No description provided for @assistantOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get assistantOpenInBrowser;

  /// No description provided for @assistantMapContext.
  ///
  /// In en, this message translates to:
  /// **'Map · {title}'**
  String assistantMapContext(String title);

  /// No description provided for @assistantBranchContext.
  ///
  /// In en, this message translates to:
  /// **'Branch · {title}'**
  String assistantBranchContext(String title);

  /// No description provided for @assistantPageContext.
  ///
  /// In en, this message translates to:
  /// **'p. {page} · {document}'**
  String assistantPageContext(String document, int page);

  /// No description provided for @assistantDocumentContext.
  ///
  /// In en, this message translates to:
  /// **'Whole · {document}'**
  String assistantDocumentContext(String document);

  /// No description provided for @assistantWholeMap.
  ///
  /// In en, this message translates to:
  /// **'Whole map'**
  String get assistantWholeMap;

  /// No description provided for @assistantAutoContext.
  ///
  /// In en, this message translates to:
  /// **'Attached automatically'**
  String get assistantAutoContext;

  /// No description provided for @assistantRemoveContext.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get assistantRemoveContext;

  /// No description provided for @assistantContextCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No references} =1{1 reference} other{{count} references}}'**
  String assistantContextCount(int count);

  /// No description provided for @assistantManageContexts.
  ///
  /// In en, this message translates to:
  /// **'Manage references'**
  String get assistantManageContexts;

  /// No description provided for @assistantSelectionContext.
  ///
  /// In en, this message translates to:
  /// **'Selected text'**
  String get assistantSelectionContext;

  /// No description provided for @assistantMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get assistantMoreActions;

  /// No description provided for @assistantCurrentPage.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String assistantCurrentPage(int page);

  /// No description provided for @assistantSkillExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get assistantSkillExplain;

  /// No description provided for @assistantSkillTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get assistantSkillTranslate;

  /// No description provided for @assistantSkillVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get assistantSkillVerify;

  /// No description provided for @assistantSkillSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get assistantSkillSummarize;

  /// No description provided for @assistantSkillQuiz.
  ///
  /// In en, this message translates to:
  /// **'Make Review Questions'**
  String get assistantSkillQuiz;

  /// No description provided for @assistantSkillQuizShort.
  ///
  /// In en, this message translates to:
  /// **'Quiz'**
  String get assistantSkillQuizShort;

  /// No description provided for @assistantSkillOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize into Map'**
  String get assistantSkillOrganize;

  /// No description provided for @assistantSkillOrganizeShort.
  ///
  /// In en, this message translates to:
  /// **'Organize'**
  String get assistantSkillOrganizeShort;

  /// No description provided for @assistantSkillPapers.
  ///
  /// In en, this message translates to:
  /// **'Find Papers'**
  String get assistantSkillPapers;

  /// No description provided for @assistantSkillVideos.
  ///
  /// In en, this message translates to:
  /// **'Find Videos'**
  String get assistantSkillVideos;

  /// No description provided for @assistantPromptExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain this'**
  String get assistantPromptExplain;

  /// No description provided for @assistantPromptTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate this'**
  String get assistantPromptTranslate;

  /// No description provided for @assistantPromptVerify.
  ///
  /// In en, this message translates to:
  /// **'Check whether this is right'**
  String get assistantPromptVerify;

  /// No description provided for @assistantPromptSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize the key points'**
  String get assistantPromptSummarize;

  /// No description provided for @assistantPromptQuiz.
  ///
  /// In en, this message translates to:
  /// **'Make a few review questions about this'**
  String get assistantPromptQuiz;

  /// No description provided for @assistantPromptOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize this into the map'**
  String get assistantPromptOrganize;

  /// No description provided for @assistantPromptPapers.
  ///
  /// In en, this message translates to:
  /// **'Find related papers'**
  String get assistantPromptPapers;

  /// No description provided for @assistantPromptVideos.
  ///
  /// In en, this message translates to:
  /// **'Find related videos'**
  String get assistantPromptVideos;

  /// No description provided for @assistantSuggestSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize page {page}'**
  String assistantSuggestSummarize(int page);

  /// No description provided for @assistantSuggestExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain “{title}”'**
  String assistantSuggestExplain(String title);

  /// No description provided for @assistantSuggestVerify.
  ///
  /// In en, this message translates to:
  /// **'Check a claim on page {page}'**
  String assistantSuggestVerify(int page);

  /// No description provided for @assistantSuggestTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate the selection'**
  String get assistantSuggestTranslate;

  /// No description provided for @assistantSuggestQuiz.
  ///
  /// In en, this message translates to:
  /// **'Make review questions for “{title}”'**
  String assistantSuggestQuiz(String title);

  /// No description provided for @assistantSuggestOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize this section into the map'**
  String get assistantSuggestOrganize;

  /// No description provided for @assistantSavedKeyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the API key. Enter it again and save.'**
  String get assistantSavedKeyUnavailable;

  /// No description provided for @assistantKeySaveUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The API key could not be saved. Its text remains in this form so you can retry. This does not mean the key is invalid.'**
  String get assistantKeySaveUnavailable;

  /// No description provided for @assistantPasteKey.
  ///
  /// In en, this message translates to:
  /// **'Paste API key'**
  String get assistantPasteKey;

  /// No description provided for @assistantCannotConnect.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the service'**
  String get assistantCannotConnect;

  /// No description provided for @assistantQuestions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 question} other{{count} questions}}'**
  String assistantQuestions(int count);

  /// No description provided for @assistantHasNote.
  ///
  /// In en, this message translates to:
  /// **'has notes'**
  String get assistantHasNote;

  /// No description provided for @assistantRunning.
  ///
  /// In en, this message translates to:
  /// **'Answering'**
  String get assistantRunning;

  /// No description provided for @assistantUnfinished.
  ///
  /// In en, this message translates to:
  /// **'Unfinished'**
  String get assistantUnfinished;

  /// No description provided for @assistantFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get assistantFailed;

  /// No description provided for @assistantDeleteEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get assistantDeleteEllipsis;

  /// No description provided for @assistantDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation?'**
  String get assistantDeleteTitle;

  /// No description provided for @assistantDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Saved notes are kept.'**
  String get assistantDeleteMessage;

  /// No description provided for @assistantRenameConversation.
  ///
  /// In en, this message translates to:
  /// **'Rename Conversation'**
  String get assistantRenameConversation;

  /// No description provided for @assistantExplainTopic.
  ///
  /// In en, this message translates to:
  /// **'Explain This Topic'**
  String get assistantExplainTopic;

  /// No description provided for @assistantExplainCard.
  ///
  /// In en, this message translates to:
  /// **'Explain This Card'**
  String get assistantExplainCard;

  /// No description provided for @assistantOrganizeBranch.
  ///
  /// In en, this message translates to:
  /// **'Organize This Branch…'**
  String get assistantOrganizeBranch;

  /// No description provided for @assistantQuizBranch.
  ///
  /// In en, this message translates to:
  /// **'Make Review Questions for This Branch…'**
  String get assistantQuizBranch;

  /// No description provided for @assistantVerifyCard.
  ///
  /// In en, this message translates to:
  /// **'Verify This Card'**
  String get assistantVerifyCard;

  /// No description provided for @assistantAskWith.
  ///
  /// In en, this message translates to:
  /// **'Ask About It…'**
  String get assistantAskWith;

  /// No description provided for @assistantAnchorGone.
  ///
  /// In en, this message translates to:
  /// **'The original place was deleted'**
  String get assistantAnchorGone;

  /// No description provided for @assistantOpenConversation.
  ///
  /// In en, this message translates to:
  /// **'Open Conversation'**
  String get assistantOpenConversation;

  /// No description provided for @assistantAskMore.
  ///
  /// In en, this message translates to:
  /// **'Ask More'**
  String get assistantAskMore;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get settingsReading;

  /// No description provided for @settingsModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsModels;

  /// No description provided for @settingsWebSearch.
  ///
  /// In en, this message translates to:
  /// **'Web Search'**
  String get settingsWebSearch;

  /// No description provided for @settingsDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default Model'**
  String get settingsDefaultModel;

  /// No description provided for @settingsServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get settingsServices;

  /// No description provided for @settingsServiceModels.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 model on} other{{count} models on}}'**
  String settingsServiceModels(int count);

  /// No description provided for @settingsServiceNoModels.
  ///
  /// In en, this message translates to:
  /// **'No models yet'**
  String get settingsServiceNoModels;

  /// No description provided for @settingsServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsServiceOff;

  /// No description provided for @settingsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsName;

  /// No description provided for @settingsAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get settingsAddress;

  /// No description provided for @settingsShowKey.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get settingsShowKey;

  /// No description provided for @settingsHideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get settingsHideKey;

  /// No description provided for @settingsSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Make Default'**
  String get settingsSetDefault;

  /// No description provided for @settingsIsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsIsDefault;

  /// No description provided for @settingsRemoveModel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsRemoveModel;

  /// No description provided for @settingsAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add Models…'**
  String get settingsAddModel;

  /// No description provided for @settingsCustomAddress.
  ///
  /// In en, this message translates to:
  /// **'Use Custom Address'**
  String get settingsCustomAddress;

  /// No description provided for @settingsRemoveService.
  ///
  /// In en, this message translates to:
  /// **'Remove Service'**
  String get settingsRemoveService;

  /// No description provided for @settingsRemoveServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}”?'**
  String settingsRemoveServiceTitle(String name);

  /// No description provided for @settingsRemoveServiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Its API key is deleted too. Conversations stay.'**
  String get settingsRemoveServiceMessage;

  /// No description provided for @settingsAddService.
  ///
  /// In en, this message translates to:
  /// **'Add Service'**
  String get settingsAddService;

  /// No description provided for @settingsAddModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Models'**
  String get settingsAddModelTitle;

  /// No description provided for @settingsSearchModels.
  ///
  /// In en, this message translates to:
  /// **'Search, or enter a model ID'**
  String get settingsSearchModels;

  /// No description provided for @settingsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get settingsAdded;

  /// No description provided for @settingsAddManual.
  ///
  /// In en, this message translates to:
  /// **'Add “{id}”'**
  String settingsAddManual(String id);

  /// No description provided for @settingsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get settingsAdd;

  /// No description provided for @settingsAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count}'**
  String settingsAddCount(int count);

  /// No description provided for @settingsOpenAiCompatible.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Compatible'**
  String get settingsOpenAiCompatible;

  /// No description provided for @settingsOllamaLocal.
  ///
  /// In en, this message translates to:
  /// **'Ollama (Local)'**
  String get settingsOllamaLocal;

  /// No description provided for @settingsSearchService.
  ///
  /// In en, this message translates to:
  /// **'Search Service'**
  String get settingsSearchService;

  /// No description provided for @settingsSearchUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Not Configured'**
  String get settingsSearchUnconfigured;

  /// No description provided for @settingsAccountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get settingsAccountId;

  /// No description provided for @settingsTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid API token'**
  String get settingsTokenInvalid;

  /// No description provided for @settingsSearchUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the search service'**
  String get settingsSearchUnreachable;

  /// No description provided for @assistantManageModels.
  ///
  /// In en, this message translates to:
  /// **'Manage Models…'**
  String get assistantManageModels;

  /// No description provided for @assistantModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get assistantModel;

  /// No description provided for @assistantThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get assistantThinking;

  /// No description provided for @assistantWorkedFor.
  ///
  /// In en, this message translates to:
  /// **'Worked for {seconds} s'**
  String assistantWorkedFor(int seconds);

  /// No description provided for @assistantToolFailures.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tool call failed} other{{count} tool calls failed}}'**
  String assistantToolFailures(int count);

  /// No description provided for @assistantAnswerWithoutTools.
  ///
  /// In en, this message translates to:
  /// **'Answer Without Tools'**
  String get assistantAnswerWithoutTools;

  /// No description provided for @assistantSwitchModel.
  ///
  /// In en, this message translates to:
  /// **'Switch Model and Retry'**
  String get assistantSwitchModel;

  /// No description provided for @assistantCopyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy Diagnostics'**
  String get assistantCopyDiagnostics;

  /// No description provided for @assistantDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get assistantDetails;

  /// No description provided for @assistantDiagnosticModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get assistantDiagnosticModel;

  /// No description provided for @assistantDiagnosticHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get assistantDiagnosticHost;

  /// No description provided for @assistantDiagnosticStatus.
  ///
  /// In en, this message translates to:
  /// **'HTTP status'**
  String get assistantDiagnosticStatus;

  /// No description provided for @assistantDiagnosticTools.
  ///
  /// In en, this message translates to:
  /// **'Failed tools'**
  String get assistantDiagnosticTools;

  /// No description provided for @assistantDiagnosticReason.
  ///
  /// In en, this message translates to:
  /// **'Stopped because'**
  String get assistantDiagnosticReason;

  /// No description provided for @assistantDiagnosticRequest.
  ///
  /// In en, this message translates to:
  /// **'Request ID'**
  String get assistantDiagnosticRequest;

  /// No description provided for @settingsVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice Input'**
  String get settingsVoice;

  /// No description provided for @voiceService.
  ///
  /// In en, this message translates to:
  /// **'Speech provider'**
  String get voiceService;

  /// No description provided for @voiceDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get voiceDisabled;

  /// No description provided for @voiceDoubao.
  ///
  /// In en, this message translates to:
  /// **'Doubao Realtime ASR 2.0'**
  String get voiceDoubao;

  /// No description provided for @voiceAliyun.
  ///
  /// In en, this message translates to:
  /// **'Alibaba Cloud Realtime ASR'**
  String get voiceAliyun;

  /// No description provided for @voiceAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get voiceAuthentication;

  /// No description provided for @voiceResource.
  ///
  /// In en, this message translates to:
  /// **'Resource type'**
  String get voiceResource;

  /// No description provided for @voiceDuration.
  ///
  /// In en, this message translates to:
  /// **'2.0 Duration'**
  String get voiceDuration;

  /// No description provided for @voiceConcurrent.
  ///
  /// In en, this message translates to:
  /// **'2.0 Concurrent'**
  String get voiceConcurrent;

  /// No description provided for @voicePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Audio is sent to your selected provider. Credentials are stored in this Mac’s Keychain.'**
  String get voicePrivacy;

  /// No description provided for @voiceTest.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get voiceTest;

  /// No description provided for @voiceSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get voiceSave;

  /// No description provided for @voiceTestPassed.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get voiceTestPassed;

  /// No description provided for @voiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get voiceSaved;

  /// No description provided for @voiceSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Check Keychain access.'**
  String get voiceSaveError;

  /// No description provided for @voiceKeyError.
  ///
  /// In en, this message translates to:
  /// **'Could not read credentials. Check Keychain access.'**
  String get voiceKeyError;

  /// No description provided for @voiceConfigurationError.
  ///
  /// In en, this message translates to:
  /// **'Complete your speech service settings and credentials.'**
  String get voiceConfigurationError;

  /// No description provided for @voiceConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check your network, credentials and service activation.'**
  String get voiceConnectionError;

  /// No description provided for @voicePermissionError.
  ///
  /// In en, this message translates to:
  /// **'Microphone access denied. Allow access in System Settings.'**
  String get voicePermissionError;

  /// No description provided for @voiceRecordingError.
  ///
  /// In en, this message translates to:
  /// **'Recording interrupted. Check your microphone and try again.'**
  String get voiceRecordingError;

  /// No description provided for @voiceTimeoutError.
  ///
  /// In en, this message translates to:
  /// **'The speech service timed out. Try again.'**
  String get voiceTimeoutError;

  /// No description provided for @voiceEmptyError.
  ///
  /// In en, this message translates to:
  /// **'No speech detected'**
  String get voiceEmptyError;

  /// No description provided for @voiceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to speech service…'**
  String get voiceConnecting;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get voiceListening;

  /// No description provided for @voiceFinishing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get voiceFinishing;

  /// No description provided for @voiceCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel voice input'**
  String get voiceCancel;

  /// No description provided for @voiceDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss voice notice'**
  String get voiceDismiss;

  /// No description provided for @voiceStart.
  ///
  /// In en, this message translates to:
  /// **'Voice Input'**
  String get voiceStart;

  /// No description provided for @voicePermissionNotice.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is off'**
  String get voicePermissionNotice;

  /// No description provided for @voiceConfigurationNotice.
  ///
  /// In en, this message translates to:
  /// **'Complete voice service settings'**
  String get voiceConfigurationNotice;

  /// No description provided for @voiceConnectionNotice.
  ///
  /// In en, this message translates to:
  /// **'Voice connection interrupted'**
  String get voiceConnectionNotice;

  /// No description provided for @voiceRecordingNotice.
  ///
  /// In en, this message translates to:
  /// **'Microphone recording interrupted'**
  String get voiceRecordingNotice;

  /// No description provided for @voiceTimeoutNotice.
  ///
  /// In en, this message translates to:
  /// **'Voice service timed out'**
  String get voiceTimeoutNotice;

  /// No description provided for @voiceNoticeWithText.
  ///
  /// In en, this message translates to:
  /// **'{message}. Text kept'**
  String voiceNoticeWithText(String message);

  /// No description provided for @voiceFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish Recording'**
  String get voiceFinish;

  /// No description provided for @voiceKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste credential'**
  String get voiceKeyPlaceholder;

  /// No description provided for @mapMultiSelect.
  ///
  /// In en, this message translates to:
  /// **'Multiple Selection'**
  String get mapMultiSelect;

  /// No description provided for @voiceAppIdPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter App ID'**
  String get voiceAppIdPlaceholder;

  /// No description provided for @settingsNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter service name'**
  String get settingsNamePlaceholder;

  /// No description provided for @settingsAccountIdPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter Account ID'**
  String get settingsAccountIdPlaceholder;

  /// No description provided for @settingsApiTokenPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste API Token'**
  String get settingsApiTokenPlaceholder;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Please retry.'**
  String get settingsSaveFailed;

  /// No description provided for @settingsSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get settingsSaving;

  /// No description provided for @settingsUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get settingsUnsaved;

  /// No description provided for @settingsSaveBeforeModels.
  ///
  /// In en, this message translates to:
  /// **'Save the service settings before fetching models'**
  String get settingsSaveBeforeModels;

  /// No description provided for @settingsRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Complete the required fields before saving'**
  String get settingsRequiredFields;

  /// No description provided for @assistantModelSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up the AI assistant'**
  String get assistantModelSetupTitle;

  /// No description provided for @assistantModelUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Model temporarily unavailable'**
  String get assistantModelUnavailableTitle;

  /// No description provided for @assistantConfigureModels.
  ///
  /// In en, this message translates to:
  /// **'Configure Models'**
  String get assistantConfigureModels;

  /// No description provided for @microphonePermission.
  ///
  /// In en, this message translates to:
  /// **'Record audio for transcription.'**
  String get microphonePermission;

  /// No description provided for @localNetworkPermission.
  ///
  /// In en, this message translates to:
  /// **'Connect to your local model service.'**
  String get localNetworkPermission;

  /// No description provided for @assistantOpenModelSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Model Settings →'**
  String get assistantOpenModelSettings;

  /// No description provided for @assistantSetupHint.
  ///
  /// In en, this message translates to:
  /// **'Add a model to get started'**
  String get assistantSetupHint;

  /// No description provided for @assistantKeyNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your API key'**
  String get assistantKeyNeedsAttention;

  /// No description provided for @assistantQuickTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get assistantQuickTitle;

  /// No description provided for @assistantQuickExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain Passage'**
  String get assistantQuickExplain;

  /// No description provided for @assistantQuickSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize Key Points'**
  String get assistantQuickSummarize;

  /// No description provided for @assistantQuickOutline.
  ///
  /// In en, this message translates to:
  /// **'Create an Outline'**
  String get assistantQuickOutline;

  /// No description provided for @assistantQuickOutlinePrompt.
  ///
  /// In en, this message translates to:
  /// **'Create a clear text outline of the selected passage, organizing its main ideas and hierarchy. Show the outline in your answer without modifying the mind map.'**
  String get assistantQuickOutlinePrompt;

  /// No description provided for @assistantQuickAsk.
  ///
  /// In en, this message translates to:
  /// **'Or ask a question…'**
  String get assistantQuickAsk;

  /// No description provided for @assistantQuickFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Ask more about this passage…'**
  String get assistantQuickFollowUp;

  /// No description provided for @assistantQuickSidebar.
  ///
  /// In en, this message translates to:
  /// **'Continue in Sidebar'**
  String get assistantQuickSidebar;

  /// No description provided for @assistantQuickBusy.
  ///
  /// In en, this message translates to:
  /// **'Another conversation is answering. You can ask when it finishes.'**
  String get assistantQuickBusy;

  /// No description provided for @assistantQuickChanged.
  ///
  /// In en, this message translates to:
  /// **'This conversation has changed. Continue viewing it in the sidebar.'**
  String get assistantQuickChanged;

  /// No description provided for @assistantQuickGenerated.
  ///
  /// In en, this message translates to:
  /// **'AI-generated content'**
  String get assistantQuickGenerated;

  /// No description provided for @assistantQuickSelection.
  ///
  /// In en, this message translates to:
  /// **'Selected Text'**
  String get assistantQuickSelection;

  /// No description provided for @cropMargins.
  ///
  /// In en, this message translates to:
  /// **'Crop Margins'**
  String get cropMargins;

  /// No description provided for @uncropMargins.
  ///
  /// In en, this message translates to:
  /// **'Uncrop Margins'**
  String get uncropMargins;

  /// No description provided for @cropAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust Crop'**
  String get cropAdjust;

  /// No description provided for @cropScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All Pages'**
  String get cropScopeAll;

  /// No description provided for @cropScopeOddEven.
  ///
  /// In en, this message translates to:
  /// **'Odd & Even'**
  String get cropScopeOddEven;

  /// No description provided for @cropScopePage.
  ///
  /// In en, this message translates to:
  /// **'This Page'**
  String get cropScopePage;

  /// No description provided for @cropAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get cropAuto;

  /// No description provided for @cropNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get cropNone;

  /// No description provided for @cropOddPages.
  ///
  /// In en, this message translates to:
  /// **'Odd Pages'**
  String get cropOddPages;

  /// No description provided for @cropEvenPages.
  ///
  /// In en, this message translates to:
  /// **'Even Pages'**
  String get cropEvenPages;

  /// No description provided for @cropCustomPage.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get cropCustomPage;

  /// No description provided for @cropHiddenAnnotations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 annotation will be hidden} other{{count} annotations will be hidden}}'**
  String cropHiddenAnnotations(int count);

  /// No description provided for @croppedHud.
  ///
  /// In en, this message translates to:
  /// **'Margins cropped'**
  String get croppedHud;

  /// No description provided for @uncroppedHud.
  ///
  /// In en, this message translates to:
  /// **'Crop removed'**
  String get uncroppedHud;

  /// No description provided for @marginNotes.
  ///
  /// In en, this message translates to:
  /// **'Margin Notes'**
  String get marginNotes;

  /// No description provided for @marginNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get marginNoteAction;

  /// No description provided for @writeMarginNote.
  ///
  /// In en, this message translates to:
  /// **'+ Comment'**
  String get writeMarginNote;

  /// No description provided for @showMarginNotes.
  ///
  /// In en, this message translates to:
  /// **'Show Margin Notes'**
  String get showMarginNotes;

  /// No description provided for @hideMarginNotes.
  ///
  /// In en, this message translates to:
  /// **'Hide Margin Notes'**
  String get hideMarginNotes;

  /// No description provided for @expandMargin.
  ///
  /// In en, this message translates to:
  /// **'Show Margin'**
  String get expandMargin;

  /// No description provided for @cropExpandMargin.
  ///
  /// In en, this message translates to:
  /// **'Crop Margins and Show Notes'**
  String get cropExpandMargin;

  /// No description provided for @marginNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Comment Deleted'**
  String get marginNoteDeleted;

  /// No description provided for @marginNoteAddedToMap.
  ///
  /// In en, this message translates to:
  /// **'Added to Mind Map'**
  String get marginNoteAddedToMap;

  /// No description provided for @compareReading.
  ///
  /// In en, this message translates to:
  /// **'Side by Side'**
  String get compareReading;

  /// No description provided for @compareRecommended.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get compareRecommended;

  /// No description provided for @compareAiTranslate.
  ///
  /// In en, this message translates to:
  /// **'AI Translate into {language}'**
  String compareAiTranslate(String language);

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageCodeZh.
  ///
  /// In en, this message translates to:
  /// **'ZH'**
  String get languageCodeZh;

  /// No description provided for @languageCodeEn.
  ///
  /// In en, this message translates to:
  /// **'EN'**
  String get languageCodeEn;

  /// No description provided for @compareAiOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get compareAiOffline;

  /// No description provided for @compareAiNeedsOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognize text first'**
  String get compareAiNeedsOcr;

  /// No description provided for @compareAiPending.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get compareAiPending;

  /// No description provided for @compareTooNarrow.
  ///
  /// In en, this message translates to:
  /// **'Window too narrow'**
  String get compareTooNarrow;

  /// No description provided for @compareExit.
  ///
  /// In en, this message translates to:
  /// **'Exit Side by Side'**
  String get compareExit;

  /// No description provided for @compareSync.
  ///
  /// In en, this message translates to:
  /// **'Sync Scrolling'**
  String get compareSync;

  /// No description provided for @compareAlign.
  ///
  /// In en, this message translates to:
  /// **'Align Here'**
  String get compareAlign;

  /// No description provided for @compareAlignedHud.
  ///
  /// In en, this message translates to:
  /// **'Aligned'**
  String get compareAlignedHud;

  /// No description provided for @compareSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap Sides'**
  String get compareSwap;

  /// No description provided for @compareMapHiddenHud.
  ///
  /// In en, this message translates to:
  /// **'Map hidden · {shortcut}'**
  String compareMapHiddenHud(String shortcut);

  /// No description provided for @compareTranslationProgress.
  ///
  /// In en, this message translates to:
  /// **'Translating {done}/{total}'**
  String compareTranslationProgress(int done, int total);

  /// No description provided for @compareTranslationSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get compareTranslationSaved;

  /// No description provided for @compareTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed'**
  String get compareTranslationFailed;

  /// No description provided for @compareTranslationPageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No text to translate on this page'**
  String get compareTranslationPageEmpty;

  /// No description provided for @compareTranslationPageSaved.
  ///
  /// In en, this message translates to:
  /// **'Page {page} saved'**
  String compareTranslationPageSaved(int page);

  /// No description provided for @compareTranslationPageProgress.
  ///
  /// In en, this message translates to:
  /// **'Page {page} · Translating {done}/{total}'**
  String compareTranslationPageProgress(int page, int done, int total);

  /// No description provided for @chooseHighlightColor.
  ///
  /// In en, this message translates to:
  /// **'Choose Highlight Color'**
  String get chooseHighlightColor;

  /// No description provided for @moreHighlightColors.
  ///
  /// In en, this message translates to:
  /// **'More Colors'**
  String get moreHighlightColors;

  /// No description provided for @selectionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get selectionTranslate;

  /// No description provided for @selectionTranslationDirection.
  ///
  /// In en, this message translates to:
  /// **'Selection Translation Direction'**
  String get selectionTranslationDirection;

  /// No description provided for @selectionTranslationAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Auto (Chinese ↔ English)'**
  String get selectionTranslationAutomatic;

  /// No description provided for @selectionTranslationEnglishToChinese.
  ///
  /// In en, this message translates to:
  /// **'English → Chinese'**
  String get selectionTranslationEnglishToChinese;

  /// No description provided for @selectionTranslationChineseToEnglish.
  ///
  /// In en, this message translates to:
  /// **'Chinese → English'**
  String get selectionTranslationChineseToEnglish;

  /// No description provided for @selectionTranslationLoading.
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get selectionTranslationLoading;

  /// No description provided for @selectionTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed. Check your model settings or connection and retry.'**
  String get selectionTranslationFailed;

  /// No description provided for @selectionTranslationOffline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Enable online access or select a local model, then retry.'**
  String get selectionTranslationOffline;

  /// No description provided for @selectionTranslationTooLong.
  ///
  /// In en, this message translates to:
  /// **'Select a shorter passage to translate.'**
  String get selectionTranslationTooLong;

  /// No description provided for @selectionTranslationCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy Translation'**
  String get selectionTranslationCopy;

  /// No description provided for @highlightCustomColor.
  ///
  /// In en, this message translates to:
  /// **'Custom Color'**
  String get highlightCustomColor;

  /// No description provided for @highlightColorHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get highlightColorHue;

  /// No description provided for @highlightColorSaturationValue.
  ///
  /// In en, this message translates to:
  /// **'Saturation and Brightness'**
  String get highlightColorSaturationValue;

  /// No description provided for @highlightColorHex.
  ///
  /// In en, this message translates to:
  /// **'Hex Color'**
  String get highlightColorHex;

  /// No description provided for @highlightColorHexInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a six-digit hex color, such as #12A4B8'**
  String get highlightColorHexInvalid;

  /// No description provided for @translationSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source Language'**
  String get translationSourceLanguage;

  /// No description provided for @translationTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target Language'**
  String get translationTargetLanguage;

  /// No description provided for @translationDetectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Detect Language'**
  String get translationDetectLanguage;

  /// No description provided for @translationSwapLanguages.
  ///
  /// In en, this message translates to:
  /// **'Swap Source and Translation'**
  String get translationSwapLanguages;

  /// No description provided for @translationSameLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose different source and target languages.'**
  String get translationSameLanguage;

  /// No description provided for @translationTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get translationTraditionalChinese;

  /// No description provided for @translationJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get translationJapanese;

  /// No description provided for @translationKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get translationKorean;

  /// No description provided for @translationFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get translationFrench;

  /// No description provided for @translationGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get translationGerman;

  /// No description provided for @translationSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get translationSpanish;

  /// No description provided for @translationPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get translationPortuguese;

  /// No description provided for @translationItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get translationItalian;

  /// No description provided for @translationRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get translationRussian;

  /// No description provided for @translationArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get translationArabic;

  /// No description provided for @translationChooseSourceToSwap.
  ///
  /// In en, this message translates to:
  /// **'Select the source language to swap direction'**
  String get translationChooseSourceToSwap;

  /// No description provided for @translationChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get translationChinese;

  /// No description provided for @translationEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get translationEnglish;

  /// No description provided for @editBookmark.
  ///
  /// In en, this message translates to:
  /// **'Edit Bookmark…'**
  String get editBookmark;

  /// No description provided for @addOutlineEntry.
  ///
  /// In en, this message translates to:
  /// **'Add Outline Entry…'**
  String get addOutlineEntry;

  /// No description provided for @addOutlineChild.
  ///
  /// In en, this message translates to:
  /// **'Add Subentry…'**
  String get addOutlineChild;

  /// No description provided for @editOutlineEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit Outline Entry…'**
  String get editOutlineEntry;

  /// No description provided for @deleteOutlineEntry.
  ///
  /// In en, this message translates to:
  /// **'Delete Outline Entry'**
  String get deleteOutlineEntry;

  /// No description provided for @deleteOutlineBranch.
  ///
  /// In en, this message translates to:
  /// **'Delete Entry and Subentries'**
  String get deleteOutlineBranch;

  /// No description provided for @noOutlineEntries.
  ///
  /// In en, this message translates to:
  /// **'No outline entries. Use + to add one.'**
  String get noOutlineEntries;

  /// No description provided for @outlineNoDestination.
  ///
  /// In en, this message translates to:
  /// **'Use page 0 for a section without a destination.'**
  String get outlineNoDestination;

  /// No description provided for @readerEntryActions.
  ///
  /// In en, this message translates to:
  /// **'Entry Actions'**
  String get readerEntryActions;

  /// No description provided for @readerDragToMove.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get readerDragToMove;

  /// No description provided for @readerSortPageAscending.
  ///
  /// In en, this message translates to:
  /// **'Page Number: Ascending'**
  String get readerSortPageAscending;

  /// No description provided for @readerSortPageDescending.
  ///
  /// In en, this message translates to:
  /// **'Page Number: Descending'**
  String get readerSortPageDescending;

  /// No description provided for @readerSortTitle.
  ///
  /// In en, this message translates to:
  /// **'By Name'**
  String get readerSortTitle;

  /// No description provided for @bookmarkPageOccupied.
  ///
  /// In en, this message translates to:
  /// **'This page already has a bookmark.'**
  String get bookmarkPageOccupied;

  /// No description provided for @readerInvalidPage.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid page number up to {count}.'**
  String readerInvalidPage(int count);

  /// No description provided for @outlineDragHint.
  ///
  /// In en, this message translates to:
  /// **'Drag above or below an entry to reorder; drag to its center to nest.'**
  String get outlineDragHint;

  /// No description provided for @toolUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get toolUnderline;

  /// No description provided for @lineSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get lineSolid;

  /// No description provided for @lineDashed.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get lineDashed;

  /// No description provided for @lineDotted.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get lineDotted;

  /// No description provided for @lineWavy.
  ///
  /// In en, this message translates to:
  /// **'Wavy'**
  String get lineWavy;

  /// No description provided for @underlinedHud.
  ///
  /// In en, this message translates to:
  /// **'Underlined'**
  String get underlinedHud;

  /// No description provided for @deleteUnderline.
  ///
  /// In en, this message translates to:
  /// **'Delete Underline'**
  String get deleteUnderline;

  /// No description provided for @underlineDeletedHud.
  ///
  /// In en, this message translates to:
  /// **'Underline Deleted'**
  String get underlineDeletedHud;

  /// No description provided for @mergeNodes.
  ///
  /// In en, this message translates to:
  /// **'Merge {count} nodes'**
  String mergeNodes(int count);

  /// No description provided for @splitNodes.
  ///
  /// In en, this message translates to:
  /// **'Split into {count} nodes'**
  String splitNodes(int count);

  /// No description provided for @selectedNodes.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedNodes(int count);

  /// No description provided for @mergedNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes merged'**
  String get mergedNodes;

  /// No description provided for @mergeCleanup.
  ///
  /// In en, this message translates to:
  /// **'Removed {relations} relationships and {summaries} summaries'**
  String mergeCleanup(int relations, int summaries);

  /// No description provided for @mergedSources.
  ///
  /// In en, this message translates to:
  /// **'{count} sources · Merged'**
  String mergedSources(int count);

  /// No description provided for @relationNeedsTwo.
  ///
  /// In en, this message translates to:
  /// **'Select exactly two nodes'**
  String get relationNeedsTwo;

  /// No description provided for @mapEditTooFewCards.
  ///
  /// In en, this message translates to:
  /// **'Select at least two nodes'**
  String get mapEditTooFewCards;

  /// No description provided for @mapEditMissingCard.
  ///
  /// In en, this message translates to:
  /// **'A selected node is unavailable'**
  String get mapEditMissingCard;

  /// No description provided for @mapEditCenterTopic.
  ///
  /// In en, this message translates to:
  /// **'The central topic cannot be used'**
  String get mapEditCenterTopic;

  /// No description provided for @mapEditImageCard.
  ///
  /// In en, this message translates to:
  /// **'Image cards cannot be merged'**
  String get mapEditImageCard;

  /// No description provided for @mapEditSummaryTopic.
  ///
  /// In en, this message translates to:
  /// **'Summary topics cannot be used'**
  String get mapEditSummaryTopic;

  /// No description provided for @mapEditUnsupportedCard.
  ///
  /// In en, this message translates to:
  /// **'This card type cannot be merged'**
  String get mapEditUnsupportedCard;

  /// No description provided for @mapEditNotMerged.
  ///
  /// In en, this message translates to:
  /// **'This card has no segments to split'**
  String get mapEditNotMerged;

  /// No description provided for @mapEditDifferentParents.
  ///
  /// In en, this message translates to:
  /// **'Select nodes with the same parent'**
  String get mapEditDifferentParents;

  /// No description provided for @mapEditOverlappingSummary.
  ///
  /// In en, this message translates to:
  /// **'This range overlaps an existing summary'**
  String get mapEditOverlappingSummary;

  /// No description provided for @mapEditMissingSummary.
  ///
  /// In en, this message translates to:
  /// **'This summary is unavailable'**
  String get mapEditMissingSummary;

  /// No description provided for @nodeBarChild.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get nodeBarChild;

  /// No description provided for @nodeBarSibling.
  ///
  /// In en, this message translates to:
  /// **'Sibling'**
  String get nodeBarSibling;

  /// No description provided for @nodeBarNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get nodeBarNote;

  /// No description provided for @nodeBarImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get nodeBarImage;

  /// No description provided for @nodeBarAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get nodeBarAssistant;

  /// No description provided for @selectionMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get selectionMerge;

  /// No description provided for @selectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get selectionSummary;

  /// No description provided for @selectionRelation.
  ///
  /// In en, this message translates to:
  /// **'Relate'**
  String get selectionRelation;

  /// No description provided for @selectionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get selectionDelete;

  /// No description provided for @relationArrowEnd.
  ///
  /// In en, this message translates to:
  /// **'One-way arrow'**
  String get relationArrowEnd;

  /// No description provided for @relationArrowBoth.
  ///
  /// In en, this message translates to:
  /// **'Two-way arrows'**
  String get relationArrowBoth;

  /// No description provided for @relationArrowNone.
  ///
  /// In en, this message translates to:
  /// **'No arrows'**
  String get relationArrowNone;

  /// No description provided for @relationReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse direction'**
  String get relationReverse;

  /// No description provided for @relationLineStyle.
  ///
  /// In en, this message translates to:
  /// **'Solid / dashed'**
  String get relationLineStyle;

  /// No description provided for @summaryIncludedNodes.
  ///
  /// In en, this message translates to:
  /// **'Includes {count} unselected nodes in between'**
  String summaryIncludedNodes(int count);

  /// No description provided for @addWebPage.
  ///
  /// In en, this message translates to:
  /// **'Add Web Page…'**
  String get addWebPage;

  /// No description provided for @webUrlPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get webUrlPlaceholder;

  /// No description provided for @webUrlEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL'**
  String get webUrlEmpty;

  /// No description provided for @webUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid URL'**
  String get webUrlInvalid;

  /// No description provided for @webUrlScheme.
  ///
  /// In en, this message translates to:
  /// **'Only http and https are supported'**
  String get webUrlScheme;

  /// No description provided for @browserBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get browserBack;

  /// No description provided for @browserForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get browserForward;

  /// No description provided for @browserReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get browserReload;

  /// No description provided for @browserStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get browserStop;

  /// No description provided for @browserClose.
  ///
  /// In en, this message translates to:
  /// **'Close Page'**
  String get browserClose;

  /// No description provided for @browserConvert.
  ///
  /// In en, this message translates to:
  /// **'Convert to Document…'**
  String get browserConvert;

  /// No description provided for @browserConvertShort.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get browserConvertShort;

  /// No description provided for @webReadyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Convert to a document?'**
  String get webReadyPrompt;

  /// No description provided for @webStillLoading.
  ///
  /// In en, this message translates to:
  /// **'Some content is still loading'**
  String get webStillLoading;

  /// No description provided for @webLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get webLater;

  /// No description provided for @webErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Can’t Open Page'**
  String get webErrorTitle;

  /// No description provided for @webRetry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get webRetry;

  /// No description provided for @settingsClearWebsiteData.
  ///
  /// In en, this message translates to:
  /// **'Clear…'**
  String get settingsClearWebsiteData;

  /// No description provided for @clearWebsiteDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all website data?'**
  String get clearWebsiteDataConfirm;

  /// No description provided for @websiteDataCleared.
  ///
  /// In en, this message translates to:
  /// **'Website data cleared'**
  String get websiteDataCleared;

  /// No description provided for @addWebTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Web Page'**
  String get addWebTitle;

  /// No description provided for @webKeepWaiting.
  ///
  /// In en, this message translates to:
  /// **'Keep Waiting'**
  String get webKeepWaiting;

  /// No description provided for @webConvertAction.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get webConvertAction;

  /// No description provided for @webErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The connection timed out'**
  String get webErrorTimeout;

  /// No description provided for @webErrorHost.
  ///
  /// In en, this message translates to:
  /// **'Server not found'**
  String get webErrorHost;

  /// No description provided for @webErrorCertificate.
  ///
  /// In en, this message translates to:
  /// **'Invalid certificate'**
  String get webErrorCertificate;

  /// No description provided for @webErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'You’re offline'**
  String get webErrorOffline;

  /// No description provided for @settingsBrowserGroup.
  ///
  /// In en, this message translates to:
  /// **'In-App Browser'**
  String get settingsBrowserGroup;

  /// No description provided for @settingsWebsiteData.
  ///
  /// In en, this message translates to:
  /// **'Website Data'**
  String get settingsWebsiteData;

  /// No description provided for @clearAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearAction;

  /// No description provided for @browserUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Not Saved'**
  String get browserUnsaved;

  /// No description provided for @addDocumentMenu.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addDocumentMenu;

  /// No description provided for @documentFiles.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentFiles;

  /// No description provided for @unsupportedFile.
  ///
  /// In en, this message translates to:
  /// **'“{name}” isn’t supported'**
  String unsupportedFile(String name);

  /// No description provided for @readingSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading Settings'**
  String get readingSettings;

  /// No description provided for @cancelImport.
  ///
  /// In en, this message translates to:
  /// **'Cancel Import'**
  String get cancelImport;

  /// No description provided for @okAction.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okAction;

  /// No description provided for @importFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t Import “{name}”'**
  String importFailedTitle(String name);

  /// No description provided for @importFailedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document couldn’t be imported} other{{count} documents couldn’t be imported}}'**
  String importFailedMany(int count);

  /// No description provided for @importErrorDrm.
  ///
  /// In en, this message translates to:
  /// **'Protected by DRM'**
  String get importErrorDrm;

  /// No description provided for @importErrorDamaged.
  ///
  /// In en, this message translates to:
  /// **'The file is damaged'**
  String get importErrorDamaged;

  /// No description provided for @importErrorKfx.
  ///
  /// In en, this message translates to:
  /// **'KFX isn’t supported'**
  String get importErrorKfx;

  /// No description provided for @importErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'No readable content'**
  String get importErrorEmpty;

  /// No description provided for @importErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported format'**
  String get importErrorUnsupported;

  /// No description provided for @importErrorLimit.
  ///
  /// In en, this message translates to:
  /// **'The file size or expanded content exceeds the import limit'**
  String get importErrorLimit;

  /// No description provided for @readerFontSmaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller Text'**
  String get readerFontSmaller;

  /// No description provided for @readerFontLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger Text'**
  String get readerFontLarger;

  /// No description provided for @readerLineTight.
  ///
  /// In en, this message translates to:
  /// **'Tight'**
  String get readerLineTight;

  /// No description provided for @readerLineNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get readerLineNormal;

  /// No description provided for @readerLineLoose.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get readerLineLoose;

  /// No description provided for @readerFontOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get readerFontOriginal;

  /// No description provided for @readerFontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get readerFontSerif;

  /// No description provided for @readerFontSans.
  ///
  /// In en, this message translates to:
  /// **'Sans'**
  String get readerFontSans;

  /// No description provided for @readerModePaged.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get readerModePaged;

  /// No description provided for @readerModeScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get readerModeScroll;

  /// No description provided for @readerPositionMissing.
  ///
  /// In en, this message translates to:
  /// **'Source position not found'**
  String get readerPositionMissing;

  /// No description provided for @readerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open document'**
  String get readerLoadFailed;

  /// No description provided for @readerNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Needs Review'**
  String get readerNeedsReview;

  /// No description provided for @readerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get readerRetry;

  /// No description provided for @readerNoOutline.
  ///
  /// In en, this message translates to:
  /// **'No outline'**
  String get readerNoOutline;

  /// No description provided for @readerSelectionStart.
  ///
  /// In en, this message translates to:
  /// **'Selection start'**
  String get readerSelectionStart;

  /// No description provided for @readerSelectionEnd.
  ///
  /// In en, this message translates to:
  /// **'Selection end'**
  String get readerSelectionEnd;

  /// No description provided for @convertTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert to Document'**
  String get convertTitle;

  /// No description provided for @convertTitlePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get convertTitlePlaceholder;

  /// No description provided for @convertReadable.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get convertReadable;

  /// No description provided for @convertPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get convertPdf;

  /// No description provided for @convertMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get convertMarkdown;

  /// No description provided for @docSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get docSaving;

  /// No description provided for @docSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved “{title}”'**
  String docSaved(String title);

  /// No description provided for @docSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t Save'**
  String get docSaveFailed;

  /// No description provided for @docUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get docUpdated;

  /// No description provided for @annotationsNeedReview.
  ///
  /// In en, this message translates to:
  /// **'Needs Review ({count})'**
  String annotationsNeedReview(int count);

  /// No description provided for @annotationsNeedReviewHud.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 highlight needs review} other{{count} highlights need review}}'**
  String annotationsNeedReviewHud(int count);

  /// No description provided for @viewAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewAction;

  /// No description provided for @openOriginalPage.
  ///
  /// In en, this message translates to:
  /// **'Open Original Page'**
  String get openOriginalPage;

  /// No description provided for @refetchPage.
  ///
  /// In en, this message translates to:
  /// **'Refetch Page'**
  String get refetchPage;

  /// No description provided for @browserUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update Document'**
  String get browserUpdate;

  /// No description provided for @webUpdatePrompt.
  ///
  /// In en, this message translates to:
  /// **'Update the document?'**
  String get webUpdatePrompt;

  /// No description provided for @webUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get webUpdateAction;

  /// No description provided for @webSource.
  ///
  /// In en, this message translates to:
  /// **'{domain} · {date}'**
  String webSource(String domain, DateTime date);

  /// No description provided for @annotationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Can’t find the original text'**
  String get annotationNotFound;

  /// No description provided for @vocabularyTitle.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get vocabularyTitle;

  /// No description provided for @vocabularyLookup.
  ///
  /// In en, this message translates to:
  /// **'Look up (T)'**
  String get vocabularyLookup;

  /// No description provided for @vocabularyTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate (T)'**
  String get vocabularyTranslate;

  /// No description provided for @vocabularyAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to vocabulary'**
  String get vocabularyAdd;

  /// No description provided for @vocabularyAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to vocabulary'**
  String get vocabularyAdded;

  /// No description provided for @vocabularyLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get vocabularyLearning;

  /// No description provided for @vocabularyKnown.
  ///
  /// In en, this message translates to:
  /// **'Known'**
  String get vocabularyKnown;

  /// No description provided for @vocabularyView.
  ///
  /// In en, this message translates to:
  /// **'View in vocabulary'**
  String get vocabularyView;

  /// No description provided for @vocabularyMarkKnown.
  ///
  /// In en, this message translates to:
  /// **'Mark as known'**
  String get vocabularyMarkKnown;

  /// No description provided for @vocabularyRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from vocabulary'**
  String get vocabularyRemove;

  /// No description provided for @vocabularyExample.
  ///
  /// In en, this message translates to:
  /// **'Save as example'**
  String get vocabularyExample;

  /// No description provided for @vocabularySentence.
  ///
  /// In en, this message translates to:
  /// **'Translate sentence'**
  String get vocabularySentence;

  /// No description provided for @vocabularyDetails.
  ///
  /// In en, this message translates to:
  /// **'Details ›'**
  String get vocabularyDetails;

  /// No description provided for @vocabularyLongSelection.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary accepts words and phrases of up to 8 words'**
  String get vocabularyLongSelection;

  /// No description provided for @vocabularySettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get vocabularySettings;

  /// No description provided for @vocabularySpeak.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get vocabularySpeak;

  /// No description provided for @vocabularySetup.
  ///
  /// In en, this message translates to:
  /// **'No model configured'**
  String get vocabularySetup;

  /// No description provided for @vocabularyOffline.
  ///
  /// In en, this message translates to:
  /// **'Online access is off'**
  String get vocabularyOffline;

  /// No description provided for @vocabularyUK.
  ///
  /// In en, this message translates to:
  /// **'UK'**
  String get vocabularyUK;

  /// No description provided for @vocabularyUS.
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get vocabularyUS;

  /// No description provided for @vocabularySearch.
  ///
  /// In en, this message translates to:
  /// **'Search words and meanings'**
  String get vocabularySearch;

  /// No description provided for @vocabularyThisSet.
  ///
  /// In en, this message translates to:
  /// **'This study set'**
  String get vocabularyThisSet;

  /// No description provided for @vocabularyAllSets.
  ///
  /// In en, this message translates to:
  /// **'All study sets'**
  String get vocabularyAllSets;

  /// No description provided for @vocabularyScope.
  ///
  /// In en, this message translates to:
  /// **'Study set scope'**
  String get vocabularyScope;

  /// No description provided for @vocabularyAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get vocabularyAll;

  /// No description provided for @vocabularyToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get vocabularyToday;

  /// No description provided for @vocabularyEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get vocabularyEarlier;

  /// No description provided for @vocabularyNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching words'**
  String get vocabularyNoMatch;

  /// No description provided for @vocabularyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No words yet'**
  String get vocabularyEmpty;

  /// No description provided for @vocabularyOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Occurrences in this document'**
  String get vocabularyOccurrences;

  /// No description provided for @vocabularySenses.
  ///
  /// In en, this message translates to:
  /// **'Meanings'**
  String get vocabularySenses;

  /// No description provided for @vocabularyRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get vocabularyRegenerate;

  /// No description provided for @vocabularyModelRequired.
  ///
  /// In en, this message translates to:
  /// **'No model configured'**
  String get vocabularyModelRequired;

  /// No description provided for @vocabularyGloss.
  ///
  /// In en, this message translates to:
  /// **'Inline meaning'**
  String get vocabularyGloss;

  /// No description provided for @vocabularyNote.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get vocabularyNote;

  /// No description provided for @vocabularyForms.
  ///
  /// In en, this message translates to:
  /// **'Word forms'**
  String get vocabularyForms;

  /// No description provided for @vocabularyForgetForm.
  ///
  /// In en, this message translates to:
  /// **'Stop recognizing'**
  String get vocabularyForgetForm;

  /// No description provided for @vocabularyExamples.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get vocabularyExamples;

  /// No description provided for @vocabularyNoExamples.
  ///
  /// In en, this message translates to:
  /// **'No examples.'**
  String get vocabularyNoExamples;

  /// No description provided for @vocabularyReturn.
  ///
  /// In en, this message translates to:
  /// **'Back to source'**
  String get vocabularyReturn;

  /// No description provided for @vocabularyOpenSet.
  ///
  /// In en, this message translates to:
  /// **'Open study set ›'**
  String get vocabularyOpenSet;

  /// No description provided for @vocabularyDeleteExample.
  ///
  /// In en, this message translates to:
  /// **'Delete example'**
  String get vocabularyDeleteExample;

  /// No description provided for @vocabularyLearnAgain.
  ///
  /// In en, this message translates to:
  /// **'Learn again'**
  String get vocabularyLearnAgain;

  /// No description provided for @vocabularyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete from vocabulary'**
  String get vocabularyDelete;

  /// No description provided for @vocabularyRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get vocabularyRemoved;

  /// No description provided for @vocabularyExampleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Example deleted'**
  String get vocabularyExampleDeleted;

  /// No description provided for @vocabularyRead.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get vocabularyRead;

  /// No description provided for @vocabularyUk.
  ///
  /// In en, this message translates to:
  /// **'UK'**
  String get vocabularyUk;

  /// No description provided for @vocabularyUs.
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get vocabularyUs;

  /// No description provided for @vocabularyAddForm.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get vocabularyAddForm;

  /// No description provided for @vocabularyHints.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary hints'**
  String get vocabularyHints;

  /// No description provided for @vocabularyHintsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get vocabularyHintsOff;

  /// No description provided for @vocabularyHintsUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get vocabularyHintsUnderline;

  /// No description provided for @vocabularyHintsGloss.
  ///
  /// In en, this message translates to:
  /// **'Meaning'**
  String get vocabularyHintsGloss;

  /// No description provided for @vocabularyHintsHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide in this document'**
  String get vocabularyHintsHidden;

  /// No description provided for @vocabularyHintsKnown.
  ///
  /// In en, this message translates to:
  /// **'Mark known words'**
  String get vocabularyHintsKnown;

  /// No description provided for @mapIdeaMenu.
  ///
  /// In en, this message translates to:
  /// **'Expand Ideas with AI'**
  String get mapIdeaMenu;

  /// No description provided for @mapIdeaExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand Ideas'**
  String get mapIdeaExpand;

  /// No description provided for @mapIdeaExpandEach.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Expand 1 Topic} other{Expand {count} Topics}}'**
  String mapIdeaExpandEach(int count);

  /// No description provided for @mapIdeaExpandMap.
  ///
  /// In en, this message translates to:
  /// **'Expand Whole Map…'**
  String get mapIdeaExpandMap;

  /// No description provided for @mapIdeaWholeMap.
  ///
  /// In en, this message translates to:
  /// **'Expand Whole Map'**
  String get mapIdeaWholeMap;

  /// No description provided for @mapIdeaBranchesOnly.
  ///
  /// In en, this message translates to:
  /// **'New Branches Only'**
  String get mapIdeaBranchesOnly;

  /// No description provided for @mapIdeaGroup.
  ///
  /// In en, this message translates to:
  /// **'Group Under New Parent'**
  String get mapIdeaGroup;

  /// No description provided for @mapIdeaFillSiblings.
  ///
  /// In en, this message translates to:
  /// **'Fill In Siblings'**
  String get mapIdeaFillSiblings;

  /// No description provided for @mapIdeaDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get mapIdeaDirection;

  /// No description provided for @mapIdeaDirectionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get mapIdeaDirectionAuto;

  /// No description provided for @mapIdeaDirectionWhy.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get mapIdeaDirectionWhy;

  /// No description provided for @mapIdeaDirectionExample.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get mapIdeaDirectionExample;

  /// No description provided for @mapIdeaDirectionCounter.
  ///
  /// In en, this message translates to:
  /// **'Counterpoints'**
  String get mapIdeaDirectionCounter;

  /// No description provided for @mapIdeaDirectionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get mapIdeaDirectionQuestion;

  /// No description provided for @mapIdeaDirectionAction.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get mapIdeaDirectionAction;

  /// No description provided for @mapIdeaDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get mapIdeaDepth;

  /// No description provided for @mapIdeaDepthLevels.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Level} other{{count} Levels}}'**
  String mapIdeaDepthLevels(int count);

  /// No description provided for @mapIdeaAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get mapIdeaAmount;

  /// No description provided for @mapIdeaAmountFew.
  ///
  /// In en, this message translates to:
  /// **'Few'**
  String get mapIdeaAmountFew;

  /// No description provided for @mapIdeaAmountSome.
  ///
  /// In en, this message translates to:
  /// **'Some'**
  String get mapIdeaAmountSome;

  /// No description provided for @mapIdeaAmountMany.
  ///
  /// In en, this message translates to:
  /// **'Many'**
  String get mapIdeaAmountMany;

  /// No description provided for @mapIdeaHint.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get mapIdeaHint;

  /// No description provided for @mapIdeaGrounded.
  ///
  /// In en, this message translates to:
  /// **'Use Source'**
  String get mapIdeaGrounded;

  /// No description provided for @mapIdeaExpanding.
  ///
  /// In en, this message translates to:
  /// **'Expanding “{title}”'**
  String mapIdeaExpanding(String title);

  /// No description provided for @mapIdeaExpandingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Expanding 1 Topic} other{Expanding {count} Topics}}'**
  String mapIdeaExpandingCount(int count);

  /// No description provided for @mapIdeaIncompleteDepth.
  ///
  /// In en, this message translates to:
  /// **'Some branches are missing levels. Try again.'**
  String get mapIdeaIncompleteDepth;

  /// No description provided for @mapIdeaStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get mapIdeaStopped;

  /// No description provided for @mapIdeaDraftCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 idea} other{{count} ideas}}'**
  String mapIdeaDraftCount(int count);

  /// No description provided for @mapIdeaKeptCount.
  ///
  /// In en, this message translates to:
  /// **'{kept} of {total} kept'**
  String mapIdeaKeptCount(int kept, int total);

  /// No description provided for @mapIdeaRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Try Others'**
  String get mapIdeaRegenerate;

  /// No description provided for @mapIdeaAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get mapIdeaAdjust;

  /// No description provided for @mapIdeaRegenerateAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get mapIdeaRegenerateAdjusted;

  /// No description provided for @mapIdeaDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get mapIdeaDiscard;

  /// No description provided for @mapIdeaKeep.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Keep 1} other{Keep {count}}}'**
  String mapIdeaKeep(int count);

  /// No description provided for @mapIdeaDraftKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get mapIdeaDraftKeep;

  /// No description provided for @mapIdeaDraftSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get mapIdeaDraftSkip;

  /// No description provided for @mapIdeaDraftEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get mapIdeaDraftEdit;

  /// No description provided for @mapIdeaDraftMore.
  ///
  /// In en, this message translates to:
  /// **'Expand Further'**
  String get mapIdeaDraftMore;

  /// No description provided for @mapIdeaDraftSemantics.
  ///
  /// In en, this message translates to:
  /// **'AI draft, {title}, {state}'**
  String mapIdeaDraftSemantics(String title, String state);

  /// No description provided for @mapIdeaDraftKept.
  ///
  /// In en, this message translates to:
  /// **'kept'**
  String get mapIdeaDraftKept;

  /// No description provided for @mapIdeaDraftSkipped.
  ///
  /// In en, this message translates to:
  /// **'not kept'**
  String get mapIdeaDraftSkipped;

  /// No description provided for @mapIdeaNewBranches.
  ///
  /// In en, this message translates to:
  /// **'New Branches'**
  String get mapIdeaNewBranches;

  /// No description provided for @mapIdeaAddCount.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String mapIdeaAddCount(int count);

  /// No description provided for @mapIdeaFewer.
  ///
  /// In en, this message translates to:
  /// **'Fewer'**
  String get mapIdeaFewer;

  /// No description provided for @mapIdeaMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get mapIdeaMore;

  /// No description provided for @mapIdeaGenerate.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get mapIdeaGenerate;

  /// No description provided for @mapIdeaStart.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get mapIdeaStart;

  /// No description provided for @mapIdeaAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 topic} other{Added {count} topics}}'**
  String mapIdeaAdded(int count);

  /// No description provided for @mapIdeaBlocked.
  ///
  /// In en, this message translates to:
  /// **'Keep or discard the suggested topics before continuing'**
  String get mapIdeaBlocked;

  /// No description provided for @mapIdeaNothing.
  ///
  /// In en, this message translates to:
  /// **'No new ideas here. Try another direction.'**
  String get mapIdeaNothing;

  /// No description provided for @mapIdeaStoppedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Stopped before any ideas'**
  String get mapIdeaStoppedEmpty;

  /// No description provided for @mapIdeaBusy.
  ///
  /// In en, this message translates to:
  /// **'The model is busy. Try again later.'**
  String get mapIdeaBusy;

  /// No description provided for @mapGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate Map'**
  String get mapGenerate;

  /// No description provided for @mapGenerateMenu.
  ///
  /// In en, this message translates to:
  /// **'Generate from Document…'**
  String get mapGenerateMenu;

  /// No description provided for @mapGenerateDocumentMenu.
  ///
  /// In en, this message translates to:
  /// **'Generate Map…'**
  String get mapGenerateDocumentMenu;

  /// No description provided for @mapGenerateUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update Map'**
  String get mapGenerateUpdate;

  /// No description provided for @mapGenerateRunning.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get mapGenerateRunning;

  /// No description provided for @mapGenerateReviewing.
  ///
  /// In en, this message translates to:
  /// **'Reviewing'**
  String get mapGenerateReviewing;

  /// No description provided for @mapHasUpdates.
  ///
  /// In en, this message translates to:
  /// **'New material'**
  String get mapHasUpdates;

  /// No description provided for @mapHasMap.
  ///
  /// In en, this message translates to:
  /// **'Has a map'**
  String get mapHasMap;

  /// No description provided for @mapEmptyGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn your source into a mind map'**
  String get mapEmptyGenerateTitle;

  /// No description provided for @mapEmptyGenerateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture key ideas, organize the structure, and keep the original context.'**
  String get mapEmptyGenerateSubtitle;

  /// No description provided for @mapEmptySourceStart.
  ///
  /// In en, this message translates to:
  /// **'Start with this source'**
  String get mapEmptySourceStart;

  /// No description provided for @mapEmptyInstructionsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'For example: organize by events, impact, and responses'**
  String get mapEmptyInstructionsPlaceholder;

  /// No description provided for @mapGenerateFrom.
  ///
  /// In en, this message translates to:
  /// **'Generate a Map from “{document}”'**
  String mapGenerateFrom(String document);

  /// No description provided for @mapGenerateSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get mapGenerateSettings;

  /// No description provided for @mapGenerateStart.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get mapGenerateStart;

  /// No description provided for @mapGenerateBlank.
  ///
  /// In en, this message translates to:
  /// **'Start Blank'**
  String get mapGenerateBlank;

  /// No description provided for @mapGenerateSuggestExam.
  ///
  /// In en, this message translates to:
  /// **'Focus on Exam Points'**
  String get mapGenerateSuggestExam;

  /// No description provided for @mapGenerateSuggestExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain Each Topic'**
  String get mapGenerateSuggestExplain;

  /// No description provided for @mapGenerateSuggestQuotes.
  ///
  /// In en, this message translates to:
  /// **'Keep Key Quotes'**
  String get mapGenerateSuggestQuotes;

  /// No description provided for @mapGenerateSuggestExamples.
  ///
  /// In en, this message translates to:
  /// **'Add Examples'**
  String get mapGenerateSuggestExamples;

  /// No description provided for @mapGenerateDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get mapGenerateDocuments;

  /// No description provided for @mapGeneratePages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String mapGeneratePages(int count);

  /// No description provided for @mapGenerateSegments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 part} other{{count} parts}}'**
  String mapGenerateSegments(int count);

  /// No description provided for @mapGenerateNeedsOcr.
  ///
  /// In en, this message translates to:
  /// **'Needs text recognition'**
  String get mapGenerateNeedsOcr;

  /// No description provided for @mapGenerateWholeDocument.
  ///
  /// In en, this message translates to:
  /// **'Entire Document'**
  String get mapGenerateWholeDocument;

  /// No description provided for @mapGenerateChapterCount.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} chapters'**
  String mapGenerateChapterCount(int selected, int total);

  /// No description provided for @mapGenerateOrganization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get mapGenerateOrganization;

  /// No description provided for @mapGenerateByChapter.
  ///
  /// In en, this message translates to:
  /// **'By Chapter'**
  String get mapGenerateByChapter;

  /// No description provided for @mapGenerateByTopic.
  ///
  /// In en, this message translates to:
  /// **'By Concept'**
  String get mapGenerateByTopic;

  /// No description provided for @mapGenerateMergeByTopic.
  ///
  /// In en, this message translates to:
  /// **'Merge by Concept'**
  String get mapGenerateMergeByTopic;

  /// No description provided for @mapGenerateByQuestion.
  ///
  /// In en, this message translates to:
  /// **'By Question'**
  String get mapGenerateByQuestion;

  /// No description provided for @mapGenerateDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get mapGenerateDetail;

  /// No description provided for @mapGenerateDetailBrief.
  ///
  /// In en, this message translates to:
  /// **'Brief'**
  String get mapGenerateDetailBrief;

  /// No description provided for @mapGenerateDetailMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get mapGenerateDetailMedium;

  /// No description provided for @mapGenerateDetailFull.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get mapGenerateDetailFull;

  /// No description provided for @mapGenerateEstimate.
  ///
  /// In en, this message translates to:
  /// **'{levels} levels · about {count} topics'**
  String mapGenerateEstimate(int levels, int count);

  /// No description provided for @mapGenerateContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get mapGenerateContent;

  /// No description provided for @mapGenerateMyMarks.
  ///
  /// In en, this message translates to:
  /// **'My Highlights and Notes'**
  String get mapGenerateMyMarks;

  /// No description provided for @mapGenerateMarkCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String mapGenerateMarkCount(int count);

  /// No description provided for @mapGenerateQuotes.
  ///
  /// In en, this message translates to:
  /// **'Key Quotes'**
  String get mapGenerateQuotes;

  /// No description provided for @mapGenerateTarget.
  ///
  /// In en, this message translates to:
  /// **'Generate To'**
  String get mapGenerateTarget;

  /// No description provided for @mapGenerateTargetNew.
  ///
  /// In en, this message translates to:
  /// **'New Map'**
  String get mapGenerateTargetNew;

  /// No description provided for @mapGenerateTargetBranch.
  ///
  /// In en, this message translates to:
  /// **'New Branch of This Map'**
  String get mapGenerateTargetBranch;

  /// No description provided for @mapGenerateTargetReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace “{title}”'**
  String mapGenerateTargetReplace(String title);

  /// No description provided for @mapGenerateInstructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get mapGenerateInstructions;

  /// No description provided for @mapGenerateReading.
  ///
  /// In en, this message translates to:
  /// **'Reading “{document}”'**
  String mapGenerateReading(String document);

  /// No description provided for @mapGenerateBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building Map'**
  String get mapGenerateBuilding;

  /// No description provided for @mapGenerateTopicCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 topic} other{{count} topics}}'**
  String mapGenerateTopicCount(int count);

  /// No description provided for @mapGenerateQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get mapGenerateQueued;

  /// No description provided for @mapGenerateChapterFailed.
  ///
  /// In en, this message translates to:
  /// **'“{chapter}” failed'**
  String mapGenerateChapterFailed(String chapter);

  /// No description provided for @mapGenerateBlocked.
  ///
  /// In en, this message translates to:
  /// **'Keep or discard the generated map before continuing'**
  String get mapGenerateBlocked;

  /// No description provided for @mapGenerateBlockedRunning.
  ///
  /// In en, this message translates to:
  /// **'Content is being generated. Wait for it to finish or click Stop.'**
  String get mapGenerateBlockedRunning;

  /// No description provided for @mapGenerateCreated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Created “{title}” · 1 topic} other{Created “{title}” · {count} topics}}'**
  String mapGenerateCreated(String title, int count);

  /// No description provided for @mapGenerateNothing.
  ///
  /// In en, this message translates to:
  /// **'No usable structure. Try another organization.'**
  String get mapGenerateNothing;

  /// No description provided for @mapGenerateStoppedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Stopped before any topics'**
  String get mapGenerateStoppedEmpty;

  /// No description provided for @mapGenerateDraftSemantics.
  ///
  /// In en, this message translates to:
  /// **'AI draft, {title}, page {page}, {state}'**
  String mapGenerateDraftSemantics(String title, int page, String state);

  /// No description provided for @mapGenerateReadProgress.
  ///
  /// In en, this message translates to:
  /// **'Read {done} of {total} chapters'**
  String mapGenerateReadProgress(int done, int total);

  /// No description provided for @mapGenerateReady.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Ready to review, 1 topic} other{Ready to review, {count} topics}}'**
  String mapGenerateReady(int count);

  /// No description provided for @mapSourceSemantics.
  ///
  /// In en, this message translates to:
  /// **'{document}, page {page}'**
  String mapSourceSemantics(String document, int page);

  /// No description provided for @mapBannerNoMap.
  ///
  /// In en, this message translates to:
  /// **'“{document}” has no map'**
  String mapBannerNoMap(String document);

  /// No description provided for @mapBannerGenerate.
  ///
  /// In en, this message translates to:
  /// **'New Map'**
  String get mapBannerGenerate;

  /// No description provided for @mapBannerMerge.
  ///
  /// In en, this message translates to:
  /// **'Add to This Map'**
  String get mapBannerMerge;

  /// No description provided for @mapBannerNeedsOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognize text to generate a map'**
  String get mapBannerNeedsOcr;

  /// No description provided for @mapFollowSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to “{title}”'**
  String mapFollowSwitched(String title);

  /// No description provided for @mapUpdateDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose sources, then preview and confirm changes before applying them to your map.'**
  String get mapUpdateDescription;

  /// No description provided for @mapUpdateReadBaseline.
  ///
  /// In en, this message translates to:
  /// **'Previously updated through page {page}'**
  String mapUpdateReadBaseline(int page);

  /// No description provided for @mapUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Map'**
  String get mapUpdateTitle;

  /// No description provided for @mapUpdateSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get mapUpdateSources;

  /// No description provided for @mapUpdateAddDocument.
  ///
  /// In en, this message translates to:
  /// **'Add Document'**
  String get mapUpdateAddDocument;

  /// No description provided for @mapUpdateSince.
  ///
  /// In en, this message translates to:
  /// **'Since Last Generated'**
  String get mapUpdateSince;

  /// No description provided for @mapUpdateNewHighlights.
  ///
  /// In en, this message translates to:
  /// **'New highlights'**
  String get mapUpdateNewHighlights;

  /// No description provided for @mapUpdateNewNotes.
  ///
  /// In en, this message translates to:
  /// **'New notes'**
  String get mapUpdateNewNotes;

  /// No description provided for @mapUpdateReadTo.
  ///
  /// In en, this message translates to:
  /// **'Read to'**
  String get mapUpdateReadTo;

  /// No description provided for @mapUpdateReadRange.
  ///
  /// In en, this message translates to:
  /// **'p.{from} → p.{to}'**
  String mapUpdateReadRange(int from, int to);

  /// No description provided for @mapUpdateScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get mapUpdateScope;

  /// No description provided for @mapUpdateScopeNew.
  ///
  /// In en, this message translates to:
  /// **'New Material Only'**
  String get mapUpdateScopeNew;

  /// No description provided for @mapUpdateScopeAll.
  ///
  /// In en, this message translates to:
  /// **'Rework Everything'**
  String get mapUpdateScopeAll;

  /// No description provided for @mapUpdateProtected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 edited topic stays as is} other{{count} edited topics stay as they are}}'**
  String mapUpdateProtected(int count);

  /// No description provided for @mapUpdatePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview Changes'**
  String get mapUpdatePreview;

  /// No description provided for @mapUpdateNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to update'**
  String get mapUpdateNothing;

  /// No description provided for @mapDiffAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get mapDiffAdded;

  /// No description provided for @mapDiffRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get mapDiffRenamed;

  /// No description provided for @mapDiffMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get mapDiffMoved;

  /// No description provided for @mapDiffRemoved.
  ///
  /// In en, this message translates to:
  /// **'Suggested Removals'**
  String get mapDiffRemoved;

  /// No description provided for @mapDiffTagNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get mapDiffTagNew;

  /// No description provided for @mapDiffTagMovedFrom.
  ///
  /// In en, this message translates to:
  /// **'From {from}'**
  String mapDiffTagMovedFrom(String from);

  /// No description provided for @mapDiffTagRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get mapDiffTagRemove;

  /// No description provided for @mapDiffMoveRoute.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to}'**
  String mapDiffMoveRoute(String from, String to);

  /// No description provided for @mapDiffExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Excerpt: {text}'**
  String mapDiffExcerpt(String text);

  /// No description provided for @mapDiffProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get mapDiffProtected;

  /// No description provided for @mapUpdateApply.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Apply 1} other{Apply {count}}}'**
  String mapUpdateApply(int count);

  /// No description provided for @mapUpdateApplied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 item} other{Updated {count} items}}'**
  String mapUpdateApplied(int count);

  /// No description provided for @mapUpdateBlocked.
  ///
  /// In en, this message translates to:
  /// **'Apply or discard the map update before continuing'**
  String get mapUpdateBlocked;

  /// No description provided for @mapDiffAddSemantics.
  ///
  /// In en, this message translates to:
  /// **'Suggested addition, {title}'**
  String mapDiffAddSemantics(String title);

  /// No description provided for @mapDiffRenameSemantics.
  ///
  /// In en, this message translates to:
  /// **'Suggested rename, {old} to {title}'**
  String mapDiffRenameSemantics(String old, String title);

  /// No description provided for @mapDiffMoveSemantics.
  ///
  /// In en, this message translates to:
  /// **'Suggested move, {title}, from {from} to {to}'**
  String mapDiffMoveSemantics(String title, String from, String to);

  /// No description provided for @mapDiffRemoveSemantics.
  ///
  /// In en, this message translates to:
  /// **'Suggested removal, {title}, {reason}'**
  String mapDiffRemoveSemantics(String title, String reason);

  /// No description provided for @settingsMapFollowDocument.
  ///
  /// In en, this message translates to:
  /// **'Switch Maps with Documents'**
  String get settingsMapFollowDocument;

  /// No description provided for @settingsMapClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Generation Cache'**
  String get settingsMapClearCache;

  /// No description provided for @notesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesTitle;

  /// No description provided for @organizeStudyNote.
  ///
  /// In en, this message translates to:
  /// **'Organize Study Notes…'**
  String get organizeStudyNote;

  /// No description provided for @organizeNotes.
  ///
  /// In en, this message translates to:
  /// **'Organize Notes'**
  String get organizeNotes;

  /// No description provided for @organizeSelection.
  ///
  /// In en, this message translates to:
  /// **'Create Study Note'**
  String get organizeSelection;

  /// No description provided for @exportStudyNote.
  ///
  /// In en, this message translates to:
  /// **'Export Note…'**
  String get exportStudyNote;

  /// No description provided for @noteMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get noteMoreOptions;

  /// No description provided for @noteSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Organize Study Notes'**
  String get noteSetupTitle;

  /// No description provided for @noteScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get noteScope;

  /// No description provided for @noteMaterials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get noteMaterials;

  /// No description provided for @noteOrganization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get noteOrganization;

  /// No description provided for @noteDepth.
  ///
  /// In en, this message translates to:
  /// **'AI Contribution'**
  String get noteDepth;

  /// No description provided for @noteContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get noteContext;

  /// No description provided for @noteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get noteTemplate;

  /// No description provided for @noteSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected highlights'**
  String get noteSelected;

  /// No description provided for @noteWhole.
  ///
  /// In en, this message translates to:
  /// **'Entire study set'**
  String get noteWhole;

  /// No description provided for @noteRecent.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get noteRecent;

  /// No description provided for @noteHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get noteHighlights;

  /// No description provided for @noteOwn.
  ///
  /// In en, this message translates to:
  /// **'My Notes'**
  String get noteOwn;

  /// No description provided for @noteMapNotes.
  ///
  /// In en, this message translates to:
  /// **'Map Notes'**
  String get noteMapNotes;

  /// No description provided for @noteSavedAi.
  ///
  /// In en, this message translates to:
  /// **'Saved AI Notes'**
  String get noteSavedAi;

  /// No description provided for @noteImages.
  ///
  /// In en, this message translates to:
  /// **'Image Cards'**
  String get noteImages;

  /// No description provided for @noteTheme.
  ///
  /// In en, this message translates to:
  /// **'By Theme'**
  String get noteTheme;

  /// No description provided for @noteSourceOrder.
  ///
  /// In en, this message translates to:
  /// **'Source Order'**
  String get noteSourceOrder;

  /// No description provided for @noteMapOrder.
  ///
  /// In en, this message translates to:
  /// **'Map Structure'**
  String get noteMapOrder;

  /// No description provided for @noteLocal.
  ///
  /// In en, this message translates to:
  /// **'Format Only'**
  String get noteLocal;

  /// No description provided for @noteAiContext.
  ///
  /// In en, this message translates to:
  /// **'Context & Summary'**
  String get noteAiContext;

  /// No description provided for @noteAiDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep Organization'**
  String get noteAiDeep;

  /// No description provided for @noteNextPhase.
  ///
  /// In en, this message translates to:
  /// **'Available in the next release'**
  String get noteNextPhase;

  /// No description provided for @noteComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete Fragments'**
  String get noteComplete;

  /// No description provided for @noteReading.
  ///
  /// In en, this message translates to:
  /// **'Reading Notes'**
  String get noteReading;

  /// No description provided for @noteCornell.
  ///
  /// In en, this message translates to:
  /// **'Cornell Notes'**
  String get noteCornell;

  /// No description provided for @noteReview.
  ///
  /// In en, this message translates to:
  /// **'Review Outline'**
  String get noteReview;

  /// No description provided for @noteGenerate.
  ///
  /// In en, this message translates to:
  /// **'Create Note'**
  String get noteGenerate;

  /// No description provided for @noteEmptyScope.
  ///
  /// In en, this message translates to:
  /// **'No highlights in this scope'**
  String get noteEmptyScope;

  /// No description provided for @noteGenerated.
  ///
  /// In en, this message translates to:
  /// **'Note created'**
  String get noteGenerated;

  /// No description provided for @noteFailureAuthentication.
  ///
  /// In en, this message translates to:
  /// **'The model service could not verify your API key. Check model settings, or use layout only.'**
  String get noteFailureAuthentication;

  /// No description provided for @noteFailureTimeout.
  ///
  /// In en, this message translates to:
  /// **'The model took too long. Retry to continue from completed sections, or use layout only.'**
  String get noteFailureTimeout;

  /// No description provided for @noteFailureBudget.
  ///
  /// In en, this message translates to:
  /// **'The model stopped before completing its output. Retry to continue organizing, or use layout only.'**
  String get noteFailureBudget;

  /// No description provided for @noteFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the model service. Check your connection and retry, or use layout only.'**
  String get noteFailureNetwork;

  /// No description provided for @noteFailureService.
  ///
  /// In en, this message translates to:
  /// **'The model service is busy or unavailable. Retry later, or use layout only.'**
  String get noteFailureService;

  /// No description provided for @noteFailureProtocol.
  ///
  /// In en, this message translates to:
  /// **'The model returned an incomplete or unsupported response. Retry, or use layout only.'**
  String get noteFailureProtocol;

  /// No description provided for @noteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create note'**
  String get noteFailed;

  /// No description provided for @noteUnused.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get noteUnused;

  /// No description provided for @notePutBack.
  ///
  /// In en, this message translates to:
  /// **'Put Back'**
  String get notePutBack;

  /// No description provided for @noteRestored.
  ///
  /// In en, this message translates to:
  /// **'Added to note'**
  String get noteRestored;

  /// No description provided for @noteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from note'**
  String get noteRemoved;

  /// No description provided for @noteExpandContext.
  ///
  /// In en, this message translates to:
  /// **'Expand Context'**
  String get noteExpandContext;

  /// No description provided for @noteCollapseContext.
  ///
  /// In en, this message translates to:
  /// **'Collapse Context'**
  String get noteCollapseContext;

  /// No description provided for @noteNoText.
  ///
  /// In en, this message translates to:
  /// **'No source text'**
  String get noteNoText;

  /// No description provided for @noteMissingHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight deleted'**
  String get noteMissingHighlight;

  /// No description provided for @noteMissingDocument.
  ///
  /// In en, this message translates to:
  /// **'Source removed'**
  String get noteMissingDocument;

  /// No description provided for @noteNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'This highlight is not in the note'**
  String get noteNotIncluded;

  /// No description provided for @noteRemoveBlock.
  ///
  /// In en, this message translates to:
  /// **'Remove from Note'**
  String get noteRemoveBlock;

  /// No description provided for @noteSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get noteSources;

  /// No description provided for @noteInclude.
  ///
  /// In en, this message translates to:
  /// **'Include'**
  String get noteInclude;

  /// No description provided for @noteCitationPage.
  ///
  /// In en, this message translates to:
  /// **'Page Numbers'**
  String get noteCitationPage;

  /// No description provided for @noteCitationFootnote.
  ///
  /// In en, this message translates to:
  /// **'Footnotes'**
  String get noteCitationFootnote;

  /// No description provided for @noteCitationNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noteCitationNone;

  /// No description provided for @noteAiContent.
  ///
  /// In en, this message translates to:
  /// **'AI Content'**
  String get noteAiContent;

  /// No description provided for @noteQuestions.
  ///
  /// In en, this message translates to:
  /// **'Review Questions'**
  String get noteQuestions;

  /// No description provided for @noteSourceList.
  ///
  /// In en, this message translates to:
  /// **'Source List'**
  String get noteSourceList;

  /// No description provided for @noteAiMarks.
  ///
  /// In en, this message translates to:
  /// **'AI Labels'**
  String get noteAiMarks;

  /// No description provided for @noteMark.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get noteMark;

  /// No description provided for @noteUnmark.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get noteUnmark;

  /// No description provided for @noteCornellSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get noteCornellSummary;

  /// No description provided for @noteContextSentences.
  ///
  /// In en, this message translates to:
  /// **'{count} surrounding sentences'**
  String noteContextSentences(int count);

  /// No description provided for @noteCoverage.
  ///
  /// In en, this message translates to:
  /// **'All {count} highlights cited · Original text preserved'**
  String noteCoverage(int count);

  /// No description provided for @noteUnusedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unused highlights'**
  String noteUnusedCount(int count);

  /// No description provided for @noteSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String noteSelectedCount(int count);

  /// No description provided for @noteRecallQuestion.
  ///
  /// In en, this message translates to:
  /// **'What does {title} {location} say?'**
  String noteRecallQuestion(String title, String location);

  /// No description provided for @noteSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get noteSelectAll;

  /// No description provided for @noteDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get noteDeselectAll;

  /// No description provided for @noteReviewAdded.
  ///
  /// In en, this message translates to:
  /// **'Created 1 review card'**
  String get noteReviewAdded;

  /// No description provided for @noteExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain This Passage'**
  String get noteExplain;

  /// No description provided for @noteCreateReview.
  ///
  /// In en, this message translates to:
  /// **'Create Review Card'**
  String get noteCreateReview;

  /// No description provided for @noteAddedToMap.
  ///
  /// In en, this message translates to:
  /// **'Added to map'**
  String get noteAddedToMap;

  /// No description provided for @noteExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get noteExport;

  /// No description provided for @noteMarginSource.
  ///
  /// In en, this message translates to:
  /// **'Margin Note'**
  String get noteMarginSource;

  /// No description provided for @notePage.
  ///
  /// In en, this message translates to:
  /// **'p.{page}'**
  String notePage(int page);

  /// No description provided for @noteSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'{title}'**
  String noteSourceTitle(String title);

  /// No description provided for @notePageSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get notePageSeparator;

  /// No description provided for @noteSourcePage.
  ///
  /// In en, this message translates to:
  /// **'{title}, p. {page}'**
  String noteSourcePage(String title, int page);

  /// No description provided for @noteOutlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm outline'**
  String get noteOutlineTitle;

  /// No description provided for @noteGenerating.
  ///
  /// In en, this message translates to:
  /// **'Organizing note'**
  String get noteGenerating;

  /// No description provided for @noteStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get noteStop;

  /// No description provided for @noteContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue organizing'**
  String get noteContinue;

  /// No description provided for @noteLayoutOnly.
  ///
  /// In en, this message translates to:
  /// **'Use original order'**
  String get noteLayoutOnly;

  /// No description provided for @noteStepOutline.
  ///
  /// In en, this message translates to:
  /// **'Grouping themes'**
  String get noteStepOutline;

  /// No description provided for @noteAddSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get noteAddSection;

  /// No description provided for @noteNewSection.
  ///
  /// In en, this message translates to:
  /// **'New section'**
  String get noteNewSection;

  /// No description provided for @noteUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get noteUnassigned;

  /// No description provided for @noteAiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AI not configured'**
  String get noteAiUnavailable;

  /// No description provided for @notePreviewOutline.
  ///
  /// In en, this message translates to:
  /// **'Preview outline'**
  String get notePreviewOutline;

  /// No description provided for @noteAiFallback.
  ///
  /// In en, this message translates to:
  /// **'AI organization failed; used original order'**
  String get noteAiFallback;

  /// No description provided for @noteShowAi.
  ///
  /// In en, this message translates to:
  /// **'Show AI markers'**
  String get noteShowAi;

  /// No description provided for @noteAiEdited.
  ///
  /// In en, this message translates to:
  /// **'AI · Edited'**
  String get noteAiEdited;

  /// No description provided for @noteRephrase.
  ///
  /// In en, this message translates to:
  /// **'Rephrase'**
  String get noteRephrase;

  /// No description provided for @noteConcise.
  ///
  /// In en, this message translates to:
  /// **'Make concise'**
  String get noteConcise;

  /// No description provided for @noteExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get noteExpand;

  /// No description provided for @noteMakeMine.
  ///
  /// In en, this message translates to:
  /// **'Make it mine'**
  String get noteMakeMine;

  /// No description provided for @noteRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Reorganize'**
  String get noteRegenerate;

  /// No description provided for @noteAddAllReview.
  ///
  /// In en, this message translates to:
  /// **'Add all to review'**
  String get noteAddAllReview;

  /// No description provided for @noteStepWrite.
  ///
  /// In en, this message translates to:
  /// **'Writing {done} / {total} · Checking references'**
  String noteStepWrite(int done, int total);

  /// No description provided for @noteSending.
  ///
  /// In en, this message translates to:
  /// **'{notes, plural, =0{Send {highlights} highlights (about {characters} characters) to {model}} other{Send {highlights} highlights and {notes} notes (about {characters} characters) to {model}}}'**
  String noteSending(int highlights, int notes, int characters, String model);

  /// No description provided for @noteStepCollect.
  ///
  /// In en, this message translates to:
  /// **'Collect materials'**
  String get noteStepCollect;

  /// No description provided for @noteStepContext.
  ///
  /// In en, this message translates to:
  /// **'Gather context'**
  String get noteStepContext;

  /// No description provided for @noteStepCompose.
  ///
  /// In en, this message translates to:
  /// **'Write note'**
  String get noteStepCompose;

  /// No description provided for @noteStepVerify.
  ///
  /// In en, this message translates to:
  /// **'Check references'**
  String get noteStepVerify;

  /// No description provided for @noteStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get noteStopped;

  /// No description provided for @noteLocked.
  ///
  /// In en, this message translates to:
  /// **'Keep when updating'**
  String get noteLocked;

  /// No description provided for @resizeCompanionPanel.
  ///
  /// In en, this message translates to:
  /// **'Resize companion panel'**
  String get resizeCompanionPanel;

  /// No description provided for @noteNewMaterials.
  ///
  /// In en, this message translates to:
  /// **'{highlights, plural, =0{{notes, plural, =1{1 new note} other{{notes} new notes}}} =1{1 new highlight{notes, plural, =0{} =1{, 1 new note} other{, {notes} new notes}}} other{{highlights} new highlights{notes, plural, =0{} =1{, 1 new note} other{, {notes} new notes}}}}'**
  String noteNewMaterials(int highlights, int notes);

  /// No description provided for @notePreviewUpdate.
  ///
  /// In en, this message translates to:
  /// **'Preview Update'**
  String get notePreviewUpdate;

  /// No description provided for @noteApplyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Apply Update'**
  String get noteApplyUpdate;

  /// No description provided for @noteIgnoreUpdate.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get noteIgnoreUpdate;

  /// No description provided for @noteUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 addition} other{{count} additions}}'**
  String noteUpdateReady(int count);

  /// No description provided for @noteUpdateStale.
  ///
  /// In en, this message translates to:
  /// **'The note or its sources changed. Preview again.'**
  String get noteUpdateStale;

  /// No description provided for @noteUpdateApplied.
  ///
  /// In en, this message translates to:
  /// **'Updated · {count} added'**
  String noteUpdateApplied(int count);

  /// No description provided for @noteLocalPlacement.
  ///
  /// In en, this message translates to:
  /// **'In source order'**
  String get noteLocalPlacement;

  /// No description provided for @noteAddToReview.
  ///
  /// In en, this message translates to:
  /// **'Add to Review'**
  String get noteAddToReview;

  /// No description provided for @noteUpdateChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String noteUpdateChanges(int count);

  /// No description provided for @noteShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share as Image'**
  String get noteShareTitle;

  /// No description provided for @noteShareQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get noteShareQuote;

  /// No description provided for @noteShareSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get noteShareSection;

  /// No description provided for @noteShareSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get noteShareSummary;

  /// No description provided for @noteSharePaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get noteSharePaper;

  /// No description provided for @noteSharePlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get noteSharePlain;

  /// No description provided for @noteShareNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get noteShareNight;

  /// No description provided for @noteShareAi.
  ///
  /// In en, this message translates to:
  /// **'AI Summary'**
  String get noteShareAi;

  /// No description provided for @noteShareFooter.
  ///
  /// In en, this message translates to:
  /// **'From my Foliarc notes'**
  String get noteShareFooter;

  /// No description provided for @noteSharedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} highlights'**
  String noteSharedCount(int count);

  /// No description provided for @noteNoQuotes.
  ///
  /// In en, this message translates to:
  /// **'No quotes'**
  String get noteNoQuotes;

  /// No description provided for @noteCopyImage.
  ///
  /// In en, this message translates to:
  /// **'Copy Image'**
  String get noteCopyImage;

  /// No description provided for @noteSaveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image…'**
  String get noteSaveImage;

  /// No description provided for @noteShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get noteShareAction;

  /// No description provided for @noteCopyRich.
  ///
  /// In en, this message translates to:
  /// **'Copy as Rich Text'**
  String get noteCopyRich;

  /// No description provided for @noteCopyMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get noteCopyMarkdown;

  /// No description provided for @noteRichText.
  ///
  /// In en, this message translates to:
  /// **'Rich Text'**
  String get noteRichText;

  /// No description provided for @studyNoteSavedImage.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get studyNoteSavedImage;

  /// No description provided for @vocabularyHintsPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get vocabularyHintsPreview;

  /// No description provided for @vocabularyHintsPreviewMeaning.
  ///
  /// In en, this message translates to:
  /// **'inquisitive'**
  String get vocabularyHintsPreviewMeaning;

  /// No description provided for @settingsReadingPreferences.
  ///
  /// In en, this message translates to:
  /// **'Reading preferences'**
  String get settingsReadingPreferences;

  /// No description provided for @appIconTitle.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appIconTitle;

  /// No description provided for @appIconPaperArc.
  ///
  /// In en, this message translates to:
  /// **'Paper Arc (default)'**
  String get appIconPaperArc;

  /// No description provided for @appIconLeafFolio.
  ///
  /// In en, this message translates to:
  /// **'Leaf & Folio'**
  String get appIconLeafFolio;

  /// No description provided for @appIconFoldedF.
  ///
  /// In en, this message translates to:
  /// **'Folded F'**
  String get appIconFoldedF;

  /// No description provided for @appIconDockHint.
  ///
  /// In en, this message translates to:
  /// **'Changes the Dock icon. Finder keeps the default icon.'**
  String get appIconDockHint;

  /// No description provided for @appIconHomeHint.
  ///
  /// In en, this message translates to:
  /// **'Changes the Home Screen icon. iOS may show a confirmation.'**
  String get appIconHomeHint;

  /// No description provided for @appIconChanging.
  ///
  /// In en, this message translates to:
  /// **'Changing icon…'**
  String get appIconChanging;

  /// No description provided for @appIconChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the icon. Please try again.'**
  String get appIconChangeFailed;

  /// No description provided for @fullTranslationMenu.
  ///
  /// In en, this message translates to:
  /// **'Full Translation…'**
  String get fullTranslationMenu;

  /// No description provided for @fullTranslationTokensUsed.
  ///
  /// In en, this message translates to:
  /// **'Used '**
  String get fullTranslationTokensUsed;

  /// No description provided for @fullTranslationTask.
  ///
  /// In en, this message translates to:
  /// **'Full Translation…'**
  String get fullTranslationTask;

  /// No description provided for @fullTranslationTaskMenu.
  ///
  /// In en, this message translates to:
  /// **'Full Translation… {percent}%'**
  String fullTranslationTaskMenu(int percent);

  /// No description provided for @fullTranslationCapsule.
  ///
  /// In en, this message translates to:
  /// **'Full Translation'**
  String get fullTranslationCapsule;

  /// No description provided for @fullTranslationCapsuleRunning.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Batch {batch} · {done}/{total} pages'**
  String fullTranslationCapsuleRunning(int percent, int batch, int done, int total);

  /// No description provided for @fullTranslationCapsuleRunningAll.
  ///
  /// In en, this message translates to:
  /// **'{percent}% {done}/{total} pages'**
  String fullTranslationCapsuleRunningAll(int percent, int done, int total);

  /// No description provided for @fullTranslationCapsuleReview.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} Pending'**
  String fullTranslationCapsuleReview(int batch);

  /// No description provided for @fullTranslationCapsulePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused {done}/{total} pages'**
  String fullTranslationCapsulePaused(int done, int total);

  /// No description provided for @fullTranslationCapsuleOffline.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Network'**
  String get fullTranslationCapsuleOffline;

  /// No description provided for @fullTranslationCapsuleBudget.
  ///
  /// In en, this message translates to:
  /// **'Paused · Exceeded Estimate'**
  String get fullTranslationCapsuleBudget;

  /// No description provided for @fullTranslationCapsuleError.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get fullTranslationCapsuleError;

  /// No description provided for @fullTranslationCapsuleDone.
  ///
  /// In en, this message translates to:
  /// **'Fully Translated'**
  String get fullTranslationCapsuleDone;

  /// No description provided for @fullTranslationCapsuleDoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Completed · {count} untranslated'**
  String fullTranslationCapsuleDoneFailed(int count);

  /// No description provided for @fullTranslationCapsuleStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped {done}/{total} pages'**
  String fullTranslationCapsuleStopped(int done, int total);

  /// No description provided for @fullTranslationPlaceholderBatch.
  ///
  /// In en, this message translates to:
  /// **'Will translate in batch {batch}'**
  String fullTranslationPlaceholderBatch(int batch);

  /// No description provided for @fullTranslationPlaceholderPageSub.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String fullTranslationPlaceholderPageSub(int page);

  /// No description provided for @fullTranslationPlaceholderOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Not in translation range'**
  String get fullTranslationPlaceholderOutOfRange;

  /// No description provided for @fullTranslationPlaceholderUntranslated.
  ///
  /// In en, this message translates to:
  /// **'Untranslated'**
  String get fullTranslationPlaceholderUntranslated;

  /// No description provided for @fullTranslationTranslatePage.
  ///
  /// In en, this message translates to:
  /// **'Translate This Page'**
  String get fullTranslationTranslatePage;

  /// No description provided for @fullTranslationViewSaved.
  ///
  /// In en, this message translates to:
  /// **'View Translation'**
  String get fullTranslationViewSaved;

  /// No description provided for @fullTranslationConfirmIntro.
  ///
  /// In en, this message translates to:
  /// **'Translate the entire document paragraph by paragraph and read it alongside the original. Confirm the source and target languages first. Clicking “Start Translation” sends the text to your configured AI model and may incur charges. You can pause at any time; completed translations are saved.'**
  String get fullTranslationConfirmIntro;

  /// No description provided for @fullTranslationSameLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source and target languages are the same. Choose another target language.'**
  String get fullTranslationSameLanguage;

  /// No description provided for @fullTranslationStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start translation. Check your model connection and try again. Existing translations are saved.'**
  String get fullTranslationStartFailed;

  /// No description provided for @fullTranslationTextProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · {done}/{total} paragraphs'**
  String fullTranslationTextProgress(int percent, int done, int total);

  /// No description provided for @fullTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Full Translation'**
  String get fullTranslationTitle;

  /// No description provided for @fullTranslationDocSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{doc} · {pages} pages'**
  String fullTranslationDocSubtitle(String doc, int pages);

  /// No description provided for @fullTranslationSourceLangDetect.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get fullTranslationSourceLangDetect;

  /// No description provided for @fullTranslationSourceDetected.
  ///
  /// In en, this message translates to:
  /// **'{language} (detected)'**
  String fullTranslationSourceDetected(String language);

  /// No description provided for @fullTranslationRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get fullTranslationRange;

  /// No description provided for @fullTranslationRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get fullTranslationRangeAll;

  /// No description provided for @fullTranslationRangePages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get fullTranslationRangePages;

  /// No description provided for @fullTranslationMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get fullTranslationMode;

  /// No description provided for @fullTranslationModeBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch Review'**
  String get fullTranslationModeBatch;

  /// No description provided for @fullTranslationModeBatchDesc.
  ///
  /// In en, this message translates to:
  /// **'Pause after each batch to review before continuing'**
  String get fullTranslationModeBatchDesc;

  /// No description provided for @fullTranslationModeAll.
  ///
  /// In en, this message translates to:
  /// **'Translate All'**
  String get fullTranslationModeAll;

  /// No description provided for @fullTranslationModeAllDesc.
  ///
  /// In en, this message translates to:
  /// **'Translate continuously to the end, pause anytime'**
  String get fullTranslationModeAllDesc;

  /// No description provided for @fullTranslationBatchSize.
  ///
  /// In en, this message translates to:
  /// **'Per Batch'**
  String get fullTranslationBatchSize;

  /// No description provided for @fullTranslationBatchPages.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String fullTranslationBatchPages(int count);

  /// No description provided for @fullTranslationBatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count} batches total'**
  String fullTranslationBatchCount(int count);

  /// No description provided for @fullTranslationNote.
  ///
  /// In en, this message translates to:
  /// **'Glossary & Requirements'**
  String get fullTranslationNote;

  /// No description provided for @fullTranslationNotePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Optional. E.g. keep proper names untranslated'**
  String get fullTranslationNotePlaceholder;

  /// No description provided for @fullTranslationCkptFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} untranslated'**
  String fullTranslationCkptFailed(int count);

  /// No description provided for @fullTranslationNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Applies only to subsequent batches; translated paragraphs won\'t be retranslated.'**
  String get fullTranslationNoteHint;

  /// No description provided for @fullTranslationNoteConfigured.
  ///
  /// In en, this message translates to:
  /// **' · Configured'**
  String get fullTranslationNoteConfigured;

  /// No description provided for @fullTranslationFooterNote.
  ///
  /// In en, this message translates to:
  /// **'Translations stay in this study set. The original is preserved.'**
  String get fullTranslationFooterNote;

  /// No description provided for @fullTranslationStartBatch.
  ///
  /// In en, this message translates to:
  /// **'Start · Pages {from}–{to}'**
  String fullTranslationStartBatch(int from, int to);

  /// No description provided for @fullTranslationStartAll.
  ///
  /// In en, this message translates to:
  /// **'Start Translation'**
  String get fullTranslationStartAll;

  /// No description provided for @fullTranslationNothingToTranslate.
  ///
  /// In en, this message translates to:
  /// **'No paragraphs to translate'**
  String get fullTranslationNothingToTranslate;

  /// No description provided for @fullTranslationBlockedScannedTitle.
  ///
  /// In en, this message translates to:
  /// **'This document has no selectable text'**
  String get fullTranslationBlockedScannedTitle;

  /// No description provided for @fullTranslationBlockedScannedDesc.
  ///
  /// In en, this message translates to:
  /// **'Recognize text on device first, then translate.'**
  String get fullTranslationBlockedScannedDesc;

  /// No description provided for @fullTranslationActionOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognize Text'**
  String get fullTranslationActionOcr;

  /// No description provided for @fullTranslationBlockedNoModelTitle.
  ///
  /// In en, this message translates to:
  /// **'No AI model configured'**
  String get fullTranslationBlockedNoModelTitle;

  /// No description provided for @fullTranslationBlockedBadKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'API Key Invalid'**
  String get fullTranslationBlockedBadKeyTitle;

  /// No description provided for @fullTranslationBlockedModelDesc.
  ///
  /// In en, this message translates to:
  /// **'Full translation uses the assistant\'s default model.'**
  String get fullTranslationBlockedModelDesc;

  /// No description provided for @fullTranslationActionSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Assistant Settings'**
  String get fullTranslationActionSettings;

  /// No description provided for @fullTranslationBlockedOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Network Unavailable'**
  String get fullTranslationBlockedOfflineTitle;

  /// No description provided for @fullTranslationBlockedOfflineDesc.
  ///
  /// In en, this message translates to:
  /// **'You can start now; translation resumes automatically when online.'**
  String get fullTranslationBlockedOfflineDesc;

  /// No description provided for @fullTranslationEstChanged.
  ///
  /// In en, this message translates to:
  /// **'Source text re-recognized · {reused} / {total} existing translations reusable'**
  String fullTranslationEstChanged(int reused, int total);

  /// No description provided for @fullTranslationEstNeeds.
  ///
  /// In en, this message translates to:
  /// **'Needs translation: {paras} paragraphs · ~{chars} chars'**
  String fullTranslationEstNeeds(String paras, String chars);

  /// No description provided for @fullTranslationEstMinutes.
  ///
  /// In en, this message translates to:
  /// **'~{minutes} min'**
  String fullTranslationEstMinutes(int minutes);

  /// No description provided for @fullTranslationEstReused.
  ///
  /// In en, this message translates to:
  /// **'Already have {paras} translations ({pages} pages), reused directly'**
  String fullTranslationEstReused(int paras, int pages);

  /// No description provided for @fullTranslationEstReusedNoPages.
  ///
  /// In en, this message translates to:
  /// **'Already have {paras} translations, reused directly'**
  String fullTranslationEstReusedNoPages(int paras);

  /// No description provided for @fullTranslationEstSkip.
  ///
  /// In en, this message translates to:
  /// **'Not sent: {details}'**
  String fullTranslationEstSkip(String details);

  /// No description provided for @fullTranslationEstSkipMargin.
  ///
  /// In en, this message translates to:
  /// **'headers/footers {count}'**
  String fullTranslationEstSkipMargin(int count);

  /// No description provided for @fullTranslationEstSkipSame.
  ///
  /// In en, this message translates to:
  /// **'already {language} {count}'**
  String fullTranslationEstSkipSame(String language, int count);

  /// No description provided for @fullTranslationEstSkipDupe.
  ///
  /// In en, this message translates to:
  /// **'duplicate paragraphs {count}'**
  String fullTranslationEstSkipDupe(int count);

  /// No description provided for @fullTranslationEstModel.
  ///
  /// In en, this message translates to:
  /// **'{model} · Est. {tokens} tokens'**
  String fullTranslationEstModel(String model, String tokens);

  /// No description provided for @fullTranslationEstBudgetWarning.
  ///
  /// In en, this message translates to:
  /// **'; pauses for confirmation if 50% over estimate'**
  String get fullTranslationEstBudgetWarning;

  /// No description provided for @fullTranslationPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Full Translation'**
  String get fullTranslationPanelTitle;

  /// No description provided for @fullTranslationStateRunningBatch.
  ///
  /// In en, this message translates to:
  /// **'Translating · Batch {batch} (pages {from}–{to})'**
  String fullTranslationStateRunningBatch(int batch, int from, int to);

  /// No description provided for @fullTranslationStateRunningAll.
  ///
  /// In en, this message translates to:
  /// **'Translating · All at once'**
  String get fullTranslationStateRunningAll;

  /// No description provided for @fullTranslationStateReview.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} Pending'**
  String fullTranslationStateReview(int batch);

  /// No description provided for @fullTranslationStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get fullTranslationStatePaused;

  /// No description provided for @fullTranslationStateOffline.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Network'**
  String get fullTranslationStateOffline;

  /// No description provided for @fullTranslationStateBudget.
  ///
  /// In en, this message translates to:
  /// **'Paused · Exceeded Estimate'**
  String get fullTranslationStateBudget;

  /// No description provided for @fullTranslationStateError.
  ///
  /// In en, this message translates to:
  /// **'Paused · Needs Attention'**
  String get fullTranslationStateError;

  /// No description provided for @fullTranslationStateDone.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get fullTranslationStateDone;

  /// No description provided for @fullTranslationStateStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get fullTranslationStateStopped;

  /// No description provided for @fullTranslationLegendDone.
  ///
  /// In en, this message translates to:
  /// **'Translated'**
  String get fullTranslationLegendDone;

  /// No description provided for @fullTranslationLegendReused.
  ///
  /// In en, this message translates to:
  /// **'Reused'**
  String get fullTranslationLegendReused;

  /// No description provided for @fullTranslationLegendRunning.
  ///
  /// In en, this message translates to:
  /// **'Translating'**
  String get fullTranslationLegendRunning;

  /// No description provided for @fullTranslationLegendQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get fullTranslationLegendQueued;

  /// No description provided for @fullTranslationLegendFailed.
  ///
  /// In en, this message translates to:
  /// **'Untranslated'**
  String get fullTranslationLegendFailed;

  /// No description provided for @fullTranslationLegendSkipped.
  ///
  /// In en, this message translates to:
  /// **'No Translation Needed'**
  String get fullTranslationLegendSkipped;

  /// No description provided for @fullTranslationStatParas.
  ///
  /// In en, this message translates to:
  /// **'Paragraphs'**
  String get fullTranslationStatParas;

  /// No description provided for @fullTranslationStatEstToken.
  ///
  /// In en, this message translates to:
  /// **'Est. {tokens}'**
  String fullTranslationStatEstToken(String tokens);

  /// No description provided for @fullTranslationStatFailed.
  ///
  /// In en, this message translates to:
  /// **'Untranslated'**
  String get fullTranslationStatFailed;

  /// No description provided for @fullTranslationDetailReused.
  ///
  /// In en, this message translates to:
  /// **'Reused Translations'**
  String get fullTranslationDetailReused;

  /// No description provided for @fullTranslationDetailParas.
  ///
  /// In en, this message translates to:
  /// **'{count} paras'**
  String fullTranslationDetailParas(int count);

  /// No description provided for @fullTranslationDetailDedup.
  ///
  /// In en, this message translates to:
  /// **'Deduplicated Paragraphs'**
  String get fullTranslationDetailDedup;

  /// No description provided for @fullTranslationDetailSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not Sent (headers, page numbers, already {language})'**
  String fullTranslationDetailSkipped(String language);

  /// No description provided for @fullTranslationDetailItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String fullTranslationDetailItems(int count);

  /// No description provided for @fullTranslationDetailModelCalls.
  ///
  /// In en, this message translates to:
  /// **'Model · Requests'**
  String get fullTranslationDetailModelCalls;

  /// No description provided for @fullTranslationDetailCalls.
  ///
  /// In en, this message translates to:
  /// **'{model} · {calls} calls'**
  String fullTranslationDetailCalls(String model, int calls);

  /// No description provided for @fullTranslationDetailElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get fullTranslationDetailElapsed;

  /// No description provided for @fullTranslationDetailTime.
  ///
  /// In en, this message translates to:
  /// **'{minutes} m {seconds} s'**
  String fullTranslationDetailTime(int minutes, int seconds);

  /// No description provided for @fullTranslationActionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get fullTranslationActionStop;

  /// No description provided for @fullTranslationActionEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get fullTranslationActionEnd;

  /// No description provided for @fullTranslationActionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get fullTranslationActionPause;

  /// No description provided for @fullTranslationActionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get fullTranslationActionResume;

  /// No description provided for @fullTranslationActionNextBatch.
  ///
  /// In en, this message translates to:
  /// **'Next Batch'**
  String get fullTranslationActionNextBatch;

  /// No description provided for @fullTranslationActionRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry {count} Untranslated'**
  String fullTranslationActionRetryFailed(int count);

  /// No description provided for @fullTranslationActionContinueTranslation.
  ///
  /// In en, this message translates to:
  /// **'Continue Translation…'**
  String get fullTranslationActionContinueTranslation;

  /// No description provided for @fullTranslationActionClear.
  ///
  /// In en, this message translates to:
  /// **'Remove Translations…'**
  String get fullTranslationActionClear;

  /// No description provided for @fullTranslationClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove all AI translations for this document?'**
  String get fullTranslationClearTitle;

  /// No description provided for @fullTranslationClearMessage.
  ///
  /// In en, this message translates to:
  /// **'Manually edited translations will also be removed.'**
  String get fullTranslationClearMessage;

  /// No description provided for @fullTranslationCkptBatchDone.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} Completed'**
  String fullTranslationCkptBatchDone(int batch);

  /// No description provided for @fullTranslationCkptPages.
  ///
  /// In en, this message translates to:
  /// **'Pages {from}–{to}'**
  String fullTranslationCkptPages(int from, int to);

  /// No description provided for @fullTranslationCkptCollapseTip.
  ///
  /// In en, this message translates to:
  /// **'Collapse to read'**
  String get fullTranslationCkptCollapseTip;

  /// No description provided for @fullTranslationCkptExpandTip.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get fullTranslationCkptExpandTip;

  /// No description provided for @fullTranslationCkptMin.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch} Pending'**
  String fullTranslationCkptMin(int batch);

  /// No description provided for @fullTranslationCkptNextBatch.
  ///
  /// In en, this message translates to:
  /// **'Continue Pages {from}–{to}'**
  String fullTranslationCkptNextBatch(int from, int to);

  /// No description provided for @fullTranslationCkptFromPage.
  ///
  /// In en, this message translates to:
  /// **'Review starting from page {page}'**
  String fullTranslationCkptFromPage(int page);

  /// No description provided for @fullTranslationCkptRemain.
  ///
  /// In en, this message translates to:
  /// **'Remaining {pages} pages · ~{tokens} tokens'**
  String fullTranslationCkptRemain(int pages, String tokens);

  /// No description provided for @fullTranslationCkptTranslateRest.
  ///
  /// In en, this message translates to:
  /// **'Translate Rest All'**
  String get fullTranslationCkptTranslateRest;

  /// No description provided for @fullTranslationHudStartBatch.
  ///
  /// In en, this message translates to:
  /// **'Starting translation for pages {from}–{to}'**
  String fullTranslationHudStartBatch(int from, int to);

  /// No description provided for @fullTranslationHudStartAll.
  ///
  /// In en, this message translates to:
  /// **'Starting full document translation'**
  String get fullTranslationHudStartAll;

  /// No description provided for @fullTranslationHudDone.
  ///
  /// In en, this message translates to:
  /// **'Full translation completed'**
  String get fullTranslationHudDone;

  /// No description provided for @fullTranslationHudDoneFailed.
  ///
  /// In en, this message translates to:
  /// **'Full translation completed · {count} untranslated'**
  String fullTranslationHudDoneFailed(int count);

  /// No description provided for @fullTranslationHudView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get fullTranslationHudView;

  /// No description provided for @fullTranslationHudStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped · Translated content saved'**
  String get fullTranslationHudStopped;

  /// No description provided for @fullTranslationHudPausedAt.
  ///
  /// In en, this message translates to:
  /// **'Full translation paused at page {page}'**
  String fullTranslationHudPausedAt(int page);

  /// No description provided for @fullTranslationHudContinue.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get fullTranslationHudContinue;

  /// No description provided for @fullTranslationHudRestAll.
  ///
  /// In en, this message translates to:
  /// **'Remaining pages will be translated all at once'**
  String get fullTranslationHudRestAll;

  /// No description provided for @fullTranslationGridCell.
  ///
  /// In en, this message translates to:
  /// **'Page {page} · {state}'**
  String fullTranslationGridCell(int page, String state);

  /// No description provided for @fullTranslationCapsuleA11y.
  ///
  /// In en, this message translates to:
  /// **'Full translation, {percent}%, batch {batch}, {done} / {total} pages'**
  String fullTranslationCapsuleA11y(int percent, int batch, int done, int total);

  /// No description provided for @fullTranslationStripBadKey.
  ///
  /// In en, this message translates to:
  /// **'API key invalid, paused'**
  String get fullTranslationStripBadKey;

  /// No description provided for @fullTranslationStripSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Translated content saved'**
  String get fullTranslationStripSavedNote;

  /// No description provided for @fullTranslationStripNoModel.
  ///
  /// In en, this message translates to:
  /// **'No AI model available, paused'**
  String get fullTranslationStripNoModel;

  /// No description provided for @fullTranslationStripStorage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save translation, paused'**
  String get fullTranslationStripStorage;

  /// No description provided for @fullTranslationStripOffline.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable, resumes automatically when online'**
  String get fullTranslationStripOffline;

  /// No description provided for @fullTranslationStripBudget.
  ///
  /// In en, this message translates to:
  /// **'Used {tokens} tokens, 50% over estimate'**
  String fullTranslationStripBudget(String tokens);

  /// No description provided for @fullTranslationStripOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get fullTranslationStripOpenSettings;

  /// No description provided for @fullTranslationStripRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get fullTranslationStripRetry;

  /// No description provided for @fullTranslationHudNetworkRestored.
  ///
  /// In en, this message translates to:
  /// **'Network restored, resuming translation'**
  String get fullTranslationHudNetworkRestored;

  /// No description provided for @fullTranslationNotificationBodyFailed.
  ///
  /// In en, this message translates to:
  /// **'{doc} · {count} untranslated'**
  String fullTranslationNotificationBodyFailed(String doc, int count);

  /// No description provided for @phoneGlassTitle.
  ///
  /// In en, this message translates to:
  /// **'Phone Liquid Glass'**
  String get phoneGlassTitle;

  /// No description provided for @phoneGlassRegular.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get phoneGlassRegular;

  /// No description provided for @phoneGlassThick.
  ///
  /// In en, this message translates to:
  /// **'Thick'**
  String get phoneGlassThick;

  /// No description provided for @phoneGlassOpaque.
  ///
  /// In en, this message translates to:
  /// **'Opaque'**
  String get phoneGlassOpaque;

  /// No description provided for @phoneNavigationCloseDrawer.
  ///
  /// In en, this message translates to:
  /// **'Close study set'**
  String get phoneNavigationCloseDrawer;

  /// No description provided for @phoneNavigationNotes.
  ///
  /// In en, this message translates to:
  /// **'Study notes'**
  String get phoneNavigationNotes;

  /// No description provided for @phoneReaderReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get phoneReaderReading;

  /// No description provided for @phoneReaderTools.
  ///
  /// In en, this message translates to:
  /// **'Annotation tools'**
  String get phoneReaderTools;

  /// No description provided for @phoneReaderCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get phoneReaderCollapse;

  /// No description provided for @phoneReaderExitTools.
  ///
  /// In en, this message translates to:
  /// **'Finish annotating'**
  String get phoneReaderExitTools;

  /// No description provided for @phoneReaderPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String phoneReaderPercent(int percent);

  /// No description provided for @mapCacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear cache'**
  String get mapCacheClearFailed;

  /// No description provided for @translationRetranslate.
  ///
  /// In en, this message translates to:
  /// **'Retranslate'**
  String get translationRetranslate;

  /// No description provided for @translationEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Translation'**
  String get translationEdit;

  /// No description provided for @translationRetranslated.
  ///
  /// In en, this message translates to:
  /// **'Retranslated'**
  String get translationRetranslated;

  /// No description provided for @translationEdited.
  ///
  /// In en, this message translates to:
  /// **'Manually edited'**
  String get translationEdited;

  /// No description provided for @translationParagraphFailed.
  ///
  /// In en, this message translates to:
  /// **'Untranslated · {reason}'**
  String translationParagraphFailed(String reason);

  /// No description provided for @translationEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Changes Saved'**
  String get translationEditSaved;

  /// No description provided for @translationCopied.
  ///
  /// In en, this message translates to:
  /// **'Translation Copied'**
  String get translationCopied;

  /// No description provided for @translationRemoved.
  ///
  /// In en, this message translates to:
  /// **'Translations Removed'**
  String get translationRemoved;

  /// No description provided for @phoneMoreOutlineAndBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Outline & Bookmarks'**
  String get phoneMoreOutlineAndBookmarks;

  /// No description provided for @phoneMoreClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get phoneMoreClose;

  /// No description provided for @phoneMoreBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get phoneMoreBack;

  /// No description provided for @mapFailureDetails.
  ///
  /// In en, this message translates to:
  /// **'Failure details'**
  String get mapFailureDetails;

  /// No description provided for @mapFailureDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Generation incomplete'**
  String get mapFailureDialogTitle;

  /// No description provided for @mapFailureDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get mapFailureDiagnostics;

  /// No description provided for @mapFailureCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get mapFailureCopy;

  /// No description provided for @mapFailureTruncated.
  ///
  /// In en, this message translates to:
  /// **'The model output was cut off. Please retry.'**
  String get mapFailureTruncated;

  /// No description provided for @mapFailureInvalid.
  ///
  /// In en, this message translates to:
  /// **'The model response did not pass mind map validation.'**
  String get mapFailureInvalid;

  /// No description provided for @mapFailureEmpty.
  ///
  /// In en, this message translates to:
  /// **'The model returned no mind map content.'**
  String get mapFailureEmpty;

  /// No description provided for @mapFailureTimeout.
  ///
  /// In en, this message translates to:
  /// **'The model request timed out. Please retry.'**
  String get mapFailureTimeout;

  /// No description provided for @mapFailureLimit.
  ///
  /// In en, this message translates to:
  /// **'The content exceeded the per-request limit.'**
  String get mapFailureLimit;

  /// No description provided for @mapFailureRate.
  ///
  /// In en, this message translates to:
  /// **'The service is rate limited. Please retry later.'**
  String get mapFailureRate;

  /// No description provided for @mapFailureRequest.
  ///
  /// In en, this message translates to:
  /// **'The service rejected the request. Check the model configuration.'**
  String get mapFailureRequest;

  /// No description provided for @mapFailureDocumentText.
  ///
  /// In en, this message translates to:
  /// **'No readable text was found in the document.'**
  String get mapFailureDocumentText;

  /// No description provided for @mapFailureStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get mapFailureStage;

  /// No description provided for @mapFailurePrepare.
  ///
  /// In en, this message translates to:
  /// **'Preparing document'**
  String get mapFailurePrepare;

  /// No description provided for @mapFailureChapter.
  ///
  /// In en, this message translates to:
  /// **'Reading chapter'**
  String get mapFailureChapter;

  /// No description provided for @mapFailureBuild.
  ///
  /// In en, this message translates to:
  /// **'Building mind map'**
  String get mapFailureBuild;

  /// No description provided for @mapFailureUpdate.
  ///
  /// In en, this message translates to:
  /// **'Updating mind map'**
  String get mapFailureUpdate;

  /// No description provided for @mapFailureModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get mapFailureModel;

  /// No description provided for @mapFailureCode.
  ///
  /// In en, this message translates to:
  /// **'Error code'**
  String get mapFailureCode;

  /// No description provided for @mapFailureLines.
  ///
  /// In en, this message translates to:
  /// **'Received / accepted lines'**
  String get mapFailureLines;

  /// No description provided for @mapFailureStop.
  ///
  /// In en, this message translates to:
  /// **'Completion reason'**
  String get mapFailureStop;

  /// No description provided for @mapFailureOutputLimit.
  ///
  /// In en, this message translates to:
  /// **'Output token limit (includes reasoning)'**
  String get mapFailureOutputLimit;

  /// No description provided for @mapFailureReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning characters'**
  String get mapFailureReasoning;

  /// No description provided for @mapFailureRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected lines'**
  String get mapFailureRejected;

  /// No description provided for @mapFailureInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Not a complete JSON object'**
  String get mapFailureInvalidJson;

  /// No description provided for @mapFailureFields.
  ///
  /// In en, this message translates to:
  /// **'Unsupported fields or operation'**
  String get mapFailureFields;

  /// No description provided for @mapFailureReference.
  ///
  /// In en, this message translates to:
  /// **'Invalid or repeated reference'**
  String get mapFailureReference;

  /// No description provided for @mapFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty or repeated title'**
  String get mapFailureTitle;

  /// No description provided for @mapFailureParent.
  ///
  /// In en, this message translates to:
  /// **'Parent node is missing or invalid'**
  String get mapFailureParent;

  /// No description provided for @mapFailureDepth.
  ///
  /// In en, this message translates to:
  /// **'Too many node levels'**
  String get mapFailureDepth;

  /// No description provided for @mapFailureAnnotation.
  ///
  /// In en, this message translates to:
  /// **'Annotation reference is invalid'**
  String get mapFailureAnnotation;

  /// No description provided for @mapFailureSource.
  ///
  /// In en, this message translates to:
  /// **'Source fields are invalid'**
  String get mapFailureSource;

  /// No description provided for @mapFailureProtected.
  ///
  /// In en, this message translates to:
  /// **'Attempted to modify protected content'**
  String get mapFailureProtected;

  /// No description provided for @mapFailureLineSize.
  ///
  /// In en, this message translates to:
  /// **'Response line is too long'**
  String get mapFailureLineSize;

  /// No description provided for @mapGenerateSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get mapGenerateSource;

  /// No description provided for @mapGenerateChangeSources.
  ///
  /// In en, this message translates to:
  /// **'Change / Add'**
  String get mapGenerateChangeSources;

  /// No description provided for @mapGenerateMoreSettings.
  ///
  /// In en, this message translates to:
  /// **'More Settings'**
  String get mapGenerateMoreSettings;

  /// No description provided for @mapGenerateSelectSources.
  ///
  /// In en, this message translates to:
  /// **'Select Documents'**
  String get mapGenerateSelectSources;

  /// No description provided for @mapGenerateSourceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} documents'**
  String mapGenerateSourceCount(int count);

  /// No description provided for @mapGenerateStructurePreview.
  ///
  /// In en, this message translates to:
  /// **'Structure Illustration'**
  String get mapGenerateStructurePreview;

  /// No description provided for @mapGeneratePreviewDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Illustrates organization; actual content is generated later.'**
  String get mapGeneratePreviewDisclaimer;

  /// No description provided for @mapGeneratePreviewRoot.
  ///
  /// In en, this message translates to:
  /// **'Document Topic'**
  String get mapGeneratePreviewRoot;

  /// No description provided for @mapGeneratePreviewChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter {count}'**
  String mapGeneratePreviewChapter(int count);

  /// No description provided for @mapGeneratePreviewConcepts.
  ///
  /// In en, this message translates to:
  /// **'Key Concepts'**
  String get mapGeneratePreviewConcepts;

  /// No description provided for @mapGeneratePreviewLinks.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get mapGeneratePreviewLinks;

  /// No description provided for @mapGeneratePreviewMethods.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get mapGeneratePreviewMethods;

  /// No description provided for @mapGeneratePreviewWhat.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get mapGeneratePreviewWhat;

  /// No description provided for @mapGeneratePreviewWhy.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get mapGeneratePreviewWhy;

  /// No description provided for @mapGeneratePreviewHow.
  ///
  /// In en, this message translates to:
  /// **'How?'**
  String get mapGeneratePreviewHow;

  /// No description provided for @mapGeneratePreviewPoint.
  ///
  /// In en, this message translates to:
  /// **'Key Point {count}'**
  String mapGeneratePreviewPoint(int count);

  /// No description provided for @mapGenerateInstructionsHint.
  ///
  /// In en, this message translates to:
  /// **'Additional instructions (optional)'**
  String get mapGenerateInstructionsHint;

  /// No description provided for @mapGenerateDestinationNew.
  ///
  /// In en, this message translates to:
  /// **'A new map will be created'**
  String get mapGenerateDestinationNew;

  /// No description provided for @mapGenerateDestinationBranch.
  ///
  /// In en, this message translates to:
  /// **'Will be added to the current map'**
  String get mapGenerateDestinationBranch;

  /// No description provided for @mapGenerateMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Map Name'**
  String get mapGenerateMapTitle;

  /// No description provided for @mapGenerateNoSources.
  ///
  /// In en, this message translates to:
  /// **'No documents available'**
  String get mapGenerateNoSources;

  /// No description provided for @mapGenerateSourceRange.
  ///
  /// In en, this message translates to:
  /// **'Document Range'**
  String get mapGenerateSourceRange;

  /// No description provided for @mapGenerateResetRange.
  ///
  /// In en, this message translates to:
  /// **'Use Full Text'**
  String get mapGenerateResetRange;

  /// No description provided for @mapGenerateMarksSummary.
  ///
  /// In en, this message translates to:
  /// **'Includes {count} annotations'**
  String mapGenerateMarksSummary(int count);

  /// No description provided for @mapGenerateStructureDepth.
  ///
  /// In en, this message translates to:
  /// **'{count} levels'**
  String mapGenerateStructureDepth(int count);

  /// No description provided for @noteProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Organizing note'**
  String get noteProgressTitle;

  /// No description provided for @noteProgressLayoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Formatting note'**
  String get noteProgressLayoutTitle;

  /// No description provided for @noteStepLayout.
  ///
  /// In en, this message translates to:
  /// **'Format sections'**
  String get noteStepLayout;

  /// No description provided for @noteProgressCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed {done} / {total} sections'**
  String noteProgressCompleted(int done, int total);

  /// No description provided for @noteProgressWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing section {index}'**
  String noteProgressWriting(int index);

  /// No description provided for @noteProgressLayoutSection.
  ///
  /// In en, this message translates to:
  /// **'Formatting section {index}'**
  String noteProgressLayoutSection(int index);

  /// No description provided for @noteProgressPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'The preview appears as each section is completed'**
  String get noteProgressPreviewEmpty;

  /// No description provided for @workspaceOpenTabs.
  ///
  /// In en, this message translates to:
  /// **'Open Tabs'**
  String get workspaceOpenTabs;

  /// No description provided for @workspaceDocumentMapTab.
  ///
  /// In en, this message translates to:
  /// **'Documents & Mind Maps'**
  String get workspaceDocumentMapTab;

  /// No description provided for @workspaceReferenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get workspaceReferenceTitle;

  /// No description provided for @workspaceReferenceFrom.
  ///
  /// In en, this message translates to:
  /// **'From: {title}'**
  String workspaceReferenceFrom(String title);

  /// No description provided for @workspaceNoTabs.
  ///
  /// In en, this message translates to:
  /// **'Open content from the sidebar'**
  String get workspaceNoTabs;

  /// No description provided for @workspaceTagMatches.
  ///
  /// In en, this message translates to:
  /// **'{count} matching topics'**
  String workspaceTagMatches(int count);

  /// No description provided for @workspaceCurrentContent.
  ///
  /// In en, this message translates to:
  /// **'Current content: {title}'**
  String workspaceCurrentContent(String title);

  /// No description provided for @settingsAdvancedGroup.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsAdvancedGroup;

  /// No description provided for @settingsEnableBetaFeatures.
  ///
  /// In en, this message translates to:
  /// **'Enable Beta Features'**
  String get settingsEnableBetaFeatures;

  /// No description provided for @assistantIconTitle.
  ///
  /// In en, this message translates to:
  /// **'AI assistant icon'**
  String get assistantIconTitle;

  /// No description provided for @assistantIconIris.
  ///
  /// In en, this message translates to:
  /// **'Blue purple'**
  String get assistantIconIris;

  /// No description provided for @assistantIconJade.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get assistantIconJade;

  /// No description provided for @assistantIconApricot.
  ///
  /// In en, this message translates to:
  /// **'Apricot'**
  String get assistantIconApricot;

  /// No description provided for @mapBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get mapBackground;

  /// No description provided for @mapBackgroundTheme.
  ///
  /// In en, this message translates to:
  /// **'Follow Theme'**
  String get mapBackgroundTheme;

  /// No description provided for @mapBackgroundBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get mapBackgroundBlack;

  /// No description provided for @mapBackgroundCharcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get mapBackgroundCharcoal;

  /// No description provided for @mapBackgroundGray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get mapBackgroundGray;

  /// No description provided for @mapBackgroundLightGray.
  ///
  /// In en, this message translates to:
  /// **'Light Gray'**
  String get mapBackgroundLightGray;

  /// No description provided for @mapBackgroundWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get mapBackgroundWhite;

  /// No description provided for @mapBackgroundIvory.
  ///
  /// In en, this message translates to:
  /// **'Ivory'**
  String get mapBackgroundIvory;

  /// No description provided for @mapBackgroundSage.
  ///
  /// In en, this message translates to:
  /// **'Sage'**
  String get mapBackgroundSage;

  /// No description provided for @mapBackgroundBlue.
  ///
  /// In en, this message translates to:
  /// **'Pale Blue'**
  String get mapBackgroundBlue;

  /// No description provided for @aiTasksTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Features'**
  String get aiTasksTitle;

  /// No description provided for @aiTasksQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick Tasks'**
  String get aiTasksQuick;

  /// No description provided for @aiTasksHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy Tasks'**
  String get aiTasksHeavy;

  /// No description provided for @aiTasksThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get aiTasksThinking;

  /// No description provided for @aiTasksThinkingAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get aiTasksThinkingAuto;

  /// No description provided for @aiTasksThinkingOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiTasksThinkingOff;

  /// No description provided for @aiTasksThinkingStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get aiTasksThinkingStandard;

  /// No description provided for @aiTasksThinkingDeep.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get aiTasksThinkingDeep;

  /// No description provided for @aiTasksUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use Default'**
  String get aiTasksUseDefault;

  /// No description provided for @aiTasksUseSetting.
  ///
  /// In en, this message translates to:
  /// **'Use Setting'**
  String get aiTasksUseSetting;

  /// No description provided for @aiTasksChooseModel.
  ///
  /// In en, this message translates to:
  /// **'Choose Model'**
  String get aiTasksChooseModel;

  /// No description provided for @aiTasksNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not Set'**
  String get aiTasksNotSet;

  /// No description provided for @aiTasksReasonThinking.
  ///
  /// In en, this message translates to:
  /// **'Can\'t turn off thinking'**
  String get aiTasksReasonThinking;

  /// No description provided for @aiTasksReasonTools.
  ///
  /// In en, this message translates to:
  /// **'No tool use'**
  String get aiTasksReasonTools;

  /// No description provided for @aiTasksReasonStructured.
  ///
  /// In en, this message translates to:
  /// **'No structured output'**
  String get aiTasksReasonStructured;

  /// No description provided for @aiTasksReasonContext.
  ///
  /// In en, this message translates to:
  /// **'Context too small'**
  String get aiTasksReasonContext;

  /// No description provided for @aiTasksReasonUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get aiTasksReasonUnsupported;

  /// No description provided for @aiTasksUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get aiTasksUnverified;

  /// No description provided for @aiTasksIssueThinking.
  ///
  /// In en, this message translates to:
  /// **'This model can\'t turn off thinking'**
  String get aiTasksIssueThinking;

  /// No description provided for @aiTasksIssueUnknown.
  ///
  /// In en, this message translates to:
  /// **'Compatibility not verified'**
  String get aiTasksIssueUnknown;

  /// No description provided for @aiTasksIssueReachable.
  ///
  /// In en, this message translates to:
  /// **'Connected · compatibility not verified'**
  String get aiTasksIssueReachable;

  /// No description provided for @aiTasksIssueTools.
  ///
  /// In en, this message translates to:
  /// **'This model doesn\'t support tool use'**
  String get aiTasksIssueTools;

  /// No description provided for @aiTasksIssueStructured.
  ///
  /// In en, this message translates to:
  /// **'This model doesn\'t support structured output'**
  String get aiTasksIssueStructured;

  /// No description provided for @aiTasksIssueContext.
  ///
  /// In en, this message translates to:
  /// **'This model\'s context is too small'**
  String get aiTasksIssueContext;

  /// No description provided for @aiTasksIssueUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This model doesn\'t support this feature'**
  String get aiTasksIssueUnsupported;

  /// No description provided for @aiTasksIssueDeleted.
  ///
  /// In en, this message translates to:
  /// **'Model removed'**
  String get aiTasksIssueDeleted;

  /// No description provided for @aiTasksIssueModelOff.
  ///
  /// In en, this message translates to:
  /// **'Model off'**
  String get aiTasksIssueModelOff;

  /// No description provided for @aiTasksIssueServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Service off'**
  String get aiTasksIssueServiceOff;

  /// No description provided for @aiTasksIssueServiceRemoved.
  ///
  /// In en, this message translates to:
  /// **'Service removed'**
  String get aiTasksIssueServiceRemoved;

  /// No description provided for @aiTasksIssueConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection unavailable'**
  String get aiTasksIssueConnection;

  /// No description provided for @aiTasksIssueInvalid.
  ///
  /// In en, this message translates to:
  /// **'Setting can\'t be read'**
  String get aiTasksIssueInvalid;

  /// No description provided for @aiTasksChangeModel.
  ///
  /// In en, this message translates to:
  /// **'Change Model'**
  String get aiTasksChangeModel;

  /// No description provided for @aiTasksTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get aiTasksTest;

  /// No description provided for @aiTasksChooseAgain.
  ///
  /// In en, this message translates to:
  /// **'Choose Again'**
  String get aiTasksChooseAgain;

  /// No description provided for @aiTasksOpenModelSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Model Settings'**
  String get aiTasksOpenModelSettings;

  /// No description provided for @aiTasksReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get aiTasksReset;

  /// No description provided for @aiTasksConflict.
  ///
  /// In en, this message translates to:
  /// **'Changed in another window'**
  String get aiTasksConflict;

  /// No description provided for @aiTasksReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get aiTasksReload;

  /// No description provided for @aiTasksAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get aiTasksAddModel;

  /// No description provided for @aiTasksCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Save changes to AI Features?'**
  String get aiTasksCloseTitle;

  /// No description provided for @aiTasksDontSave.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Save'**
  String get aiTasksDontSave;

  /// No description provided for @aiTasksAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign…'**
  String get aiTasksAssign;

  /// No description provided for @aiTasksAddedModels.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 model} other{Added {count} models}}'**
  String aiTasksAddedModels(int count);

  /// No description provided for @aiTasksAssignToFeatures.
  ///
  /// In en, this message translates to:
  /// **'Assign to Features'**
  String get aiTasksAssignToFeatures;

  /// No description provided for @aiTasksRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}”?'**
  String aiTasksRemoveTitle(String name);

  /// No description provided for @aiTasksQuickDefault.
  ///
  /// In en, this message translates to:
  /// **'Quick default'**
  String get aiTasksQuickDefault;

  /// No description provided for @aiTasksHeavyDefault.
  ///
  /// In en, this message translates to:
  /// **'Heavy default'**
  String get aiTasksHeavyDefault;

  /// No description provided for @aiTasksConversations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conversation} other{{count} conversations}}'**
  String aiTasksConversations(int count);

  /// No description provided for @aiTasksMore.
  ///
  /// In en, this message translates to:
  /// **'{count} more'**
  String aiTasksMore(int count);

  /// No description provided for @aiTasksUsageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check where it\'s used'**
  String get aiTasksUsageUnavailable;

  /// No description provided for @aiTasksRunLabel.
  ///
  /// In en, this message translates to:
  /// **'{task} · {source}'**
  String aiTasksRunLabel(String task, String source);

  /// No description provided for @aiTasksModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiTasksModel;

  /// No description provided for @aiTasksRunAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Needs confirmation'**
  String get aiTasksRunAwaiting;

  /// No description provided for @aiTasksRunPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get aiTasksRunPaused;

  /// No description provided for @aiTasksRunPausedCount.
  ///
  /// In en, this message translates to:
  /// **'Paused {done}/{total}'**
  String aiTasksRunPausedCount(int done, int total);

  /// No description provided for @aiTasksRunInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get aiTasksRunInterrupted;

  /// No description provided for @aiTasksRunInterruptedCount.
  ///
  /// In en, this message translates to:
  /// **'Interrupted {done}/{total}'**
  String aiTasksRunInterruptedCount(int done, int total);

  /// No description provided for @aiTasksRunPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially complete · {count} {unit} unfinished'**
  String aiTasksRunPartial(int count, String unit);

  /// No description provided for @aiTasksRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get aiTasksRunFailed;

  /// No description provided for @aiTasksRunStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get aiTasksRunStopped;

  /// No description provided for @aiTasksRunStoppedCount.
  ///
  /// In en, this message translates to:
  /// **'Stopped {done}/{total}'**
  String aiTasksRunStoppedCount(int done, int total);

  /// No description provided for @aiTasksRunCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get aiTasksRunCompleted;

  /// No description provided for @aiTasksRunUnfinished.
  ///
  /// In en, this message translates to:
  /// **'Last run didn\'t finish'**
  String get aiTasksRunUnfinished;

  /// No description provided for @aiTasksRetryUnfinished.
  ///
  /// In en, this message translates to:
  /// **'Retry {count} {unit}'**
  String aiTasksRetryUnfinished(int count, String unit);

  /// No description provided for @aiTaskSelectionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Selection Translation'**
  String get aiTaskSelectionTranslate;

  /// No description provided for @aiTaskWordLookup.
  ///
  /// In en, this message translates to:
  /// **'Word Lookup'**
  String get aiTaskWordLookup;

  /// No description provided for @aiTaskTitleGenerate.
  ///
  /// In en, this message translates to:
  /// **'Title Generation'**
  String get aiTaskTitleGenerate;

  /// No description provided for @aiTaskAssistantChat.
  ///
  /// In en, this message translates to:
  /// **'Assistant Chat & Explain'**
  String get aiTaskAssistantChat;

  /// No description provided for @aiTaskConversationSummarize.
  ///
  /// In en, this message translates to:
  /// **'Conversation Summary'**
  String get aiTaskConversationSummarize;

  /// No description provided for @aiTaskDocumentSummarize.
  ///
  /// In en, this message translates to:
  /// **'Document Summary'**
  String get aiTaskDocumentSummarize;

  /// No description provided for @aiTaskDocumentTranslate.
  ///
  /// In en, this message translates to:
  /// **'Full Translation'**
  String get aiTaskDocumentTranslate;

  /// No description provided for @aiTaskMapExpand.
  ///
  /// In en, this message translates to:
  /// **'Mind Map Expansion'**
  String get aiTaskMapExpand;

  /// No description provided for @aiTaskMapGenerate.
  ///
  /// In en, this message translates to:
  /// **'Mind Map Generation & Update'**
  String get aiTaskMapGenerate;

  /// No description provided for @aiTaskResearch.
  ///
  /// In en, this message translates to:
  /// **'Research & Verification'**
  String get aiTaskResearch;

  /// No description provided for @aiTaskStudyNotes.
  ///
  /// In en, this message translates to:
  /// **'Study Note Organizing'**
  String get aiTaskStudyNotes;

  /// No description provided for @aiTaskReviewCards.
  ///
  /// In en, this message translates to:
  /// **'Review Cards & Questions'**
  String get aiTaskReviewCards;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
