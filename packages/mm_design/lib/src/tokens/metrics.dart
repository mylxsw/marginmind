import 'package:flutter/widgets.dart';

/// 4-point spacing scale.
abstract final class MMSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 32;
}

/// Reader controls in mobile-redesign.html, measured below the safe status area.
abstract final class MMPhoneReaderLayout {
  static const double inset = 14;
  static const double modeWidth = 170;
  static const double bottom = 24;
  static const double top = 4;
  static const double gap = 10;
  static const double edge = 64;
  static const double immersiveEdge = 6;
  static const double scrubHeight = 74;
  static const double colorHeight = 46;
  static const double progress = 14;
  static const double dot = 8;
  static const double orbDot = 10;
  static const double toolInset = 6;
  static const double scrubInset = 18;
}

/// Shared iPad toolbar rhythm. Touch cells remain at least 44 pt wide;
/// spacing is added only between groups, never between adjacent tools.
abstract final class MMToolbarSpacing {
  static const double item = 0;
  static const double group = 8;
  static const double inset = 2;
}

/// Concentric radii: inner radius = outer radius − inset.
abstract final class MMRadii {
  static const double phoneReaderToolbar = 28;
  static const double phoneTabBar = 32;
  static const double phoneSheet = 38;
  static const double vocabularyCard = 10;
  static const double vocabularyPos = 4;
  static const double window = 24;
  static const double sidebar = 16;
  static const double row = 8;
  static const double capsule = 18;
  static const double capsuleButton = 15;
  static const double card = 12;
  static const double cover = 14;
  static const double dropdown = 14;
  static const double excerpt = 6;
  static const double page = 3;
  static const double sheet = 22;
  static const double field = 8;

  /// AI idea expansion: the popover's expansion section, and the direction
  /// tag or page chip on a draft node.
  static const double ideaSection = 10;
  static const double mapDraftTag = 4;

  /// Mind map from a document (GUL-600): the empty state's icon tile and the
  /// page chip of a generated topic (half its height). Diff tags reuse
  /// [mapDraftTag].
  static const double mapEmptyGlyph = 16;
  static const double mapSourceChip = 9;
}

abstract final class MMSizes {
  static const double phoneTabBarHeight = 64;
  static const double phoneTabBarHorizontalInset = 22;
  static const double phoneTabBarBottomInset = 26;
  static const double phoneTopControl = 44;
  static const double phoneToolOrb = 50;
  static const double phoneToolBarHeight = 56;
  static const double phonePageCapsuleHeight = 36;
  static const double phoneDrawerWidth = 328;
  static const double phoneSheetPadding = 8;
  static const double hairline = .5;
  static const double nodeStroke = 1;
  static const double paneHeaderHeight = 44;
  static const double desktopPaneHeaderHeight = 40;
  static const double tabletPaneHeaderHeight = 52;
  static const double phoneWorkspaceToolbarHeight = 50;
  static const double thumbDock = 56;
  static const Size thumbDockButton = Size(46, 44);
  static const double vocabularyChipHeight = 20;
  static const double vocabularyDot = 6;
  static const double vocabularyCardWidth = 360;
  static const double vocabularyHitCardWidth = 300;
  static const double vocabularyGlossSize = 10;
  static const double readerMaxFitZoom = 1.4;
  static const Size readerToolbarButton = Size(30, 26);
  static const double dropdownWidth = 240;
  static const double dropdownWideWidth = 340;
  static const double readerZoomMenuWidth = 280;
  static const double dropdownRowHeight = 30;
  static const double dropdownIcon = 14;
  static const double noticeBadge = 40;
  static const double readerCompareHeader = 34;
  static const double readerCompareDivider = .5;
  static const double readerCompareControl = 24;
  static const double readerCompareBottomGap = 28;
  static const double mapExportNodeWidth = 240;
  static const double mapExportCanvasPadding = 72;
  static const double mapExportImageFallbackHeight = 120;
  static const double mapExportSheetWidth = 560;
  static const double mapExportPreviewHeight = 180;
  static const double fullTranslationSheetWidth = 560;
  static const double fullTranslationPanelWidth = 372;

  /// Keep the excerpt-target hint clear of the map view controls.

