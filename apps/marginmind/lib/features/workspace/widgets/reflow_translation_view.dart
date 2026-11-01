import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../reader_compare.dart';
import '../reader_translation.dart';
import '../reader_paragraphs.dart';
import '../reflow_session.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'reader_compare_controls.dart';
import '../full_translation.dart';
import 'full_translation_capsule.dart';
import 'full_translation_strip.dart';

/// A lazy paragraph list centered on the source paragraph. Both directions use
/// source identities, so translation length never changes the correspondence.
class ReflowTranslationView extends ConsumerStatefulWidget {
  const ReflowTranslationView({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<ReflowTranslationView> createState() => _ReflowTranslationViewState();
}

class _ReflowTranslationViewState extends ConsumerState<ReflowTranslationView> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  GlobalKey _center = GlobalKey();
  final _keys = <String, GlobalKey>{};
  int _index = 0, _epoch = 0;
  bool _rightInput = false;
  String? _identity;
  ReaderTranslationController get controller => ref.read(readerTranslationProvider(widget.studySetId).notifier);

  void _follow(TextReadingPosition? position, ReaderTranslationState state) {
    if (_rightInput || position == null || ref.read(readerCompareProvider(widget.studySetId))?.sync != true) return;
    final paragraph = paragraphAt(state.paragraphs, position);
    if (paragraph == null || paragraph.index == _index) return;
    setState(() {
      _index = paragraph.index;
      _center = GlobalKey();
      _keys.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _observe() {
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    final state = ref.read(readerTranslationProvider(widget.studySetId));
    if (!_rightInput || viewport == null) return;
    TranslationParagraph? first;
    var best = double.infinity;
    for (final p in state.paragraphs) {
      final box = _keys[p.fingerprint]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final y = viewport.globalToLocal(box.localToGlobal(Offset.zero)).dy;
      if (y + box.size.height <= 0 || y >= viewport.size.height) continue;
      if (y < best) {
        first = p;
        best = y;
      }
    }
    final p = first;
    if (p == null) return;
    controller.prioritize([p.index], p.index);
    if (ref.read(readerCompareProvider(widget.studySetId))?.sync != true) return;
    final position = paragraphPosition(p) as TextReadingPosition;
    final session = ref.read(reflowSessionProvider((widget.studySetId, p.documentId)));
    if (session.position != null && sameSourcePosition(session.position!, position)) return;
    unawaited(session.jump(position, remember: false));
  }

  @override
  void dispose() {
    _epoch++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerTranslationProvider(widget.studySetId));
    final pair = ref.watch(readerCompareProvider(widget.studySetId))!;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final document = workspace.content.document(pair.leftDocumentId)!;
    final targetLang = (pair.right as AiCompareTarget).targetLang;
    final fullState = ref.watch(fullTranslationProvider((widget.studySetId, document.id, targetLang)));
    final identity = '${document.id}:${document.revision}:${(pair.right as AiCompareTarget).targetLang}';
    if (_identity != identity) {
      _identity = identity;
      _index = 0;
      _keys.clear();
      _center = GlobalKey();
      _rightInput = false;
    }
    ref.listen(translationSourceInputProvider(widget.studySetId), (_, _) {
      _rightInput = false;
      _epoch++;
    });
    ref.listen(readerTranslationProvider(widget.studySetId).select((s) => (s.textPosition, s.loading)), (_, _) {
      final epoch = _epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _epoch) {
          _follow(
            ref.read(readerTranslationProvider(widget.studySetId)).textPosition,
            ref.read(readerTranslationProvider(widget.studySetId)),
          );
        }
      });
    });
    final l = context.l10n, c = context.mmColors;
    final style = ref.watch(settingsProvider).readerStyle;
    final reading = ref.watch(settingsProvider).reading(document.format);
    Widget paragraph(int index) {
      final p = state.paragraphs[index];
      final value = state.values[p.fingerprint];
      return MouseRegion(
        key: _keys.putIfAbsent(p.fingerprint, GlobalKey.new),
        onEnter: (_) => controller.hover(p.fingerprint),
        onExit: (_) => controller.hover(null),
        child: Container(
          key: ValueKey('translation-paragraph-$index'),
          constraints: const BoxConstraints(minHeight: MMSizes.touchTarget),
          padding: const EdgeInsets.symmetric(vertical: MMSpacing.l, horizontal: MMSpacing.xl),
          color: state.hovered == p.fingerprint ? c.accentTint : null,
          child: value == null
              ? Semantics(
                  button: true,
                  label: l.selectionTranslate,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _rightInput = true;
                      controller.prioritize([p.index], p.index);
                      if (pair.sync) {
                        unawaited(
                          ref
                              .read(reflowSessionProvider((widget.studySetId, document.id)))
                              .jump(paragraphPosition(p) as TextReadingPosition, remember: false),
                        );
                      }
                    },
                    child: Text(p.text, style: context.mmText.body.copyWith(color: c.secondaryLabel)),
                  ),
                )
              : SelectableText(
                  value,
                  style: MMTypography.readingBody.copyWith(
                    color: style.inkColor,
                    fontSize: MMReaderTypography.fontSizes[reading.size],
                    height: MMReaderTypography.lineHeights[reading.lineHeight],
                    fontWeight: p.heading ? FontWeight.w600 : FontWeight.normal,
                  ),
                  contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editable.contextMenuAnchors,
                    buttonItems: [
                      ...editable.contextMenuButtonItems,
                      ContextMenuButtonItem(
                        label: l.excerptAction,
                        onPressed: () async {
                          final selected = editable.textEditingValue.selection
                              .textInside(editable.textEditingValue.text)
                              .trim();
                          editable.hideToolbar();
                          if (selected.isEmpty) return;
                          try {
                            final notice = await workspace.excerptSource(
                              p.documentId,
                              SourceSelection.text([p.textAnchor!], text: selected),
                              ref.read(workspaceProvider(widget.studySetId)).color,
                            );
                            if (context.mounted) showNotice(context, notice, rootTitle: '');
                          } catch (_) {
                            if (context.mounted) MMHud.show(context, l.somethingWentWrong);
                          }
                        },
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return ColoredBox(
      color: style.paperColor,
      child: Column(
        children: [
          SizedBox(
            height: context.mmTouch ? MMSizes.touchTarget : MMSizes.readerCompareHeader,
            child: Row(
              children: [
                const SizedBox(width: MMSpacing.s),
                Expanded(
                  child: ReaderCompareMenu(
                    studySetId: widget.studySetId,
                    document: document,
                    translationLanguage: (pair.right as AiCompareTarget).targetLang,
                  ),
                ),
                if (fullState.job != null)
                  Flexible(
                    child: FullTranslationCapsule(
                      studySetId: widget.studySetId,
                      documentId: document.id,
                      targetLang: targetLang,
                    ),
                  ),
                if (state.failed)
                  MMIconButton(icon: MMIcons.history, tooltip: l.assistantRetry, onPressed: controller.retry),
                MMIconButton(
                  icon: MMIcons.close,
                  tooltip: l.compareExit,
                  onPressed: ref.read(readerCompareProvider(widget.studySetId).notifier).exit,
                ),
              ],
            ),
          ),
          if (fullState.job != null)
            FullTranslationStrip(studySetId: widget.studySetId, documentId: document.id, targetLang: targetLang),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is UserScrollNotification && n.direction != ScrollDirection.idle) _rightInput = true;
                      if (n is ScrollEndNotification && _rightInput) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _observe();
                        });
                      }
                      return false;
                    },
                    child: Listener(
                      onPointerSignal: (_) => _rightInput = true,
                      onPointerDown: (_) => _rightInput = true,
                      child: CustomScrollView(
                        key: _viewport,
                        controller: _scroll,
                        center: _center,
                        slivers: [
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => paragraph(_index - i - 1),
                              childCount: _index,
                            ),
                          ),
                          SliverList(
                            key: _center,
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => paragraph(_index + i),
                              childCount: math.max(0, state.paragraphs.length - _index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
