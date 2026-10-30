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

/// Concentric radii: inner radius = outer radius − inset.
abstract final class MMRadii {
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
}

abstract final class MMSizes {
  static const double vocabularyDot = 6;
  static const double vocabularyCardWidth = 360;
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

  /// Keep the excerpt-target hint clear of the map view controls.
  static const double mapViewControlsReservedWidth = 380;

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
  static const double sidebarWidth = 236;
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidth = 320;
  static const double sidebarInset = 8;
  static const double sidebarRow = 28;

  /// Space reserved at the top of the sidebar for the window buttons.
  static const double windowButtonsHeight = 28;

  /// Width the window buttons need when the sidebar is hidden and they sit
  /// in the toolbar instead.
  static const double windowButtonsWidth = 78;
  static const double field = 28;
  static const double browserAddress = 30;
  static const double browserAddressTouch = 36;
  static const double browserProgressTrack = 2;
  static const double webConversionSheetWidth = 640;
  static const double webConversionPreviewWidth = 200;
  static const double webConversionPreviewHeight = 260;
  static const double webConversionPreviewCompactHeight = 300;

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
  static const Size windowMinSize = Size(960, 600);
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
