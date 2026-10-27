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
  static const double excerpt = 6;
  static const double page = 3;
  static const double sheet = 22;
  static const double field = 8;
}

abstract final class MMSizes {
  static const double mapExportNodeWidth = 240;
  static const double mapExportCanvasPadding = 72;
  static const double mapExportImageFallbackHeight = 120;
  static const double mapExportSheetWidth = 560;
  static const double mapExportPreviewHeight = 180;

  /// Keep the excerpt-target hint clear of the map view controls.
  static const double mapViewControlsReservedWidth = 380;
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
  static const double segmented = 28;
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
  static const Size windowMinSize = Size(960, 600);
}