  /// The map's structure and palette popover, and its thumbnails.
  static const double mapStylePopoverWidth = 300;
  static const double mapStructureThumbHeight = 52;
  static const double mapPaletteThumbHeight = 44;
  static const double readerSidebarWidth = 240;
  static const double readerSidebarMinWidth = 180;
  static const double readerSidebarMaxWidth = 360;
  static const double readerContentMinWidth = 240;
  static const double toolbarHeight = 56;
  static const double toolbarGroupHeight = 36;
  static const Size toolbarButton = Size(34, 30);

  /// Color dot in a floating toolbar: hit area width and dot diameter.
  static const double floatingToolbarColor = 26;
  static const double floatingToolbarDot = 14;
  static const double vocabularyListWidth = 340;
  static const double sidebarWidth = 236;
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 320;
  static const double sidebarInset = 8;
  static const double sidebarRow = 28;

  /// Space reserved at the top of the sidebar for the window buttons.
  static const double windowButtonsHeight = 28;

  /// Matches the macOS unified toolbar: window button centers sit at y=26.
  static const double windowTitlebarHeight = 52;
  // Window chrome keeps the native button center even when pane toolbars
  // use denser desktop spacing.
  static const double desktopWindowTitlebarHeight = windowTitlebarHeight;

  /// Width the window buttons need when the sidebar is hidden and they sit
  /// in the toolbar instead.
  static const double windowButtonsWidth = 78;
  static const double field = 28;
  static const double browserAddress = 30;
  static const double browserAddressTouch = 36;
  static const double browserProgressTrack = 2;
  static const double webConversionSheetWidth = 1080;

  /// Maximum width of an editable value in a settings row.
  static const double settingsFieldWidth = 245;
  static const double segmented = 28;
  static const double segmentedTouch = 36;
  static const double readerMinWidth = 420;

  /// Quiet full-width reader navigation: page badge above a thin track.
  static const double readerNavigationHeight = 64;
  static const double readerProgressTrack = 1;

  /// Right panel shared by research and card details; narrower when the
  /// window cannot also fit the sidebar beside the content.
  static const double rightPanelWidth = 400;
  static const double rightPanelNarrowWidth = 360;
  static const double mapMinWidth = 360;
  static const double dividerHitWidth = 8;

  /// Minimum hit area of a control under touch input.
  static const double touchTarget = 44;

  /// Painted tablet chrome is compact; its touch cells remain 44 points.
  static const double tabletControlVisual = 32;
  static const double tabletToolbarVisual = 36;
  static const double tabletToolbarIcon = 18;
  static const double tabletReaderNavigationHeight = 52;

  /// Smallest height of either pane when the source sits above the map.
  static const double paneMinHeight = 240;

  /// Width of the "Source | Map" switch in a compact window.
  static const double paneSwitchMaxWidth = 360;

  /// A phone's floating glass tab bar: capsule height (Android's is taller
  /// for its 48 dp hit areas), its gap to the screen sides and the smallest
  /// gap to the bottom edge when there is no home indicator inset.
  static const double tabBar = 60;
  static const double tabBarAndroid = 64;
  static const double tabBarMargin = 16;
  static const double tabBarBottomGap = 12;

  /// Bottom sheets of a compact window: the medium height as a fraction of
  /// the space below the safe area top, and the drag handle strip.
  static const double bottomSheetMedium = 0.62;
  static const double bottomSheetHandle = 20;

  /// Review rating button under touch.
  static const double reviewRatingTouch = 64;

  /// Row of an action sheet (context menu of a compact window).
  static const double actionSheetRow = 52;

  /// Toolbar search field in a compact window.
  static const double compactSearchWidth = 160;
  static const double noteProgressSheetWidth = 820;
  static const double noteSetupSheetWidth = 640;
  static const double noteExportSheetWidth = 900;
  static const double noteExportOptionsWidth = 280;
  static const double noteExportBodyHeight = 520;
  static const double noteShareSheetWidth = 860;
  static const double noteShareOptionsWidth = 250;
  static const double noteFormThumbHeight = 56;
  static const double noteTemplateCardWidth = 128;
  static const double noteColorDot = 14;
  static const double noteCoverageWidth = 340;
  static const Size windowMinSize = Size(960, 600);

