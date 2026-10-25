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
  /// **'{documents} docs · {cards} cards'**
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

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Start your first study set'**
  String get firstRunTitle;

  /// No description provided for @firstRunMessage.
  ///
  /// In en, this message translates to:
  /// **'Drop one or more PDFs here and MarginMind will create a study set for them. Your highlights, cards and mind maps all live inside it.'**
  String get firstRunMessage;

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

  /// No description provided for @sheetLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get sheetLocation;

  /// No description provided for @sheetColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get sheetColor;

  /// No description provided for @sheetImportAfterCreate.
  ///
  /// In en, this message translates to:
  /// **'Import PDFs after creating…'**
  String get sheetImportAfterCreate;

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

  /// No description provided for @createdHud.
  ///
  /// In en, this message translates to:
  /// **'Created “{name}”'**
  String createdHud(String name);

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

  /// No description provided for @mapEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Highlight a sentence in the source and it becomes a card under the selected topic.'**
  String get mapEmptyMessage;

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
