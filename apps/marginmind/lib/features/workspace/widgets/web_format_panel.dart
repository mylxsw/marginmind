import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/settings_window.dart' show SettingsTab, showSettings;
import '../../../shared/l10n.dart';
import '../../assistant/assistant_services.dart';
import '../../assistant/settings/ai_task_settings.dart' show AiTaskFocusTask;
import '../../assistant/settings/ai_task_status.dart';
import '../../assistant/settings/model_route_picker.dart';
import '../../assistant/widgets/assistant_markdown.dart';
import '../web_format_runtime.dart';
import '../web_format_session.dart';

enum WebFormatTab { preview, edit, compare }

String _clock(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The opt-in row. The route decides availability; the sheet decides nothing
/// about models and only receives the result through [onRoute].
class WebFormatCard extends ConsumerWidget {
  const WebFormatCard({
    super.key,
    required this.enabled,
    required this.onEnabled,
    required this.model,
    required this.onModel,
    required this.onRoute,
    this.scope,
  });
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final ModelReference? model;
  final ValueChanged<ModelReference?> onModel;
  final ValueChanged<RoutingRowState?> onRoute;

  /// Size of the job, once the extraction is known.
  final ({int chars, int sections})? scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final row = ref.watch(webFormatRouteProvider(model)).value;
    WidgetsBinding.instance.addPostFrameCallback((_) => onRoute(row));
    final catalog = ref.watch(assistantServicesProvider).value;
    final ready = row != null && !routingIssueBlocks(row.issue);
    final on = enabled && ready;
    final local = row?.config?.capabilities.identity.protocol == ModelProtocol.ollamaChat;
    // Without a key the default service is as unusable as no model at all.
    final needsSetup = row == null || row.issue == RoutingIssue.unset || row.issue == RoutingIssue.secretUnavailable;
    void openSettings() => needsSetup
        ? showSettings(context, tab: SettingsTab.models)
        : showSettings(context, tab: SettingsTab.aiTasks, focus: const AiTaskFocusTask(TaskType.webFormat));
    final issue = needsSetup || ready ? null : routingIssueText(l, row.issue, failureCode: row.failureCode);
    return Container(
      key: const ValueKey('web-format-card'),
      padding: const EdgeInsets.all(MMSpacing.m),
      decoration: BoxDecoration(
        color: c.quaternaryFill,
        borderRadius: BorderRadius.circular(MMRadii.row),
        border: Border.all(color: on ? c.accent : c.hairline, width: on ? 1 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(MMIcons.ai, size: 18, color: c.accent),
              const SizedBox(width: MMSpacing.s),
              Expanded(child: Text(l.webFormatTitle, style: t.headline)),
              MMSwitch(value: on, onChanged: ready ? onEnabled : null, semanticLabel: l.webFormatTitle),
            ],
          ),
          const SizedBox(height: MMSpacing.s),
          Text(l.webFormatHint, style: t.bodySecondary),
          if (row != null && !ready) ...[
            const SizedBox(height: MMSpacing.s),
            Row(
              children: [
                if (issue != null) ...[Icon(MMIcons.warning, size: 13, color: c.critical), const SizedBox(width: 4)],
                Expanded(
                  child: Text(
                    issue ?? l.assistantSetupHint,
                    style: t.footnote.copyWith(color: issue == null ? c.secondaryLabel : c.critical),
                  ),
                ),
                MMButton(label: l.webFormatOpenSettings, variant: MMButtonVariant.plain, onPressed: openSettings),
              ],
            ),
          ],
          if (on) ...[
            const SizedBox(height: MMSpacing.s),
            Row(
              children: [
                Expanded(child: Text(l.webFormatModel, style: t.bodySecondary)),
                ModelRoutePicker(
                  label: row.effective == null || catalog == null
                      ? l.aiTasksNotSet
                      : routeModelLabel(catalog, row.effective!),
                  tone: model == null ? ModelRouteTone.inherited : ModelRouteTone.explicit,
                  groups: [
                    for (final service in catalog?.services ?? <AssistantService>[])
                      if (service.enabled && (service.protocol != ServiceProtocol.ollama || service.localEnabled))
                        ModelRouteGroup(service.name, [
                          for (final item in service.models)
                            if (item.enabled)
                              ModelRouteOption(model: ModelReference(service.id, item.id), label: item.displayName),
                        ]),
                  ],
                  selected: model,
                  onChanged: onModel,
                  followLabel: l.aiTasksUseSetting,
                  semanticLabel: l.webFormatModel,
                  semanticValue: row.modelLabel ?? '',
                  maxWidth: 200,
                ),
              ],
            ),
            const SizedBox(height: MMSpacing.s),
            Text(
              [
                if (scope != null) l.webFormatScope('${scope!.chars}', '${scope!.sections}'),
                local ? l.webFormatLocal : l.webFormatSendsTo(row.serviceLabel ?? ''),
              ].join(),
              key: const ValueKey('web-format-disclosure'),
              style: t.footnote.copyWith(color: c.secondaryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stages while running; the completeness result and sections afterward.
class WebFormatProgress extends StatelessWidget {
  const WebFormatProgress({
    super.key,
    required this.session,
    required this.onReveal,
    required this.onCompare,
    required this.onDiscard,
  });
  final WebFormatSession session;
  final ValueChanged<int> onReveal, onCompare;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final label = t.callout.copyWith(color: c.secondaryLabel);
    final sections = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (i, s) in session.sections.indexed) _row(context, i, s)],
    );
    if (session.running) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.webFormatProgressTitle, style: label),
          const SizedBox(height: MMSpacing.s),
          _stage(context, l.webFormatStageRead, done: session.sections.isNotEmpty, running: session.sections.isEmpty),
          _stage(context, l.webFormatStageSplit, done: session.sections.isNotEmpty, note: '${session.sections.length}'),
          _stage(
            context,
            l.webFormatStageFormat,
            done: !session.running,
            running: session.phase == WebFormatPhase.running && !session.checking,
            note: '${session.formattedCount}/${session.sections.length}',
          ),
          Padding(padding: const EdgeInsets.only(left: 24), child: sections),
          _stage(context, l.webFormatStageCheck, running: session.checking),
        ],
      );
    }
    final check = session.check;
    final reviews = [
      for (final (i, s) in session.sections.indexed)
        if (s.needsReview) (i, s),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (check != null) ...[
          Text(l.webFormatCheckTitle, style: label),
          const SizedBox(height: MMSpacing.s),
          Row(
            children: [
              Icon(
                check.complete ? MMIcons.check : MMIcons.warning,
                size: 13,
                color: check.complete ? c.positive : c.caution,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l.webFormatKept(
                    '${check.imagesKept}',
                    '${check.imagesTotal}',
                    '${check.linksKept}',
                    '${check.linksTotal}',
                    '${check.codeKept}',
                    '${check.codeTotal}',
                  ),
                  style: t.footnote.copyWith(color: c.secondaryLabel),
                ),
              ),
            ],
          ),
          for (final (i, s) in reviews) ...[const SizedBox(height: MMSpacing.s), _review(context, i, s)],
          const SizedBox(height: MMSpacing.l),
        ],
        Text(l.webFormatSections, style: label),
        const SizedBox(height: MMSpacing.xs),
        sections,
        if (session.edited) ...[
          const SizedBox(height: MMSpacing.s),
          Text(l.webFormatEditedNoRerun, style: t.footnote.copyWith(color: c.secondaryLabel)),
        ],
        const SizedBox(height: MMSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: MMButton(label: l.webFormatDiscardAction, variant: MMButtonVariant.plain, onPressed: onDiscard),
        ),
      ],
    );
  }

  Widget _review(BuildContext context, int index, WebFormatSection section) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final percent = section.check!.changePercent;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.caution.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            percent < 0
                ? l.webFormatShorter(section.title, '${-percent}')
                : l.webFormatLonger(section.title, '$percent'),
            style: t.footnote.copyWith(color: c.caution, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(percent < 0 ? l.webFormatShorterHint : l.webFormatLongerHint, style: t.footnote),
          Row(
            children: [
              MMButton(
                label: l.webFormatViewCompare,
                variant: MMButtonVariant.plain,
                onPressed: () => onCompare(index),
              ),
              MMButton(
                label: l.webFormatAcknowledge,
                variant: MMButtonVariant.plain,
                onPressed: () => session.acknowledge(index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context, String title, {bool done = false, bool running = false, String? note}) {
    final c = context.mmColors, t = context.mmText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MMSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: running
                ? const CupertinoActivityIndicator(radius: 7)
                : done
                ? Icon(MMIcons.check, size: 14, color: c.positive)
                : Center(child: _dot(c)),
          ),
          const SizedBox(width: MMSpacing.s),
          Expanded(child: Text(title, style: done || running ? t.body : t.bodySecondary)),
          if (note != null && (done || running)) Text(note, style: t.footnote.copyWith(color: c.secondaryLabel)),
        ],
      ),
    );
  }

  Widget _dot(MMColors c) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
  );

  Widget _row(BuildContext context, int index, WebFormatSection section) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final icon = switch (section.state) {
      WebFormatSectionState.done when section.needsReview => Icon(MMIcons.warning, size: 13, color: c.caution),
      WebFormatSectionState.done => Icon(MMIcons.check, size: 13, color: c.positive),
      WebFormatSectionState.running => const CupertinoActivityIndicator(radius: 6),
      WebFormatSectionState.failed => Icon(MMIcons.warning, size: 13, color: c.critical),
      _ => Center(child: _dot(c)),
    };
    final settled = section.formatted || section.state == WebFormatSectionState.running;
    return MMInteractive(
      semanticLabel: section.title,
      onTap: () => onReveal(index),
      builder: (context, state) => Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: section.state == WebFormatSectionState.running
              ? c.accentTint
              : state.hovered
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(width: 14, height: 14, child: icon),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: settled ? t.body : t.bodySecondary,
              ),
            ),
            if (session.finished && !session.edited && (state.hovered || context.mmTouchPlatform))
              MMButton(
                key: ValueKey('web-format-rerun-$index'),
                label: l.webFormatRerun,
                variant: MMButtonVariant.plain,
                onPressed: () => session.rerun(index),
              ),
          ],
        ),
      ),
    );
  }
}

