import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/navigation.dart';
import '../../shared/l10n.dart';

enum _Section { colors, typography, controls, feedback }

/// Live catalogue of mm_design (Help › Component Gallery, ⌥⌘G). Use it to
/// check tokens and components in both appearances while developing.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  _Section _section = _Section.colors;
  String _segment = 'map';
  bool _toolOn = true;
  MMAnnotationColor _color = MMAnnotationColor.yellow;
  Rect _selection = const Rect.fromLTWH(200, 96, 180, 22);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final names = {
      _Section.colors: l.galleryColors,
      _Section.typography: l.galleryTypography,
      _Section.controls: l.galleryControls,
      _Section.feedback: l.galleryFeedback,
    };
    final icons = {
      _Section.colors: MMIcons.appearance,
      _Section.typography: MMIcons.text,
      _Section.controls: MMIcons.grid,
      _Section.feedback: MMIcons.success,
    };
    return MMWindowScaffold(
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      sidebar: MMSidebar(
        children: [
          MMSidebarSection(
            title: l.galleryTitle,
            children: [
              for (final s in _Section.values)
                MMSidebarItem(
                  icon: icons[s]!,
                  label: names[s]!,
                  selected: s == _section,
                  onTap: () => setState(() => _section = s),
                ),
            ],
          ),
        ],
      ),
      toolbar: MMToolbar(
        title: l.galleryTitle,
        subtitle: l.gallerySubtitle,
        actions: [
          MMButton(label: l.back, icon: MMIcons.chevronLeft, onPressed: ref.read(navigationProvider.notifier).back),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 48),
        children: switch (_section) {
          _Section.colors => _colors(context),
          _Section.typography => _typography(context),
          _Section.controls => _controls(context),
          _Section.feedback => _feedback(context),
        },
      ),
    );
  }

  Widget _title(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(text, style: context.mmText.title3),
  );

  List<Widget> _colors(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final tokens = {
      'windowBackground': c.windowBackground,
      'readerBackground': c.readerBackground,
      'canvas': c.canvas,
      'card': c.card,
      'label': c.label,
      'secondaryLabel': c.secondaryLabel,
      'separator': c.separator,
      'fill': c.fill,
      'quaternaryFill': c.quaternaryFill,
      'accent': c.accent,
      'accentFill': c.accentFill,
      'accentTint': c.accentTint,
      'line': c.line,
    };
    Widget swatch(String name, Color color) => SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.separator, width: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, style: t.mono.copyWith(color: c.label)),
        ],
      ),
    );
    return [
      _title(context, 'MMColors'),
      Wrap(spacing: 16, runSpacing: 16, children: [for (final e in tokens.entries) swatch(e.key, e.value)]),
      _title(context, 'MMAnnotationColor'),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final a in MMAnnotationColor.values)
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 44,
                    decoration: BoxDecoration(color: a.color, borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: c.page, borderRadius: BorderRadius.circular(6)),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: context.l10n.colorName(a),
                            style: t.readingExcerpt.copyWith(
                              color: const Color(0xFF1D1D1F),
                              backgroundColor: a.highlight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _typography(BuildContext context) {
    final t = context.mmText;
    final styles = {
      'largeTitle': t.largeTitle,
      'title2': t.title2,
      'title3': t.title3,
      'headline': t.headline,
      'body': t.body,
      'callout': t.callout,
      'subheadline': t.subheadline,
      'footnote': t.footnote,
      'readingBody': t.readingBody.copyWith(color: t.body.color),
      'readingExcerpt': t.readingExcerpt,
      'mono': t.mono,
    };
    return [
      _title(context, 'MMTypography'),
      for (final e in styles.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(width: 160, child: Text(e.key, style: t.mono)),
              Expanded(child: Text('间隔重复利用的正是这一机制 · Spaced repetition', style: e.value)),
            ],
          ),
        ),
    ];
  }

  List<Widget> _controls(BuildContext context) {
    final l = context.l10n;
    return [
      _title(context, 'MMToolbarGroup · MMToolbarButton'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          MMToolbarGroup(
            children: [
              MMToolbarButton(icon: MMIcons.select, tooltip: l.toolSelect, onPressed: () {}),
              MMToolbarButton(
                icon: MMIcons.highlight,
                tooltip: l.toolHighlight,
                selected: _toolOn,
                onPressed: () => setState(() => _toolOn = !_toolOn),
              ),
              const MMToolbarDivider(),
              MMToolbarButton(icon: MMIcons.trash, tooltip: l.removeFromMap, onPressed: null),
            ],
          ),
          MMToolbarGroup(
            children: [
              MMToolbarButton(
                icon: MMIcons.sort,
                label: l.sortBy(l.sortRecent),
                tooltip: l.sortTooltip,
                onPressed: () {},
              ),
            ],
          ),
          MMToolbarSearchField(placeholder: l.search),
        ],
      ),
      _title(context, 'MMSegmentedControl'),
      Align(
        alignment: Alignment.centerLeft,
        child: MMSegmentedControl<String>(
          value: _segment,
          onChanged: (v) => setState(() => _segment = v),
          segments: [
            MMSegment(value: 'map', label: l.mapView),
            MMSegment(value: 'outline', label: l.outlineView),
          ],
        ),
      ),
      _title(context, 'MMButton'),
      Wrap(
        spacing: 12,
        children: [
          MMButton(label: l.create, variant: MMButtonVariant.primary, onPressed: () {}),
          MMButton(label: l.cancel, onPressed: () {}),
          MMButton(label: l.open, variant: MMButtonVariant.plain, onPressed: () {}),
          MMButton(label: l.create, variant: MMButtonVariant.primary, onPressed: null),
        ],
      ),
      _title(context, 'MMSearchField · MMTextField'),
      SizedBox(width: 280, child: MMSearchField(placeholder: l.search)),
      const SizedBox(height: 12),
      SizedBox(width: 280, child: MMTextField(placeholder: l.sheetNamePlaceholder)),
      _title(context, 'MMColorPicker'),
      Align(
        alignment: Alignment.centerLeft,
        child: MMColorPicker(selected: _color, onChanged: (v) => setState(() => _color = v), labelOf: l.colorName),
      ),
      _title(context, 'MMFloatingToolbar'),
      _floatingToolbar(context),
      _title(context, 'MMSidebarItem · MMBadge · MMCount'),
      SizedBox(
        width: 236,
        child: Column(
          children: [
            MMSidebarItem(
              icon: MMIcons.document,
              label: '学习的底层逻辑',
              selected: true,
              trailing: const MMCount(6),
              onTap: () {},
            ),
            MMSidebarItem(icon: MMIcons.review, label: l.review, trailing: const MMBadge('5'), onTap: () {}),
          ],
        ),
      ),
      _title(context, 'MMProgressBar'),
      const SizedBox(width: 280, child: MMProgressBar(value: 0.62)),
    ];
  }

  /// A draggable "selection" on a page; the toolbar follows it and flips or
  /// shifts at the edges.
  Widget _floatingToolbar(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MMRadii.card),
        child: ColoredBox(
          color: c.readerBackground,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final area = Offset.zero & constraints.biggest;
              void drag(DragUpdateDetails d) {
                final moved = _selection.shift(d.delta);
                final dx = moved.left.clamp(area.left, max(area.left, area.right - moved.width)) - moved.left;
                final dy = moved.top.clamp(area.top, max(area.top, area.bottom - moved.height)) - moved.top;
                setState(() => _selection = moved.shift(Offset(dx, dy)));
              }

              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: _selection,
                    child: GestureDetector(
                      key: const ValueKey('gallery-selection'),
                      onPanUpdate: drag,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _color.highlight,
                            borderRadius: BorderRadius.circular(MMRadii.page),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: MMFloatingToolbarLayout(
                      anchor: _selection,
                      child: MMFloatingToolbar(
                        children: [
                          for (final color in MMAnnotationColor.values)
                            MMFloatingToolbarColor(
                              color: color,
                              tooltip: l.colorName(color),
                              selected: color == _color,
                              onPressed: () => setState(() => _color = color),
                            ),
                          const MMToolbarDivider(),
                          MMToolbarButton(icon: MMIcons.highlight, tooltip: l.highlightAction, onPressed: () {}),
                          MMToolbarButton(icon: MMIcons.copy, tooltip: l.copyAction, onPressed: () {}),
                          MMToolbarButton(icon: MMIcons.addNote, tooltip: l.addNote, onPressed: () {}),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _feedback(BuildContext context) {
    final l = context.l10n;
    return [
      _title(context, 'MMHud · MMSheet'),
      Wrap(
        spacing: 12,
        children: [
          MMButton(label: l.galleryShowHud, onPressed: () => MMHud.show(context, l.galleryHudMessage)),
          MMButton(
            label: l.galleryShowSheet,
            onPressed: () => showMMSheet<void>(
              context: context,
              builder: (context) => MMSheet(
                title: l.newStudySet,
                actions: [
                  MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
                  MMButton(
                    label: l.create,
                    variant: MMButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
                child: MMFormRow(
                  label: l.sheetName,
                  child: MMTextField(placeholder: l.sheetNamePlaceholder, autofocus: true),
                ),
              ),
            ),
          ),
        ],
      ),
      _title(context, 'MMEmptyState'),
      SizedBox(
        height: 360,
        child: MMEmptyState(
          icon: MMIcons.studySet,
          actions: [
            MMButton(label: l.newStudySet, variant: MMButtonVariant.primary, onPressed: () {}),
            MMButton(label: l.openSample, onPressed: () {}),
          ],
        ),
      ),
    ];
  }
}
