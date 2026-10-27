import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../shared/l10n.dart';
import '../research_answer.dart';
import '../research_controller.dart';
import '../research_drafts.dart';
import '../research_intents.dart';
import '../research_settings.dart';
import 'research_widgets.dart';
import 'video_link_sheet.dart';
import 'save_note_sheet.dart';

/// Searches of other sites, opened in the browser. Their results are never
/// read or counted as sources.
List<(String, Uri)> externalSearches(Set<ResearchSourceKind> kinds, String query) => [
  if (kinds.contains(ResearchSourceKind.web)) ('Google', externalSearchLink(query)),
  if (kinds.contains(ResearchSourceKind.video)) ...[
    ('YouTube', Uri.https('www.youtube.com', '/results', {'search_query': query})),
    ('Bilibili', Uri.https('search.bilibili.com', '/all', {'keyword': query})),
  ],
  if (kinds.contains(ResearchSourceKind.image))
    ('Google Images', Uri.https('www.google.com', '/search', {'tbm': 'isch', 'q': query})),
];

/// The sources of a research (design 4.4): filtered by kind, each with its
/// reading state and access, merged reprints, and what can be done next.
class ResearchSources extends ConsumerWidget {
  const ResearchSources({super.key, required this.studySetId, required this.value, required this.panel});

  final String studySetId;
  final ResearchSessionState value;
  final ResearchPanelState panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final session = value.session;
    final drafts = value.drafts;
    final controller = ref.read(researchPanelProvider(studySetId).notifier);
    final running = panel.progress.containsKey(session.id) || session.status == 'running';
    final query = drafts.keywords.isNotEmpty ? drafts.keywords.join(' ') : session.question;
    final external = externalSearches(drafts.kinds, query);
    final kinds = {for (final s in value.sources) sourceKind(s.kind)};
    final shown = [
      for (final s in value.sources)
        if (panel.filter == null || sourceKind(s.kind) == panel.filter) s,
    ];
    final used = {
      for (final turn in AnswerTurn.all(session.history))
        for (final p in turn.points)
          for (final cite in p.cites) cite.sourceId,
    };
    final links = ref.read(researchLinksProvider);

    if (value.sources.isEmpty) {
      if (running) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.research)),
              const SizedBox(height: MMSpacing.m),
              Text(
                l.researchSearching(drafts.keywords.join(' · ')),
                style: t.footnote.copyWith(color: c.secondaryLabel),
              ),
            ],
          ),
        );
      }
      if (external.isEmpty) {
        final offline = drafts.method == ResearchMethod.offline;
        return MMEmptyState(
          icon: session.status == 'failed' ? MMIcons.offline : MMIcons.search,
          title: offline ? l.researchOfflineNoSources : l.researchNoSources,
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(MMSpacing.l),
      children: [
        if (drafts.kinds.contains(ResearchSourceKind.video))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MMButton(
              key: const ValueKey('save-video-link'),
              label: l.researchSaveVideo,
              onPressed: () => showVideoLinkSheet(context, studySetId, session.id),
            ),
          ),
        if (kinds.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: MMSpacing.m),
            child: Wrap(
              spacing: MMSpacing.xs,
              children: [
                ResearchChip(
                  key: const ValueKey('filter-all'),
                  label: l.researchFilterAll,
                  selected: panel.filter == null,
                  onTap: () => controller.setFilter(null),
                ),
                for (final kind in ResearchSourceKind.values)
                  if (kinds.contains(kind))
                    ResearchChip(
                      key: ValueKey('filter-${kind.name}'),
                      label: kindLabel(l, kind),
                      selected: panel.filter == kind,
                      onTap: () => controller.setFilter(kind),
                    ),
              ],
            ),
          ),
        for (final source in shown)
          _SourceItem(
            key: ValueKey('source-${source.id}'),
            studySetId: studySetId,
            value: value,
            source: source,
            used: used.contains(source.id) && session.mode == 'web',
            chosen: drafts.chosen.contains(source.id),
          ),
        for (final (site, url) in external) _ExternalItem(site: site, query: query, onTap: () => links.open(url)),
      ],
    );
  }
}

class _SourceItem extends ConsumerWidget {
  const _SourceItem({
    super.key,
    required this.studySetId,
    required this.value,
    required this.source,
    required this.used,
    required this.chosen,
  });