/// Live and finished text. Scrolling back pauses following the output.
class WebFormatPane extends StatefulWidget {
  const WebFormatPane({
    super.key,
    required this.session,
    required this.mode,
    required this.tab,
    required this.onTab,
    required this.header,
    required this.resources,
    required this.pdf,
    required this.reveal,
    required this.onRevert,
  });
  final WebFormatSession session;
  final WebCaptureMode mode;
  final WebFormatTab tab;
  final ValueChanged<WebFormatTab> onTab;
  final Widget header;
  final Map<String, Uint8List> resources;

  /// The finished PDF preview, built by the sheet that owns printing.
  final WidgetBuilder pdf;

  /// Section to scroll to; set by the progress list.
  final ValueNotifier<int?> reveal;

  final VoidCallback onRevert;

  @override
  State<WebFormatPane> createState() => _WebFormatPaneState();
}

class _WebFormatPaneState extends State<WebFormatPane> {
  final _scroll = ScrollController();
  final _editor = TextEditingController();
  final _sectionKeys = <int, GlobalKey>{};
  bool _follow = true, _source = false, _narrow = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    widget.reveal.addListener(_reveal);
    _syncEditor();
  }

  @override
  void didUpdateWidget(WebFormatPane old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_changed);
      widget.session.addListener(_changed);
    }
    if (old.reveal != widget.reveal) {
      old.reveal.removeListener(_reveal);
      widget.reveal.addListener(_reveal);
    }
    if (old.tab != widget.tab) _syncEditor();
  }

  void _syncEditor() {
    if (widget.tab == WebFormatTab.edit && _editor.text != widget.session.markdown) {
      _editor.text = widget.session.markdown;
    }
  }

  void _changed() {
    if (!mounted) return;
    _syncEditor();
    setState(() {});
    if (_follow && widget.session.running) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  void _reveal() {
    final index = widget.reveal.value;
    if (index == null) return;
    setState(() => _follow = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionKeys[index]?.currentContext;
      if (target != null && target.mounted) Scrollable.ensureVisible(target, duration: MMMotion.standard);
      widget.reveal.value = null;
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    widget.reveal.removeListener(_reveal);
    _scroll.dispose();
    _editor.dispose();
    super.dispose();
  }

  bool _userScrolled(UserScrollNotification note) {
    if (widget.session.running && note.direction == ScrollDirection.forward && _follow) {
      setState(() => _follow = false);
    }
    return false;
  }

  Widget _image(String source, String alt) {
    final bytes = widget.resources[source];
    final c = context.mmColors;
    Widget missing() => Container(
      padding: const EdgeInsets.all(MMSpacing.s),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(MMIcons.image, size: 14, color: c.secondaryLabel),
          const SizedBox(width: 6),
          Text(alt.isEmpty ? context.l10n.webFormatImage : alt, style: context.mmText.footnote),
        ],
      ),
    );
    if (bytes == null) return missing();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MMSpacing.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Image.memory(bytes, errorBuilder: (_, _, _) => missing()),
      ),
    );
  }

  Widget _body(String text, {bool cursor = false, double size = 15}) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(size / 13)),
    child: AnswerBody(
      text: text,
      citations: const [],
      onCitation: (_) {},
      cursor: cursor,
      imageBuilder: _image,
      headingStyle: (level) =>
          (level <= 2 ? context.mmText.title3 : context.mmText.headline).copyWith(color: context.mmColors.label),
    ),
  );

  /// The extraction's raw HTML blocks read as plain rows in a preview.
  String _readable(String block) {
    if (!block.startsWith('<')) return block;
    return block
        .replaceAll(RegExp(r'</t[dh]>'), '　')
        .replaceAll(RegExp(r'</(tr|li)>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  Widget _section(int index) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final section = widget.session.sections[index];
    final key = _sectionKeys.putIfAbsent(index, GlobalKey.new);
    final child = switch (section.state) {
      WebFormatSectionState.failed => _failure(index, section),
      WebFormatSectionState.waiting when widget.session.running => const SizedBox.shrink(),
      WebFormatSectionState.waiting || WebFormatSectionState.source => Container(
        padding: const EdgeInsets.only(left: 10),
        margin: const EdgeInsets.only(bottom: MMSpacing.l),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.fill, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.webFormatSourceTag('${index + 1}'), style: t.footnote.copyWith(color: c.secondaryLabel)),
            const SizedBox(height: MMSpacing.xs),
            for (final row in section.comparison) ...[_body(_readable(row.text), size: 13), const SizedBox(height: 6)],
          ],
        ),
      ),
      WebFormatSectionState.running when section.output.isEmpty => Padding(
        padding: const EdgeInsets.only(bottom: MMSpacing.l),
        child: Row(
          children: [
            const CupertinoActivityIndicator(radius: 7),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: Text(l.webFormatWriting(section.title), style: t.bodySecondary)),
          ],
        ),
      ),
      _ when _source && widget.session.running => Padding(
        padding: const EdgeInsets.only(bottom: MMSpacing.l),
        child: Text(section.output, style: MMTypography.mono.copyWith(color: c.label, height: 1.6)),
      ),
      _ => Padding(
        padding: const EdgeInsets.only(bottom: MMSpacing.l),
        child: _body(section.output, cursor: section.state == WebFormatSectionState.running),
      ),
    };
    return KeyedSubtree(key: key, child: child);
  }

  Widget _failure(int index, WebFormatSection section) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    return Container(
      key: ValueKey('web-format-failed-$index'),
      margin: const EdgeInsets.only(bottom: MMSpacing.l),
      padding: const EdgeInsets.all(MMSpacing.m),
      decoration: BoxDecoration(
        color: c.critical.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(MMRadii.card),
        border: Border.all(color: c.critical, width: .5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(MMIcons.warning, size: 14, color: c.critical),
              const SizedBox(width: 6),
              Expanded(child: Text(l.webFormatSectionFailed('${index + 1}'), style: t.headline)),
            ],
          ),
          const SizedBox(height: 6),
          Text('${aiInvocationError(l, section.error!)} ${l.webFormatSectionFailedHint}', style: t.bodySecondary),
          const SizedBox(height: MMSpacing.s),
          Wrap(
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.xs,
            children: [
              MMButton(
                label: l.webRetry,
                variant: MMButtonVariant.primary,
                onPressed: () => widget.session.rerun(index),
              ),
              MMButton(label: l.webFormatUseSource, onPressed: () => widget.session.useSource(index)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _strip() {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final session = widget.session;
    if (session.running) {
      final active = session.activeIndex;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: MMSpacing.s,
            runSpacing: MMSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const CupertinoActivityIndicator(radius: 7),
              Text(
                session.checking
                    ? l.webFormatChecking
                    : active == null
                    ? l.webFormatPreparing
                    : l.webFormatProgress('${active + 1}', '${session.sections.length}'),
                style: t.headline,
              ),
              Text(
                l.webFormatOutputMeta('${session.outputChars}', _clock(session.elapsed)),
                style: t.footnote.copyWith(color: c.secondaryLabel),
              ),
              MMSegmentedControl<bool>(
                segments: [
                  MMSegment(value: false, label: l.webFormatViewLayout),
                  MMSegment(value: true, label: l.convertMarkdown),
                ],
                value: _source,
                onChanged: (value) => setState(() => _source = value),
              ),
            ],
          ),
          const SizedBox(height: MMSpacing.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: session.progress,
              minHeight: 2,
              color: c.accent,
              backgroundColor: c.quaternaryFill,
            ),
          ),
          const SizedBox(height: MMSpacing.s),
        ],
      );
    }
    final total = session.sections.length, done = session.formattedCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: MMSpacing.s),
      child: Wrap(
        spacing: MMSpacing.s,
        runSpacing: MMSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          MMSegmentedControl<WebFormatTab>(
            segments: [
              MMSegment(value: WebFormatTab.preview, label: l.webFormatTabPreview),
              MMSegment(value: WebFormatTab.edit, label: l.webFormatTabEdit),
              MMSegment(value: WebFormatTab.compare, label: l.webFormatTabCompare),
            ],
            value: widget.tab,
            onChanged: widget.onTab,
          ),
          if (done < total)
            Text(l.webFormatPartial('$done', '$total'), style: t.footnote.copyWith(color: c.caution))
          else
            Text(
              [
                l.webFormatDoneMeta('$total', '${session.outputChars}', _clock(session.elapsed)),
                if (session.edited) l.webFormatEditedMark,
              ].join(' · '),
              style: t.footnote.copyWith(color: c.secondaryLabel),
            ),
          if (!session.edited &&
              session.sections.any(
                (s) => s.state == WebFormatSectionState.waiting || s.state == WebFormatSectionState.failed,
              ))
            MMButton(label: l.webFormatResume, onPressed: session.resume),
        ],
      ),
    );
  }

  Widget _content() {
    final session = widget.session;
    final c = context.mmColors;
    if (session.running || widget.tab == WebFormatTab.preview) {
      if (session.finished && widget.mode == WebCaptureMode.original) return widget.pdf(context);
      final List<Widget> body;
      if (session.finished && widget.mode == WebCaptureMode.markdown) {
        body = [Text(session.markdown, style: MMTypography.mono.copyWith(color: c.label, height: 1.6))];
      } else if (session.edited) {
        body = [_body(session.markdown)];
      } else {
        body = [for (var i = 0; i < session.sections.length; i++) _section(i)];
      }
      return Stack(
        children: [
          NotificationListener<UserScrollNotification>(
            onNotification: _userScrolled,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                key: const ValueKey('web-format-scroll'),
                controller: _scroll,
                primary: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [widget.header, ...body]),
              ),
            ),
          ),
          if (session.running && !_follow)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: MMSpacing.s),
                child: MMButton(
                  label: context.l10n.webFormatBackToLatest,
                  onPressed: () {
                    setState(() => _follow = true);
                    _changed();
                  },
                ),
              ),
            ),
        ],
      );
    }
    return widget.tab == WebFormatTab.edit ? _edit() : _compare();
  }

  Widget _edit() {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final session = widget.session;
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.convertMarkdown, style: t.callout.copyWith(color: c.secondaryLabel)),
            ),
            if (session.edited)
              MMButton(label: l.webFormatRevert, variant: MMButtonVariant.plain, onPressed: widget.onRevert),
          ],
        ),
        const SizedBox(height: MMSpacing.xs),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(MMSpacing.m),
            decoration: BoxDecoration(
              color: c.quaternaryFill,
              borderRadius: BorderRadius.circular(MMRadii.row),
              border: Border.all(color: c.hairline, width: .5),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                key: const ValueKey('web-format-editor'),
                controller: _editor,
                expands: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: MMTypography.mono.copyWith(color: c.label, height: 1.65),
                decoration: InputDecoration.collapsed(hintText: null, hintStyle: t.bodySecondary),
                onChanged: session.edit,
              ),
            ),
          ),
        ),
      ],
    );
    if (_narrow) return editor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: editor),
        const SizedBox(width: MMSpacing.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: MMSizes.field,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l.webFormatLivePreview, style: t.callout.copyWith(color: c.secondaryLabel)),
                ),
              ),
              const SizedBox(height: MMSpacing.xs),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: SingleChildScrollView(primary: false, child: _body(session.markdown, size: 14)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compare() {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final session = widget.session;
    final narrow = _narrow;
    final head = t.callout.copyWith(color: c.secondaryLabel);
    Widget original(WebFormatSection section) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in section.comparison)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: row.removed
                ? Container(
                    key: const ValueKey('web-format-removed'),
                    color: c.critical.withValues(alpha: .1),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(decoration: TextDecoration.lineThrough, decorationColor: c.critical),
                      child: _body(_readable(row.text), size: 13),
                    ),
                  )
                : _body(_readable(row.text), size: 13),
          ),
      ],
    );
    Widget result(WebFormatSection section) => section.formatted
        ? _body(section.output, size: 13)
        : Text(l.webFormatNotFormatted, style: t.footnote.copyWith(color: c.secondaryLabel));
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        key: const ValueKey('web-format-compare'),
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!narrow)
              Row(
                children: [
                  Expanded(child: Text(l.webFormatSourceColumn, style: head)),
                  const SizedBox(width: MMSpacing.xl),
                  Expanded(
                    child: Text(session.edited ? l.webFormatResultColumnEdited : l.webFormatResultColumn, style: head),
                  ),
                ],
              ),
            for (final (i, section) in session.sections.indexed)
              KeyedSubtree(
                key: _sectionKeys.putIfAbsent(i, GlobalKey.new),
                child: Container(
                  margin: const EdgeInsets.only(top: MMSpacing.s),
                  padding: const EdgeInsets.only(top: MMSpacing.s),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.separator, width: .5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (section.needsReview)
                        Padding(
                          padding: const EdgeInsets.only(bottom: MMSpacing.s),
                          child: Wrap(
                            spacing: MMSpacing.s,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Icon(MMIcons.warning, size: 13, color: c.caution),
                              Text(
                                section.check!.changePercent < 0
                                    ? l.webFormatRemovedHint('${-section.check!.changePercent}')
                                    : l.webFormatAddedHint('${section.check!.changePercent}'),
                                style: t.footnote.copyWith(color: c.caution),
                              ),
                              MMButton(label: l.webFormatAcknowledge, onPressed: () => session.acknowledge(i)),
                            ],
                          ),
                        ),
                      if (narrow) ...[
                        Text(l.webFormatSourceColumn, style: head),
                        const SizedBox(height: MMSpacing.xs),
                        original(section),
                        const SizedBox(height: MMSpacing.s),
                        Text(l.webFormatResultColumn, style: head),
                        const SizedBox(height: MMSpacing.xs),
                        result(section),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: original(section)),
                            const SizedBox(width: MMSpacing.xl),
                            Expanded(child: result(section)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final error = widget.session.runError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _strip(),
        if (error != null)
          Container(
            key: const ValueKey('web-format-run-error'),
            margin: const EdgeInsets.only(bottom: MMSpacing.s),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.critical.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${aiInvocationError(l, error)} ',
                    style: t.footnote.copyWith(color: c.critical, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: l.webFormatInterruptedHint, style: t.footnote),
                ],
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _narrow = constraints.maxWidth < 560;
              return _content();
            },
          ),
        ),
      ],
    );
  }
}