  /// AI idea expansion (GUL-581): the popover's primary button and direction
  /// chips, the generating / review bar above the map view controls, its
  /// adjust menu and the whole-map plan card.
  static const double ideaPrimaryButton = 34;
  static const double ideaChip = 22;
  static const double ideaBar = 40;
  static const double ideaBarBottomInset = 64;
  static const double ideaAdjustWidth = 330;
  static const double ideaPlanWidth = 420;
  static const double ideaPlanTopInset = 64;
  static const double ideaPlanRow = 36;
  static const Size ideaStepperButton = Size(20, 22);

  /// Draft (ghost) topics: dashed outline, the hover controls above the
  /// draft, the placeholder shown before the first draft arrives, and the
  /// ring around the topic being expanded (halo pulses out to its max).
  static const double mapDraftBorder = 1;
  static const double mapDraftDash = 4;
  static const double mapDraftDashGap = 3;
  static const double mapDraftTag = 16;
  static const double mapDraftControls = 24;
  static const Size mapDraftControlButton = Size(22, 20);
  static const Size mapDraftPlaceholder = Size(120, 30);
  static const double mapWorkingRing = 2;
  static const double mapWorkingHalo = 6;
  static const double mapWorkingHaloMax = 10;

  /// Mind map from a document (GUL-600): the generate settings sheet and its
  /// form (settings pane, document and chapter rows), the empty state, the
  /// document banner, the update popover and diff panel, the source page
  /// chip and its document dot, the header's "new material" badge, the lock
  /// on protected topics and one segment of the reading progress.
  static const double mapGenerateSheetWidth = 760;
  static const double mapGenerateSheetHeight = 540;
  static const double mapGenerateTouchHeight = 640;
  static const double mapGenerateTwoPaneWidth = 640;
  static const double mapGenerateSettingsWidth = 280;
  static const double mapGenerateCompactPreviewHeight = 280;
  static const double mapGenerateLabelWidth = 96;
  static const double mapGenerateDocumentRow = 40;
  static const double mapGenerateChapterRow = 30;
  static const double mapGenerateRangeInset = 38;
  static const double mapGeneratePageFieldWidth = 64;
  static const double mapEmptyStateWidth = 620;
  static const double mapEmptySourceWidth = 320;
  static const double mapEmptySourceMinWidth = 224;
  static const double mapEmptySourceHeight = 76;
  static const double mapEmptyGlyph = 56;
  static const double mapDocumentBanner = 44;
  static const double mapDocumentBannerCompactWidth = 480;
  static const double mapFollowNotice = 34;
  static const double mapDocumentLegendLabelWidth = 96;
  static const double mapUpdatePopoverWidth = 560;
  static const double mapDiffPanelWidth = 340;
  static const double mapSourceChip = 18;
  static const double mapSourceDot = 6;
  static const double mapUpdateBadge = 7;
  static const double mapUpdateBadgeRing = 1.5;
  static const double mapProtectedBadge = 18;
  static const Size mapReadingStep = Size(16, 4);
}

/// Shared geometry for the source-anchored book reader.
abstract final class MMReaderLayout {
  static const double zoomStep = 1.2;
  static const double minZoom = .25;
  static const double maxZoom = 16;
  static const double measure = 680;
  static const double spreadMeasure = 600;
  static const double spreadMinWidth = 1000;
  static const double spreadGap = 64;
  static const double margin = 48;
  static const double marginCompact = 24;
  static const double topInset = 40;
  static const double topInsetCompact = 28;
  static const double scrollTopInset = 36;
  static const double scrollTopInsetCompact = 24;
  static const double turnZone = .25;
  static const double marginColumn = 220;
  static const double settingsWidth = 280;
  static const double thumbnailWidth = 112;
  static const double thumbnailHeight = 144;
}

/// Written study notes, shared by setup, reading and export surfaces.
abstract final class MMNoteLayout {
  static const double measure = 600;
  static const double gutter = 64;
  static const double gutterCompact = 20;
  static const double trailing = 56;
  static const double topInset = 30;
  static const double bottomInset = 120;
  static const double blockButton = 22;
  static const double blockGap = 12;
  static const double sectionTop = 30;
  static const double sectionBottom = 10;
  static const double aiRule = 2;
  static const double quoteBar = 3;
  static const double quoteIndent = 16;
  static const double tocWidth = 224;
  static const double tocMinWidth = 1000;
  static const double exportLabelMinWidth = 720;
  static const double barHeight = 44;
  static const double cornellCueWidth = 170;
  static const double answerBlur = 5;
}