  final String studySetId;
  final ResearchSessionState value;
  final ResearchSource source;
  final bool used;
  final bool chosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final controller = ref.read(researchPanelProvider(studySetId).notifier);
    final sessionId = value.session.id;
    final kind = sourceKind(source.kind);
    final (state, stateColor) = readState(context, source.readState);
    final meta = (value.metadata[source.id] as Map?)?.cast<String, Object?>() ?? const {};
    final aliases = (meta['aliases'] as List? ?? const []).length;
    final merged = aliases > 1 ? aliases - 1 : 0;
    final openAccess = meta['openAccess'];
    final host = Uri.tryParse(source.url)?.host ?? '';
    final reading = ref.watch(
      researchPanelProvider(studySetId).select((s) => s.progress[sessionId]?.stage == ResearchStage.read),
    );
    final failed = source.readState == ResearchReadState.failed.name;
    final kindColor = switch (kind) {
      ResearchSourceKind.web => c.accent,
      ResearchSourceKind.paper => c.research,
      ResearchSourceKind.video => c.critical,
      ResearchSourceKind.image => c.positive,
    };
    Future<void> openReading() async {
      if (source.versions.isEmpty && !failed && kind != ResearchSourceKind.video) {
        await controller.read(source.id, sessionId: sessionId);
      }
      controller.openReading(source.id);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: MMSpacing.m),
      padding: const EdgeInsets.only(left: MMSpacing.m),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: chosen ? c.research : Colors.transparent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: kindColor, borderRadius: BorderRadius.circular(6)),
                child: Icon(kindIcon(kind), size: 12, color: Colors.white),
              ),
              const SizedBox(width: MMSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${value.numberOf(source.id)}. ${source.title.isEmpty ? source.url : source.title}',
                      style: t.headline,
                    ),
                    const SizedBox(height: MMSpacing.xxs),
                    Text(
                      [
                        if (host.isNotEmpty) host,
                        if (source.authors.isNotEmpty) source.authors.take(3).join(', '),
                        if (source.publishedAt != null) '${source.publishedAt!.year}',
                        if (source.doi != null) 'DOI ${source.doi}',
                      ].join(' · '),
                      style: t.footnote.copyWith(color: c.secondaryLabel),
                    ),
                    const SizedBox(height: MMSpacing.xs),
                    Wrap(
                      spacing: MMSpacing.xs,
                      runSpacing: MMSpacing.xs,
                      children: [
                        MMPill(state, color: stateColor),
                        if (value.pastedVersions(source.id).isNotEmpty) MMPill(l.researchPasted),
                        if (openAccess == true) MMPill(l.researchOpenAccess),
                        if (openAccess == false) MMPill(l.researchSubscription),
                        if (used) MMPill(l.researchUsedInAnswer, color: c.research),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (merged > 0)
            Padding(
              padding: const EdgeInsets.only(top: MMSpacing.xs),
              child: Text(l.researchMerged(merged), style: t.footnote.copyWith(color: c.secondaryLabel)),
            ),
          const SizedBox(height: MMSpacing.s),
          Wrap(
            spacing: MMSpacing.xs,
            runSpacing: MMSpacing.xs,
            children: [
              if (kind == ResearchSourceKind.video)
                _SmallButton(
                  icon: MMIcons.openExternal,
                  label: l.researchOpenPage,
                  onTap: () => ref.read(researchLinksProvider).open(Uri.parse(source.url)),
                )
              else
                _SmallButton(
                  key: ValueKey('read-${source.id}'),
                  icon: failed ? MMIcons.warning : MMIcons.interpret,
                  label: failed ? l.researchWhyFailed : l.researchRead,
                  busy: reading && source.versions.isEmpty && !failed,
                  onTap: () => unawaited(openReading()),
                ),
              if (kind == ResearchSourceKind.video)
                _SmallButton(
                  icon: MMIcons.add,
                  label: l.researchSaveLinkOnly,
                  onTap: () =>
                      showSaveNoteSheet(context, studySetId: studySetId, sessionId: sessionId, linkOnly: source),
                ),
              if (source.versions.isNotEmpty && kind != ResearchSourceKind.video)
                _SmallButton(
                  key: ValueKey('choose-${source.id}'),
                  icon: chosen ? MMIcons.check : MMIcons.add,
                  label: chosen ? l.researchChosen : l.researchChoose,
                  onTap: () => controller.toggleChosen(sessionId, source.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExternalItem extends StatelessWidget {
  const _ExternalItem({required this.site, required this.query, required this.onTap});

  final String site;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      key: ValueKey('external-$site'),
      onTap: onTap,
      semanticLabel: l.researchExternalSearch(site, query),
      builder: (context, s) => Container(
        margin: const EdgeInsets.only(bottom: MMSpacing.s),
        padding: const EdgeInsets.all(MMSpacing.s),
        decoration: BoxDecoration(
          color: s.hovered ? c.hover : null,
          borderRadius: BorderRadius.circular(MMRadii.field),
          border: Border.all(color: c.separator),
        ),
        child: Row(
          children: [
            Icon(MMIcons.openExternal, size: 13, color: c.icon),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: Text(l.researchExternalSearch(site, query), style: t.callout)),
            MMPill(l.researchExternal),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({super.key, required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: busy ? null : onTap,
      semanticLabel: label,
      builder: (context, s) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s + 2),
        decoration: BoxDecoration(
          color: s.hovered ? c.fill : c.quaternaryFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(dimension: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.research))
            else
              Icon(icon, size: 11, color: c.icon),
            const SizedBox(width: MMSpacing.xs),
            Text(label, style: context.mmText.footnote),
          ],
        ),
      ),
    );
  }
}
