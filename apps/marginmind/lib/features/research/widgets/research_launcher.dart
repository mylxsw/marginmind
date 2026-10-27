import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../research_controller.dart';
import '../research_intents.dart';
import '../research_origin.dart';
import '../research_providers.dart';
import '../research_settings.dart';
import 'research_settings_sheet.dart';
import 'research_widgets.dart';

/// Opens the research launcher beside [anchor] (global coordinates; the top
/// of the window when null). Nothing is requested until the user starts.
Future<void> showResearchLauncher(
  BuildContext context, {
  required String studySetId,
  required ResearchOrigin origin,
  ResearchIntent? intent,
  Rect? anchor,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierColor: Colors.transparent,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  transitionDuration: MMMotion.quick,
  pageBuilder: (dialogContext, _, _) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(dialogContext).pop()},
    child: CustomSingleChildLayout(
      delegate: _LauncherLayout(anchor),
      child: ResearchLauncher(studySetId: studySetId, origin: origin, intent: intent),
    ),
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
);

class _LauncherLayout extends SingleChildLayoutDelegate {
  _LauncherLayout(this.anchor);

  final Rect? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: ResearchLauncher.width,
    maxHeight: (constraints.maxHeight - MMSizes.toolbarHeight - MMSpacing.l).clamp(200, double.infinity),
  );

  /// Below the anchor when it fits, else above it, else as low as fits;
  /// always inside the window.
  @override
  Offset getPositionForChild(Size size, Size child) {
    const margin = MMSpacing.s;
    final a = anchor;
    if (a == null) return Offset((size.width - child.width) / 2, MMSizes.toolbarHeight + margin);
    final x = (a.center.dx - child.width / 2).clamp(margin, size.width - child.width - margin);
    var y = a.bottom + margin;
    if (y + child.height > size.height - margin) {
      y = a.top - margin - child.height;
      if (y < MMSizes.toolbarHeight) y = size.height - child.height - margin;
    }
    return Offset(x, y.clamp(margin, size.height - child.height).toDouble());
  }

  @override
  bool shouldRelayout(_LauncherLayout old) => old.anchor != anchor;
}

/// The research launcher (design 4.1): where the research starts, an intent
/// (one recommended), the question, keywords and sources, the method and
/// the context that will be sent. Start (⌘↩) or keep it for later.
class ResearchLauncher extends ConsumerStatefulWidget {
  const ResearchLauncher({super.key, required this.studySetId, required this.origin, this.intent});

  static const width = 440.0;

  final String studySetId;
  final ResearchOrigin origin;
  final ResearchIntent? intent;

  @override
  ConsumerState<ResearchLauncher> createState() => _ResearchLauncherState();
}

