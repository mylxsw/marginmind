import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import 'map_export_scene.dart';
import '../workspace_controller.dart';

enum MapExportFormat { png, pdf, markdown, opml }

enum MapExportAppearance { light, dark, transparent }

Future<void> showMapExportSheet(BuildContext context, WidgetRef ref, String studySetId, {String? branchId}) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final state = ref.read(workspaceProvider(studySetId));
  final snapshot = controller.content;
  final stored = controller.content.map(state.activeMapId)?.title ?? '';
  final title = stored.isEmpty ? ref.read(studySetProvider(studySetId))?.title ?? context.l10n.appName : stored;
  // Capture the immutable snapshot and resolver before the modal route opens.
  await showMMSheet<void>(
    context: context,
    width: MMSizes.mapExportSheetWidth,
    builder: (_) => MapExportSheet(
      content: snapshot,
      mapId: state.activeMapId,
      title: title,
      branchId: branchId ?? state.selectedCardId,
      initialBranch: branchId != null,
      resolveImage: controller.imagePath,
    ),
  );
}

class MapExportSheet extends StatefulWidget {
  const MapExportSheet({
    super.key,
    required this.content,
    required this.mapId,
    required this.title,
    required this.resolveImage,
    this.branchId,
    this.initialBranch = false,
    this.save,
  });
  final StudySetContent content;
  final String mapId, title;
  final String? branchId;
  final bool initialBranch;
  final String Function(String) resolveImage;

  /// Test seam for cancellation and save failures, including system dialog errors.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  @override
  State<MapExportSheet> createState() => _MapExportSheetState();
}

