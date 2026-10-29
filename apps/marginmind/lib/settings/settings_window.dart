import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../app/navigation.dart';
import '../features/assistant/settings/model_settings.dart';
import '../features/assistant/settings/web_search_settings.dart';
import '../features/voice/voice_settings_page.dart';
import '../shared/l10n.dart';
import 'app_settings.dart';

enum SettingsTab { general, reading, models, webSearch, voice }

/// The app's settings (⌘,): a centered dialog in the main window's own
/// language — a floating glass sidebar of sections beside a titled,
/// scrolling page. Service forms use explicit Save actions.
Future<void> showSettings(BuildContext context, {SettingsTab tab = SettingsTab.general, bool? showsGallery}) =>
    showMMDialog<void>(
      context: context,
      builder: (_) => SettingsWindow(initialTab: tab, showsGallery: showsGallery ?? kDebugMode),
    );

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key, this.initialTab = SettingsTab.general, this.showsGallery = kDebugMode});

  static const size = Size(780, 560), minSize = Size(640, 440);

  /// Space kept between the dialog and the window edges.
  static const margin = 24.0;

  static const sidebarWidth = 196.0;

  final SettingsTab initialTab;

  /// The component gallery is a development tool, like its menu item.
  final bool showsGallery;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late SettingsTab _tab =
      MMPlatformCapabilities.current.externalCredentials ||
          [SettingsTab.general, SettingsTab.reading].contains(widget.initialTab)
      ? widget.initialTab
      : SettingsTab.general;

  /// [preferred], shrunk to fit [screen] less the margins; below [min] it
  /// gives up the margins first, and only a smaller window shrinks it more.
  static double _fit(double preferred, double min, double screen) {
    final floor = min < screen ? min : screen;
    final room = screen - SettingsWindow.margin * 2;
    return preferred.clamp(floor, room > floor ? room : floor).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final tabs = [
      (SettingsTab.general, MMIcons.settings, l.settingsGeneral),
      (SettingsTab.reading, MMIcons.reading, l.settingsReading),
      if (MMPlatformCapabilities.current.externalCredentials) (SettingsTab.models, MMIcons.ai, l.settingsModels),
      if (MMPlatformCapabilities.current.externalCredentials) (SettingsTab.webSearch, MMIcons.web, l.settingsWebSearch),
      if (MMPlatformCapabilities.current.externalCredentials) (SettingsTab.voice, MMIcons.microphone, l.settingsVoice),
    ];
    final title = tabs.firstWhere((t) => t.$1 == _tab).$3;
    final page = switch (_tab) {
      SettingsTab.general => _GeneralPage(showsGallery: widget.showsGallery),
      SettingsTab.reading => const _ReadingPage(),
      SettingsTab.models => const ModelSettingsPage(),
      SettingsTab.webSearch => const WebSearchSettingsPage(),
      SettingsTab.voice => const VoiceSettingsPage(),
    };
    // A compact window's bottom sheet: the sections switch above the page,
    // which takes the sheet's full height.
    if (MMBottomSheet.contains(context)) {
      return Material(
        type: MaterialType.transparency,
        child: SizedBox.expand(
          key: const ValueKey('settings-window'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(MMSpacing.m, MMSpacing.xs, MMSpacing.m, MMSpacing.s),
                child: MMSegmentedControl<SettingsTab>(
                  key: const ValueKey('settings-sections'),
                  expand: true,
                  segments: [for (final (tab, _, label) in tabs) MMSegment(value: tab, label: label)],
                  value: _tab,
                  onChanged: (tab) => setState(() => _tab = tab),
                ),
              ),
              Expanded(child: page),
            ],
          ),
        ),
      );
    }
    final screen = MediaQuery.sizeOf(context);
    const size = SettingsWindow.size, min = SettingsWindow.minSize;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('settings-window'),
        width: _fit(size.width, min.width, screen.width),
        height: _fit(size.height, min.height, screen.height),
        padding: const EdgeInsets.all(MMSpacing.s),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.windowBackground,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          border: Border.all(color: c.hairline, width: .5),
          boxShadow: c.sheetShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              title: l.settingsTitle,
              children: [
                for (final (tab, icon, label) in tabs)
                  MMSidebarItem(
                    key: ValueKey('settings-tab-${tab.name}'),
                    icon: icon,
                    label: label,
                    selected: tab == _tab,
                    onTap: () => setState(() => _tab = tab),
                  ),
              ],
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        const SizedBox(width: MMSpacing.l),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              key: const ValueKey('settings-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.mmText.title3.copyWith(color: c.label),
                            ),
                          ),
                        ),
                        MMIconButton(
                          key: const ValueKey('settings-close'),
                          icon: MMIcons.close,
                          iconSize: 13,
                          tooltip: '${l.closePanel}（Esc）',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: MMSpacing.xs),
                      ],
                    ),
                  ),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The section list: the main window's floating glass sidebar, without its
