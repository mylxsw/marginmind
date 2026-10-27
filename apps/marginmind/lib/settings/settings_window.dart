import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../app/navigation.dart';
import '../features/assistant/settings/model_settings.dart';
import '../features/assistant/settings/web_search_settings.dart';
import '../shared/l10n.dart';
import 'app_settings.dart';

enum SettingsTab { general, reading, models, webSearch }

/// The app's settings (⌘,): icon tabs over one scrolling page, like a macOS
/// settings window. Shown as a window-sized sheet; changes apply at once.
Future<void> showSettings(BuildContext context, {SettingsTab tab = SettingsTab.general}) => showMMSheet<void>(
  context: context,
  width: SettingsWindow.width,
  builder: (_) => SettingsWindow(initialTab: tab),
);

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key, this.initialTab = SettingsTab.general, this.showsGallery = kDebugMode});

  static const width = 680.0, height = 640.0;

  final SettingsTab initialTab;

  /// The component gallery is a development tool, like its menu item.
  final bool showsGallery;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late SettingsTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final tabs = [
      (SettingsTab.general, MMIcons.settings, l.settingsGeneral),
      (SettingsTab.reading, MMIcons.reading, l.settingsReading),
      (SettingsTab.models, MMIcons.ai, l.settingsModels),
      (SettingsTab.webSearch, MMIcons.web, l.settingsWebSearch),
    ];
    final available = MediaQuery.sizeOf(context).height - MMSizes.toolbarHeight - 24;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('settings-window'),
        height: SettingsWindow.height.clamp(320, available < 320 ? 320 : available).toDouble(),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.canvas,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          border: Border.all(color: c.hairline, width: .5),
          boxShadow: c.sheetShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: c.windowBackground,
                border: Border(bottom: BorderSide(color: c.separator)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: MMSpacing.s,
                    top: MMSpacing.s,
                    child: MMIconButton(
                      key: const ValueKey('settings-close'),
                      icon: MMIcons.close,
                      iconSize: 12,
                      size: 24,
                      tooltip: l.closePanel,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (tab, icon, label) in tabs)
                          _Tab(
                            key: ValueKey('settings-tab-${tab.name}'),
                            icon: icon,
                            label: label,
                            selected: tab == _tab,
                            onPressed: () => setState(() => _tab = tab),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                SettingsTab.general => _GeneralPage(showsGallery: widget.showsGallery),
                SettingsTab.reading => const _ReadingPage(),
                SettingsTab.models => const ModelSettingsPage(),
                SettingsTab.webSearch => const WebSearchSettingsPage(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({super.key, required this.icon, required this.label, required this.selected, required this.onPressed});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      semanticLabel: label,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        width: 76,
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: MMSpacing.xxs),
        decoration: BoxDecoration(
          color: selected ? c.selectedRow : (s.hovered ? c.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(MMRadii.row),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? c.accent : c.icon),
            const SizedBox(height: MMSpacing.xxs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.footnote.copyWith(color: selected ? c.accent : c.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// One settings page: a centered 520pt column on the canvas.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.icon, this.iconGradient, this.title, required this.children});

  /// The page's icon and name above its groups (Models, Web Search).
  final IconData? icon;
  final List<Color>? iconGradient;
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.xl, MMSpacing.l, MMSpacing.xxl),
    children: [
      Center(
        child: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null && title != null) ...[
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: iconGradient ?? [context.mmColors.research, context.mmColors.research],
                      ),
                    ),
                    child: Icon(icon, size: 28, color: Colors.white),
                  ),
                ),
                const SizedBox(height: MMSpacing.s),
                Center(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title!,
                      style: context.mmText.title3.copyWith(fontSize: 17, color: context.mmColors.label),
                    ),
                  ),
                ),
                const SizedBox(height: MMSpacing.s),
              ],
              ...children,
            ],
          ),
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
          ],
        ),
      ],
    );
  }
}