class _MapExportSheetState extends State<MapExportSheet> {
  var _format = MapExportFormat.png;
  var _appearance = MapExportAppearance.light;
  var _scale = 2;
  late bool _branch = widget.initialBranch && widget.branchId != null;
  var _busy = false, _loading = true, _failed = false, _imageFailed = false;
  var _loadGeneration = 0;
  Map<String, ui.Image> _images = {};
  Map<String, Uint8List> _bytes = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final snapshot = _content;
    try {
      final ids = snapshot.nodes.where((n) => n.mapId == widget.mapId).map((n) => n.cardId).toSet();
      final (images, bytes) = await loadExportImages(
        snapshot.copyWith(cards: snapshot.cards.where((c) => ids.contains(c.id)).toList()),
        widget.resolveImage,
      );
      if (!mounted || generation != _loadGeneration) {
        for (final image in images.values) {
          image.dispose();
        }
        return;
      }
      setState(() {
        for (final image in _images.values) {
          image.dispose();
        }
        _images = images;
        _bytes = bytes;
        _loading = false;
        _failed = false;
        _imageFailed = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _imageFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  StudySetContent get _content => MapExporter.scope(widget.content, widget.mapId, _branch ? widget.branchId : null);
  bool get _visual => _format == MapExportFormat.png || _format == MapExportFormat.pdf;
  String get _title {
    if (!_branch) return widget.title;
    final card = widget.content.card(widget.branchId!);
    final research = widget.content.researchNote(card?.researchNoteId ?? '');
    return research?.title ?? (card?.title.isNotEmpty == true ? card!.title : widget.title);
  }

  MapExporter get _exporter {
    final l = context.l10n;
    return MapExporter(
      _content,
      mapId: widget.mapId,
      rootTitle: _title,
      source: (doc, page) => '${doc.title} · ${l.pageNumber(page)}',
      summary: (label) => label.isEmpty ? l.newSummaryLabel : l.exportSummary(label),
      relationsTitle: l.exportRelations,
      researchNoteLabel: l.exportResearchNote,
      sourceLabel: l.exportSource,
    );
  }

  MapExportScene _scene() => MapExportScene.build(
    content: _content,
    mapId: widget.mapId,
    title: _title,
    colors: _appearance == MapExportAppearance.dark ? MMColors.dark : MMColors.light,
    researchLabel: context.l10n.exportResearchNote,
    source: (doc, page) => '${doc.title} · ${context.l10n.pageNumber(page)}',
    transparent: _format == MapExportFormat.png && _appearance == MapExportAppearance.transparent,
    images: _images,
    imageBytes: _bytes,
  );

  Future<void> _save(MapExportScene scene) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final l = context.l10n;
    try {
      final extension = switch (_format) {
        MapExportFormat.markdown => 'md',
        _ => _format.name,
      };
      final Uint8List data;
      if (_format == MapExportFormat.png) {
        data = await scene.png(MapRasterPlan(scene.size, _scale.toDouble()));
      } else if (_format == MapExportFormat.pdf) {
        data = await const NativeMapExport().pdf(scene.vector);
      } else {
        final exporter = _exporter;
        data = Uint8List.fromList(utf8.encode(_format == MapExportFormat.opml ? exporter.opml() : exporter.markdown()));
      }
      final name = '${_title.replaceAll(RegExp(r'[/:\\\x00-\x1f]'), '-')}.$extension';
      final bool saved;
      if (widget.save case final save?) {
        saved = await save(name, data);
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [
            XTypeGroup(extensions: [extension]),
          ],
        );
        saved = location != null;
        if (location != null) await File(location.path).writeAsBytes(data, flush: true);
      }
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
        MMHud.show(context, l.exportedHud);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scene = _scene();
    final plan = MapRasterPlan(scene.size, _scale.toDouble());
    // A phone's bottom sheet: the controls share the width they have.
    final fill = MMBottomSheet.contains(context);
    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(top: MMSpacing.m),
      child: MMFormRow(label: label, child: child),
    );
    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.exportTitle,
        actions: [
          MMButton(label: l.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
          MMButton(
            label: l.exportAction,
            variant: MMButtonVariant.primary,
            onPressed: _busy || (_visual && (_loading || _imageFailed)) ? null : () => _save(scene),
          ),
        ],
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .65),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MMSegmentedControl<MapExportFormat>(
                  expand: fill,
                  segments: [
                    for (final format in MapExportFormat.values)
                      MMSegment(
                        value: format,
                        label: switch (format) {
                          MapExportFormat.markdown => 'Markdown',
                          MapExportFormat.opml => 'OPML',
                          _ => format.name.toUpperCase(),
                        },
                      ),
                  ],
                  value: _format,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _format = value;
                          _failed = false;
                          if (value == MapExportFormat.pdf && _appearance == MapExportAppearance.transparent) {
                            _appearance = MapExportAppearance.light;
                          }
                        }),
                ),
                const SizedBox(height: MMSpacing.m),
                if (_visual) ...[
                  Container(
                    height: MMSizes.mapExportPreviewHeight,
                    width: double.infinity,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: context.mmColors.quaternaryFill,
                      borderRadius: BorderRadius.circular(MMRadii.row),
                    ),
                    child: FittedBox(
                      child: SizedBox.fromSize(
                        size: scene.size,
                        child: CustomPaint(painter: scene),
                      ),
                    ),
                  ),
                  const SizedBox(height: MMSpacing.s),
                  Text(
                    _format == MapExportFormat.png
                        ? l.exportPixels('${plan.width}', '${plan.height}')
                        : l.exportCentimeters(
                            (scene.size.width / 72 * 2.54).toStringAsFixed(1),
                            (scene.size.height / 72 * 2.54).toStringAsFixed(1),
                          ),
                    style: context.mmText.footnote,
                  ),
                  if (_format == MapExportFormat.png && plan.reduced)
                    Text(l.exportReduced, style: context.mmText.footnote),
                  if (_format == MapExportFormat.png && plan.large) Text(l.exportLarge, style: context.mmText.footnote),
                ] else
                  SizedBox(
                    height: MMSizes.mapExportPreviewHeight,
                    child: SingleChildScrollView(
                      child: Text(
                        _format == MapExportFormat.markdown ? _exporter.markdown() : _exporter.opml(),
                        style: context.mmText.mono,
                      ),
                    ),
                  ),
                row(
                  l.exportRange,
                  MMSegmentedControl<bool>(
                    expand: fill,
                    segments: [
                      MMSegment(value: false, label: l.exportWholeMap),
                      if (widget.branchId != null) MMSegment(value: true, label: l.exportCurrentBranch),
                    ],
                    value: _branch,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _branch = value;
                              _loading = true;
                            });
                            _load();
                          },
                  ),
                ),
                if (_visual)
                  row(
                    l.exportAppearance,
                    MMSegmentedControl<MapExportAppearance>(
                      expand: fill,
                      segments: [
                        MMSegment(value: MapExportAppearance.light, label: l.exportLight),
                        MMSegment(value: MapExportAppearance.dark, label: l.exportDark),
                        if (_format == MapExportFormat.png)
                          MMSegment(value: MapExportAppearance.transparent, label: l.exportTransparent),
                      ],
                      value: _appearance,
                      onChanged: _busy ? null : (value) => setState(() => _appearance = value),
                    ),
                  ),
                if (_format == MapExportFormat.png)
                  row(
                    l.exportScale,
                    MMSegmentedControl<int>(
                      expand: fill,
                      segments: [
                        for (final scale in [1, 2, 3]) MMSegment(value: scale, label: '$scale×'),
                      ],
                      value: _scale,
                      onChanged: _busy ? null : (value) => setState(() => _scale = value),
                    ),
                  ),
                if (_loading && _visual || _busy) Text(l.exportLoading, style: context.mmText.footnote),
                if (_failed || (_imageFailed && _visual))
                  Row(
                    children: [
                      Expanded(child: Text(l.exportFailed, style: context.mmText.body)),
                      MMButton(
                        label: l.exportRetry,
                        onPressed: () {
                          setState(() {
                            _failed = false;
                            _loading = true;
                          });
                          _load();
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