class _ResearchLauncherState extends ConsumerState<ResearchLauncher> {
  late final ResearchIntent _recommended = recommendIntent(widget.origin.text, fromMap: widget.origin.fromMap);
  late ResearchIntent _intent = widget.intent ?? _recommended;
  final _question = TextEditingController();
  final _questionFocus = FocusNode();
  final _keywordInput = TextEditingController();
  late List<String> _keywords = suggestKeywords(widget.origin.text, fromMap: widget.origin.fromMap);
  late Set<ResearchSourceKind> _kinds = _intent.kinds;
  late ResearchMethod _method;
  late final Map<ResearchContextKind, bool> _context = {for (final p in widget.origin.parts) p.kind: p.on};
  bool _contextOpen = false;
  bool _join = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(researchSettingsProvider);
    _method = defaultMethod(_intent, ai: settings.aiConfigured, web: settings.webAvailable);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _question.text = _questionFor(_intent);
      _questionFocus.requestFocus();
      _question.selection = TextSelection.collapsed(offset: _question.text.length);
    });
  }

  @override
  void dispose() {
    _question.dispose();
    _questionFocus.dispose();
    _keywordInput.dispose();
    super.dispose();
  }

  String _questionFor(ResearchIntent intent) {
    final l = context.l10n;
    final term = researchTerm(widget.origin.text, fromMap: widget.origin.fromMap);
    final quote = widget.origin.text.replaceAll(RegExp(r'[。.]$'), '');
    return switch (intent) {
      ResearchIntent.explain => l.researchQuestionExplain(term),
      ResearchIntent.interpret => l.researchQuestionInterpret,
      ResearchIntent.verify =>
        !widget.origin.fromMap && quote.runes.length <= 40
            ? l.researchQuestionVerifyQuote(quote)
            : l.researchQuestionVerify,
      ResearchIntent.video => l.researchQuestionVideo(term),
      ResearchIntent.paper => l.researchQuestionPaper(term),
      ResearchIntent.deep => '',
      ResearchIntent.translate => l.researchQuestionTranslate,
    };
  }

  void _pickIntent(ResearchIntent intent) {
    final settings = ref.read(researchSettingsProvider);
    setState(() {
      _intent = intent;
      _kinds = intent.kinds;
      _method = defaultMethod(intent, ai: settings.aiConfigured, web: settings.webAvailable);
      _question.text = _questionFor(intent);
    });
    _questionFocus.requestFocus();
  }

  void _addKeyword() {
    final value = _keywordInput.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_keywords.contains(value)) _keywords = [..._keywords, value];
      _keywordInput.clear();
    });
  }

  /// "Label：text" lines of the parts switched on.
  String _contextText(AppLocalizations l) => [
    for (final p in widget.origin.parts)
      if (_context[p.kind] ?? p.on) '${contextLabel(l, p.kind)}：${p.text}',
  ].join('\n');

  ResearchLaunch _launch(AppLocalizations l) => ResearchLaunch(
    origin: widget.origin,
    intent: _intent,
    question: _question.text.trim(),
    method: _method,
    keywords: _method == ResearchMethod.offline ? const [] : _keywords,
    kinds: _method == ResearchMethod.offline ? const {} : _kinds,
    context: _method == ResearchMethod.search ? '' : _contextText(l),
  );

  Future<void> _start({required ResearchSession? running}) async {
    final l = context.l10n;
    if (_busy) return;
    if (_question.text.trim().isEmpty) {
      MMHud.show(context, l.researchNeedQuestion, icon: MMIcons.info);
      _questionFocus.requestFocus();
      return;
    }
    _busy = true;
    final panel = ref.read(researchPanelProvider(widget.studySetId).notifier);
    final navigator = Navigator.of(context);
    try {
      if (_join && running != null) {
        await panel.join(running.id, _contextText(l));
        panel.show(running.id);
        final hud = navigator.context;
        navigator.pop();
        if (hud.mounted) MMHud.show(hud, l.researchJoined);
        return;
      }
      final launch = _launch(l);
      navigator.pop();
      await panel.start(launch);
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
    } finally {
      _busy = false;
    }
  }

  Future<void> _later() async {
    final l = context.l10n;
    if (_busy || _question.text.trim().isEmpty) {
      if (_question.text.trim().isEmpty) MMHud.show(context, l.researchNeedQuestion, icon: MMIcons.info);
      return;
    }
    _busy = true;
    final hud = Navigator.of(context).context;
    try {
      await ref.read(researchPanelProvider(widget.studySetId).notifier).later(_launch(l));
      if (mounted) Navigator.of(context).pop();
      if (hud.mounted) MMHud.show(hud, l.researchSavedForLater);
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final settings = ref.watch(researchSettingsProvider);
    final running = ref
        .watch(researchSessionsProvider(widget.studySetId))
        .value
        ?.where((s) => s.status == 'running')
        .firstOrNull;
    final origin = widget.origin;
    final location = origin.fromMap
        ? [...origin.path.skip(1), origin.text].join(' › ')
        : '${origin.documentTitle} · ${l.pageNumber(origin.page)}';
    final parts = [
      for (final p in origin.parts)
        if (_context[p.kind] ?? p.on) p,
    ];
    final chars = parts.fold<int>(0, (n, p) => n + p.text.runes.length);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _start(running: running),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _start(running: running),
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          key: const ValueKey('research-launcher'),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(MMRadii.sheet - 6),
            border: Border.all(color: c.hairline, width: 0.5),
            boxShadow: c.sheetShadow,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MMSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(MMIcons.research, size: 14, color: c.research),
                    const SizedBox(width: MMSpacing.xs + 2),
                    Text(
                      origin.fromMap ? l.researchNode : l.researchSelection,
                      style: t.headline.copyWith(color: c.research),
                    ),
                    const SizedBox(width: MMSpacing.m),
                    Expanded(
                      child: Text(
                        location,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote.copyWith(color: c.secondaryLabel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MMSpacing.s + 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
                  decoration: BoxDecoration(
                    color: c.quaternaryFill,
                    borderRadius: BorderRadius.circular(MMRadii.field),
                  ),
                  child: Text(
                    origin.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: origin.fromMap ? t.headline : t.readingExcerpt,
                  ),
                ),
                if (running != null) ...[
                  const SizedBox(height: MMSpacing.m),
                  ResearchFieldLabel(l.researchRunningChoice),
                  ResearchRadio(
                    key: const ValueKey('launcher-as-new'),
                    selected: !_join,
                    label: l.researchAsNew,
                    onTap: () => setState(() => _join = false),
                  ),
                  ResearchRadio(
                    key: const ValueKey('launcher-join'),
                    selected: _join,
                    label: l.researchJoin,
                    detail: running.question,
                    onTap: () => setState(() => _join = true),
                  ),
                ],
                if (!_join) ...[
                  const SizedBox(height: MMSpacing.m),
                  _IntentGrid(intent: _intent, recommended: _recommended, onPick: _pickIntent),
                  const SizedBox(height: MMSpacing.m),
                  ResearchFieldLabel(l.researchQuestion),
                  MMTextField(
                    key: const ValueKey('launcher-question'),
                    controller: _question,
                    focusNode: _questionFocus,
                    maxLines: 4,
                    minLines: 2,
                    placeholder: _intent == ResearchIntent.deep ? l.researchQuestionPlaceholder : null,
                    semanticLabel: l.researchQuestion,
                  ),
                  if (_method != ResearchMethod.offline) ...[
                    const SizedBox(height: MMSpacing.m),
                    ResearchFieldLabel(l.researchKeywords),
                    Wrap(
                      spacing: MMSpacing.xs,
                      runSpacing: MMSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final k in _keywords)
                          ResearchChip(
                            label: k,
                            onRemove: () => setState(() => _keywords = [..._keywords]..remove(k)),
                            removeTooltip: l.remove,
                          ),
                        SizedBox(
                          width: 160,
                          child: MMTextField(
                            key: const ValueKey('launcher-keyword'),
                            controller: _keywordInput,
                            placeholder: l.researchAddKeyword,
                            semanticLabel: l.researchAddKeyword,
                            onSubmitted: (_) => _addKeyword(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MMSpacing.m),
                    ResearchFieldLabel(l.researchSourcesLabel),
                    Wrap(
                      spacing: MMSpacing.xs,
                      runSpacing: MMSpacing.xs,
                      children: [
                        for (final kind in ResearchSourceKind.values)
                          ResearchChip(
                            label: kindLabel(l, kind),
                            icon: kindIcon(kind),
                            selected: _kinds.contains(kind),
                            onTap: () => setState(
                              () => _kinds = _kinds.contains(kind) ? ({..._kinds}..remove(kind)) : {..._kinds, kind},
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: MMSpacing.m),
                  ResearchFieldLabel(l.researchMethod),
                  ResearchMethodPicker(
                    value: _method,
                    ai: settings.aiConfigured,
                    web: settings.webAvailable,
                    onChanged: (m) => setState(() => _method = m),
                  ),
                  const SizedBox(height: MMSpacing.xs + 2),
                  if (!settings.aiConfigured)
                    ResearchNotice(
                      icon: MMIcons.info,
                      text: l.researchNoAi,
                      action: l.researchSetUpAi,
                      onAction: () {
                        Navigator.of(context).pop();
                        unawaited(showResearchSettingsSheet(context));
                      },
                    )
                  else
                    Text(switch (_method) {
                      ResearchMethod.search => l.researchMethodSearchNote,
                      ResearchMethod.offline => l.researchMethodOfflineNote,
                      ResearchMethod.web => l.researchMethodWebNote(settings.searches, settings.pages),
                    }, style: t.footnote.copyWith(color: c.secondaryLabel)),
                  if (_method != ResearchMethod.search && settings.showContext) ...[
                    const SizedBox(height: MMSpacing.m),
                    _ContextBox(
                      open: _contextOpen,
                      summary: l.researchContextSummary(parts.map((p) => contextLabel(l, p.kind)).join(' + '), chars),
                      onToggle: () => setState(() => _contextOpen = !_contextOpen),
                      children: [
                        for (final p in origin.parts)
                          _ContextPartRow(
                            part: p,
                            on: _context[p.kind] ?? p.on,
                            onChanged: p.required ? null : (v) => setState(() => _context[p.kind] = v),
                          ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: MMSpacing.l),
                Row(
                  children: [
                    // Each side keeps its natural width when it fits; a
                    // narrow card shortens labels rather than overflowing.
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _join
                            ? const SizedBox.shrink()
                            : MMButton(label: l.researchLater, icon: MMIcons.later, onPressed: _later),
                      ),
                    ),
                    Text('⌘↩', style: t.footnote.copyWith(color: c.secondaryLabel)),
                    const SizedBox(width: MMSpacing.s),
                    Flexible(
                      child: MMButton(
                        key: const ValueKey('launcher-start'),
                        label: _join ? l.researchJoin : l.researchStart,
                        variant: MMButtonVariant.primary,
                        color: c.research,
                        onPressed: () => _start(running: running),
                      ),
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

class _IntentGrid extends StatelessWidget {
  const _IntentGrid({required this.intent, required this.recommended, required this.onPick});

  final ResearchIntent intent;
  final ResearchIntent recommended;
  final ValueChanged<ResearchIntent> onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - MMSpacing.xs * 3) / 4;
        return Wrap(
          spacing: MMSpacing.xs,
          runSpacing: MMSpacing.xs,
          children: [
            for (final i in ResearchIntent.values)
              SizedBox(
                width: width,
                height: 50,
                child: MMInteractive(
                  key: ValueKey('intent-${i.name}'),
                  selected: i == intent,
                  semanticLabel: intentLabel(l, i),
                  onTap: () => onPick(i),
                  builder: (context, s) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: MMMotion.quick,
                        decoration: BoxDecoration(
                          color: i == intent ? c.researchTint : (s.hovered ? c.hover : c.card),
                          borderRadius: BorderRadius.circular(MMRadii.field + 2),
                          border: Border.all(
                            color: i == intent ? c.research : c.separator,
                            width: i == intent ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(intentIcon(i), size: 14, color: i == intent ? c.research : c.icon),
                              const SizedBox(height: MMSpacing.xs),
                              Text(
                                intentLabel(l, i),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.footnote.copyWith(color: i == intent ? c.research : c.label),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i == recommended)
                        Positioned(
                          top: -6,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              l.researchRecommended,
                              style: t.footnote.copyWith(color: c.onAccent, fontSize: 9, height: 13 / 9),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ContextBox extends StatelessWidget {
  const _ContextBox({required this.open, required this.summary, required this.onToggle, required this.children});

  final bool open;
  final String summary;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.separator),
        borderRadius: BorderRadius.circular(MMRadii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMInteractive(
            key: const ValueKey('launcher-context'),
            onTap: onToggle,
            semanticLabel: summary,
            builder: (context, s) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
              child: Row(
                children: [
                  Icon(MMIcons.lock, size: 12, color: c.icon),
                  const SizedBox(width: MMSpacing.s),
                  Expanded(
                    child: Text(summary, style: t.callout.copyWith(fontWeight: FontWeight.w400)),
                  ),
                  Icon(open ? MMIcons.chevronUp : MMIcons.chevronDown, size: 11, color: c.icon),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(MMSpacing.m, 0, MMSpacing.m, MMSpacing.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
        ],
      ),
    );
  }
}

class _ContextPartRow extends StatelessWidget {
  const _ContextPartRow({required this.part, required this.on, required this.onChanged});

  final ResearchContextPart part;
  final bool on;

  /// Null: always sent.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return Padding(
      padding: const EdgeInsets.only(top: MMSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: MMSwitch(
              key: ValueKey('context-${part.kind.name}'),
              value: on,
              color: c.research,
              semanticLabel: contextLabel(l, part.kind),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: MMSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contextLabel(l, part.kind), style: t.subheadline.copyWith(color: c.secondaryLabel)),
                const SizedBox(height: MMSpacing.xxs),
                Text(
                  part.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: (part.required ? t.readingExcerpt : t.footnote).copyWith(
                    color: on ? c.label : c.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
