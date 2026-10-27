import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../research_providers.dart';
import '../research_settings.dart';
import 'research_widgets.dart';

Future<void> showResearchSettingsSheet(BuildContext context) =>
    showMMSheet<void>(context: context, builder: (_) => const ResearchSettingsSheet(), width: 520);

/// Research settings (design 4.8): the AI service with its key (kept in the
/// Keychain), model and address, the limits of a web research, what the
/// launcher shows, and the web cache.
class ResearchSettingsSheet extends ConsumerStatefulWidget {
  const ResearchSettingsSheet({super.key});

  @override
  ConsumerState<ResearchSettingsSheet> createState() => _ResearchSettingsSheetState();
}

class _ResearchSettingsSheetState extends ConsumerState<ResearchSettingsSheet> {
  final _key = TextEditingController();
  late final _model = TextEditingController(text: ref.read(researchSettingsProvider).model);
  late final _endpoint = TextEditingController(text: ref.read(researchSettingsProvider).endpoint);
  bool _saving = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _setService(ResearchService service) async {
    final controller = ref.read(researchSettingsProvider.notifier);
    await controller.setService(service);
    if (!mounted) return;
    final settings = ref.read(researchSettingsProvider);
    setState(() {
      _key.clear();
      _model.text = settings.model;
    });
  }

  Future<void> _done() async {
    if (_saving) return;
    _saving = true;
    final l = context.l10n;
    final controller = ref.read(researchSettingsProvider.notifier);
    try {
      await controller.setModel(_model.text);
      await controller.setEndpoint(_endpoint.text);
      if (_key.text.trim().isNotEmpty) await controller.saveKey(_key.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) MMHud.show(context, l.researchKeyFailed, icon: MMIcons.close);
    } finally {
      _saving = false;
    }
  }

  Future<void> _removeKey() async {
    final l = context.l10n;
    try {
      await ref.read(researchSettingsProvider.notifier).saveKey('');
    } catch (_) {
      if (mounted) MMHud.show(context, l.researchKeyFailed, icon: MMIcons.close);
    }
  }

  Future<void> _clearCache() async {
    final l = context.l10n;
    final cache = ref.read(researchCacheProvider);
    try {
      await cache?.clear();
      if (mounted) MMHud.show(context, l.researchCacheCleared);
    } catch (_) {
      if (mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.close);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final settings = ref.watch(researchSettingsProvider);
    final controller = ref.read(researchSettingsProvider.notifier);
    final service = settings.service;
    Widget stepper(String label, int value, int max, ValueChanged<int> set) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MMIconButton(
          icon: MMIcons.zoomOut,
          tooltip: '−',
          size: 22,
          iconSize: 10,
          onPressed: value > 1 ? () => set(value - 1) : null,
        ),
        Text(label, style: t.body),
        MMIconButton(
          icon: MMIcons.zoomIn,
          tooltip: '+',
          size: 22,
          iconSize: 10,
          onPressed: value < max ? () => set(value + 1) : null,
        ),
      ],
    );

    return MMSheet(
      title: l.researchSettings,
      actions: [
        MMButton(
          key: const ValueKey('research-settings-done'),
          label: l.done,
          variant: MMButtonVariant.primary,
          onPressed: _done,
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MMFormRow(
                label: l.researchService,
                labelWidth: 110,
                child: Wrap(
                  spacing: MMSpacing.xs,
                  runSpacing: MMSpacing.xs,
                  children: [
                    for (final (s, label) in [
                      (ResearchService.none, l.researchServiceNone),
                      (ResearchService.anthropic, 'Anthropic'),
                      (ResearchService.openai, 'OpenAI'),
                      (ResearchService.compatible, l.researchServiceCompatible),
                    ])
                      ResearchChip(
                        key: ValueKey('service-${s.name}'),
                        label: label,
                        selected: s == service,
                        onTap: () => _setService(s),
                      ),
                  ],
                ),
              ),
              if (service != ResearchService.none) ...[
                if (service == ResearchService.compatible)
                  MMFormRow(
                    label: l.researchEndpoint,
                    labelWidth: 110,
                    child: MMTextField(
                      key: const ValueKey('research-endpoint'),
                      controller: _endpoint,
                      placeholder: 'https://…/v1/chat/completions',
                      semanticLabel: l.researchEndpoint,
                    ),
                  ),
                MMFormRow(
                  label: l.researchModel,
                  labelWidth: 110,
                  child: MMTextField(
                    key: const ValueKey('research-model'),
                    controller: _model,
                    placeholder: service == ResearchService.anthropic ? ResearchSettings.anthropicModel : null,
                    semanticLabel: l.researchModel,
                  ),
                ),
                MMFormRow(
                  label: l.researchApiKey,
                  labelWidth: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MMTextField(
                        key: const ValueKey('research-key'),
                        controller: _key,
                        obscureText: true,
                        placeholder: settings.keySaved ? '••••••••' : null,
                        semanticLabel: l.researchApiKey,
                      ),
                      if (settings.keySaved)
                        Padding(
                          padding: const EdgeInsets.only(top: MMSpacing.xs),
                          child: Row(
                            children: [
                              Icon(MMIcons.lock, size: 11, color: c.positive),
                              const SizedBox(width: MMSpacing.xs),
                              Expanded(
                                child: Text(l.researchKeySaved, style: t.footnote.copyWith(color: c.secondaryLabel)),
                              ),
                              MMButton(label: l.remove, variant: MMButtonVariant.plain, onPressed: _removeKey),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              MMFormRow(
                label: l.researchPaperSearch,
                labelWidth: 110,
                child: Text('OpenAlex', style: t.body),
              ),
              MMFormRow(
                label: l.researchLimits,
                labelWidth: 110,
                child: Wrap(
                  spacing: MMSpacing.s,
                  children: [
                    stepper(
                      l.researchLimitSearches(settings.searches),
                      settings.searches,
                      ResearchSettings.maxSearches,
                      (v) => controller.setLimits(searches: v),
                    ),
                    stepper(
                      l.researchLimitPages(settings.pages),
                      settings.pages,
                      ResearchSettings.maxPages,
                      (v) => controller.setLimits(pages: v),
                    ),
                    stepper(
                      l.researchLimitMinutes(settings.minutes),
                      settings.minutes,
                      ResearchSettings.maxMinutes,
                      (v) => controller.setLimits(minutes: v),
                    ),
                  ],
                ),
              ),
              MMFormRow(
                label: l.researchPrivacy,
                labelWidth: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MMCheckbox(
                      key: const ValueKey('research-show-context'),
                      value: settings.showContext,
                      label: l.researchShowContext,
                      color: c.research,
                      onChanged: controller.setShowContext,
                    ),
                    const SizedBox(height: MMSpacing.s),
                    // Always on: the address rules are not a preference.
                    MMCheckbox(value: true, label: l.researchBlockPrivate, color: c.research, onChanged: null),
                  ],
                ),
              ),
              MMFormRow(
                label: l.researchCache,
                labelWidth: 110,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: MMButton(
                    key: const ValueKey('research-clear-cache'),
                    label: l.researchClearCache,
                    onPressed: ref.watch(researchCacheProvider) == null ? null : _clearCache,
                  ),
                ),
              ),
              if (service != ResearchService.none && !settings.aiConfigured && settings.keySaved)
                ResearchNotice(text: l.researchServiceIncomplete),
            ],
          ),
        ),
      ),
    );
  }
}