/// window buttons.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final reduce = MMAppearance.reduceTransparencyOf(context);
    const radius = BorderRadius.all(Radius.circular(MMRadii.sidebar));
    Widget panel = Container(
      decoration: BoxDecoration(
        color: reduce ? c.sidebarOpaque : c.sidebar,
        borderRadius: radius,
        border: Border.all(color: c.hairline, width: .5),
      ),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MMSpacing.s, 0, MMSpacing.s, 10),
            child: Semantics(
              header: true,
              child: Text(title, style: context.mmText.headline.copyWith(color: c.label)),
            ),
          ),
          for (final child in children) Padding(padding: const EdgeInsets.only(bottom: 2), child: child),
        ],
      ),
    );
    if (!reduce) panel = BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: panel);
    return SizedBox(
      key: const ValueKey('settings-sidebar'),
      width: SettingsWindow.sidebarWidth,
      child: ClipRRect(borderRadius: radius, child: panel),
    );
  }
}

/// One settings page: a centered column, at most 540pt wide.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(MMSpacing.m + 2, MMSpacing.xs, MMSpacing.m + 2, MMSpacing.xxl),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ],
  );
}

class _GeneralPage extends ConsumerWidget {
  const _GeneralPage({required this.showsGallery});

  final bool showsGallery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    return SettingsPage(
      children: [
        MMSettingsGroup(
          children: [
            MMSettingsRow(
              label: l.appearance,
              trailing: MMPopUpButton<AppearancePreference>(
                key: const ValueKey('settings-appearance'),
                value: settings.appearance,
                semanticLabel: l.appearance,
                onChanged: controller.setAppearance,
                items: [
                  (AppearancePreference.system, l.appearanceSystem),
                  (AppearancePreference.light, l.appearanceLight),
                  (AppearancePreference.dark, l.appearanceDark),
                ],
              ),
            ),
            MMSettingsRow(
              label: l.language,
              trailing: MMPopUpButton<LanguagePreference>(
                key: const ValueKey('settings-language'),
                value: settings.language,
                semanticLabel: l.language,
                onChanged: controller.setLanguage,
                items: [
                  (LanguagePreference.system, l.languageSystem),
                  (LanguagePreference.zh, '简体中文'),
                  (LanguagePreference.en, 'English'),
                ],
              ),
            ),
          ],
        ),
        if (showsGallery) ...[
          const SizedBox(height: MMSpacing.m),
          Align(
            alignment: Alignment.centerRight,
            child: MMButton(
              label: l.componentGallery,
              variant: MMButtonVariant.plain,
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(navigationProvider.notifier).showGallery();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadingPage extends ConsumerWidget {
  const _ReadingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final style = ref.watch(settingsProvider.select((s) => s.readerStyle));
    final direction = ref.watch(settingsProvider.select((s) => s.selectionTranslationDirection));
    return SettingsPage(
      children: [
        MMSettingsGroup(
          children: [
            MMSettingsRow(
              label: l.readerAppearance,
              trailing: MMPopUpButton<MMReaderStyle>(
                key: const ValueKey('settings-reader-style'),
                value: style,
                semanticLabel: l.readerAppearance,
                onChanged: ref.read(settingsProvider.notifier).setReaderStyle,
                items: [
                  (MMReaderStyle.white, l.readerStyleWhite),
                  (MMReaderStyle.dark, l.readerStyleDark),
                  (MMReaderStyle.paper, l.readerStylePaper),
                  (MMReaderStyle.green, l.readerStyleGreen),
                ],
              ),
            ),
            MMSettingsRow(
              label: l.selectionTranslationDirection,
              trailing: MMPopUpButton<SelectionTranslationDirection>(
                key: const ValueKey('settings-selection-translation'),
                value: direction,
                semanticLabel: l.selectionTranslationDirection,
                onChanged: ref.read(settingsProvider.notifier).setSelectionTranslationDirection,
                items: [
                  (SelectionTranslationDirection.automatic, l.selectionTranslationAutomatic),
                  (SelectionTranslationDirection.englishToChinese, l.selectionTranslationEnglishToChinese),
                  (SelectionTranslationDirection.chineseToEnglish, l.selectionTranslationChineseToEnglish),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
