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
  /// **'MarginMind'**
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
  /// **'Pick a document in the sidebar, or import a PDF into this study set.'**
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
  /// **'Page Fit'**
  String get readerZoom;

  /// No description provided for @readerAppearance.
  ///
  /// In en, this message translates to:
  /// **'Reading Appearance'**
  String get readerAppearance;

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
