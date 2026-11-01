import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/settings_save_actions.dart';
import '../../../shared/l10n.dart';
import '../assistant_routing.dart';
import '../assistant_services.dart';
import 'ai_task_status.dart';
import 'model_route_picker.dart';

/// Where Settings › AI Features opens: one feature's row, or every row using
/// a model. A new instance re-runs the highlight.
sealed class AiTaskFocus {
  const AiTaskFocus();
}

class AiTaskFocusTask extends AiTaskFocus {
  const AiTaskFocusTask(this.type);
  final TaskType type;
}

class AiTaskFocusModel extends AiTaskFocus {
  const AiTaskFocusModel(this.model);
  final ModelReference model;
}

/// Settings uses the same versioned contracts as production dispatch. Owner-bound
/// task handlers stay in their domain factories; only immutable specs are shared.
final aiTaskRoutingSpecsProvider = Provider<Map<TaskType, TaskSpec>>(
  (ref) => Map.unmodifiable({
    for (final spec in [
      selectionTranslationSpec,
      wordLookupSpec,
      titleGenerationSpec,
      ...assistantTaskSpecs,
      documentTranslationSpec,
      mapExpandSpec,
      mapGenerateSpec,
      studyNotesSpec,
    ])
      spec.type: spec,
  }),
);

/// A category default has no domain-specific capabilities. Individual feature
/// rows below it independently report their actual requirements.
TaskSpec _categorySettingsSpec(TaskType type) => TaskSpec(
  type: type,
  inputSchema: 'settings',
  resultSchema: 'settings',
  promptVersion: 'settings',
  schemaVersion: 'settings',
  completionRule: 'settings',
);

enum AiTaskSaveState { idle, saving, saved, failed, conflict }

/// The page's one draft: two defaults, heavy thinking and the function
/// bindings. Lives as long as the settings window, so switching sections
/// keeps it; only [save] writes, carrying the revision it was read at.
class AiTaskDraft extends ChangeNotifier {
  RoutingConfig? _base;
  final _defaults = <TaskCategory, ModelReference?>{};
  final _bindings = <TaskType, TaskModelBinding>{};
  ReasoningPolicy _heavyReasoning = ReasoningPolicy.auto;
  AiTaskSaveState _state = AiTaskSaveState.idle;

  RoutingConfig? get base => _base;
  bool get loaded => _base != null;
  AiTaskSaveState get state => _state;
  bool get saving => _state == AiTaskSaveState.saving;
  ModelReference? defaultModel(TaskCategory category) => _defaults[category];
  TaskModelBinding binding(TaskType type) => _bindings[type] ?? const TaskModelBinding.inherit();
  ReasoningPolicy get heavyReasoning => _heavyReasoning;
  bool get hasExplicit => TaskType.values.any((t) => binding(t).mode == TaskBindingMode.explicit);

  /// Takes the stored value unless edits (or a save) are pending: those keep
  /// their base revision so a stale save is refused, never merged.
  void adopt(RoutingConfig config) {
    if (_base != null && (dirty || saving || _state == AiTaskSaveState.conflict)) return;
    if (_base?.revision == config.revision && identical(_base?.document, config.document)) return;
    _load(config);
    notifyListeners();
  }

  /// Discards the draft for [config] (“Reload”, “Don't Save”).
  void reload(RoutingConfig config) {
    _load(config);
    _state = AiTaskSaveState.idle;
    notifyListeners();
  }

  void _load(RoutingConfig config) {
    _base = config;
    for (final category in TaskCategory.values) {
      _defaults[category] = config.defaultModel(category);
    }
    _bindings
      ..clear()
      ..addEntries(TaskType.values.map((t) => MapEntry(t, config.binding(t))));
    _heavyReasoning = config.heavyReasoning;
  }

  bool get dirty {
    final base = _base;
    if (base == null) return false;
    if (_heavyReasoning != base.heavyReasoning) return true;
    if (TaskCategory.values.any((c) => _defaults[c] != base.defaultModel(c))) return true;
    return TaskType.values.any((t) {
      final a = binding(t), b = base.binding(t);
      return a.mode != b.mode || a.model != b.model || a.reasoning != b.reasoning;
    });
  }

  void _edit(void Function() change) {
    if (saving) return;
    change();
    if (_state != AiTaskSaveState.conflict) _state = AiTaskSaveState.idle;
    notifyListeners();
  }

  void setDefault(TaskCategory category, ModelReference model) => _edit(() => _defaults[category] = model);
  void setHeavyReasoning(ReasoningPolicy value) => _edit(() => _heavyReasoning = value);
  void setBinding(TaskType type, TaskModelBinding binding) => _edit(() => _bindings[type] = binding);

  /// Every feature back to its class default; defaults and heavy thinking stay.
  void resetBindings() => _edit(() {
    for (final type in TaskType.values) {
      _bindings[type] = const TaskModelBinding.inherit();
    }
  });

  /// The draft as a routing document. Unchanged references keep their display
  /// snapshots; fields and task keys this version does not know survive.
  RoutingConfig toConfig({bool bindings = true}) {
    final base = _base!;
    final document = base.document;
    final baseDefaults = (document['defaults'] as Map?) ?? const {};
    final baseBindings = (document['bindings'] as Map?) ?? const {};
    final categories = {for (final c in TaskCategory.values) c.name};
    final types = {for (final t in TaskType.values) t.key};
    Map<String, dynamic> reference(ModelReference model, ModelReference? previous, Object? raw) =>
        model == previous && raw is Map ? Map<String, dynamic>.from(raw) : model.toJson();
    return RoutingConfig(
      document: {
        ...document,
        'defaults': <String, dynamic>{
          for (final entry in baseDefaults.entries)
            if (!categories.contains(entry.key)) entry.key as String: entry.value,
          for (final category in TaskCategory.values)
            if (_defaults[category] case final model?)
              category.name: reference(model, base.defaultModel(category), baseDefaults[category.name]),
        },
        'bindings': <String, dynamic>{
          if (bindings) ...{
            for (final entry in baseBindings.entries)
              if (!types.contains(entry.key)) entry.key as String: entry.value,
            for (final type in TaskType.values)
              if (binding(type) case TaskModelBinding(mode: TaskBindingMode.explicit, :final model?, :final reasoning))
                type.key: <String, dynamic>{
                  'mode': TaskBindingMode.explicit.name,
                  'model': reference(model, base.binding(type).model, (baseBindings[type.key] as Map?)?['model']),
                  if (reasoning != null) 'reasoning': reasoning.name,
                },
          },
        },
        'heavyReasoning': _heavyReasoning.name,
      },
    );
  }

  /// Writes the draft against the revision it was read at. A newer revision
  /// is a conflict (never overwritten); other failures keep the draft.
  Future<bool> save(Future<RoutingConfig> Function(RoutingConfig draft, int expectedRevision) persist) async {
    if (saving || _state == AiTaskSaveState.conflict) return false;
    if (!dirty) return true;
    _state = AiTaskSaveState.saving;
    notifyListeners();
    try {
      final saved = await persist(toConfig(), _base!.revision);
      _load(saved);
      _state = AiTaskSaveState.saved;
      return true;
    } on RoutingRevisionConflict {
      _state = AiTaskSaveState.conflict;
      return false;
    } catch (_) {
      _state = AiTaskSaveState.failed;
      return false;
    } finally {
      notifyListeners();
    }
  }
}

/// Saves only the revision-controlled routing document. The legacy catalog
/// default remains migration input, never a mirror of new task preferences.
Future<bool> saveAiTaskDraft(WidgetRef ref, AiTaskDraft draft) => draft.save((config, revision) async {
  await ref.read(assistantRoutingProvider.notifier).save(config, expectedRevision: revision);
  return ref.read(assistantRoutingProvider).requireValue;
});

/// A capability test of one model: running, or how it ended.

/// Settings › AI Features: the quick and heavy defaults, then each feature's
/// model. Rows show the model that will run; colour tells bound from inherited.
class AiTaskSettingsPage extends ConsumerStatefulWidget {
  const AiTaskSettingsPage({super.key, required this.draft, required this.onOpenModels, this.focus});

  final AiTaskDraft draft;
  final AiTaskFocus? focus;

  /// Switches to Settings › Models, opening [serviceId]'s card or the add-service list.
  final void Function({String? serviceId, bool addService}) onOpenModels;

  @override
  ConsumerState<AiTaskSettingsPage> createState() => _AiTaskSettingsPageState();
}

class _AiTaskSettingsPageState extends ConsumerState<AiTaskSettingsPage> {
  final _rows = <TaskType, RoutingRowState>{};
  final _defaultRows = <TaskCategory, RoutingRowState>{};
  final _pickers = <String, GlobalKey>{};
  final _focus = <String, FocusNode>{};
  final _rowKeys = <String, GlobalKey>{};
  Set<String> _highlighted = const {};
  Timer? _highlightTimer;
  AiTaskFocus? _pendingFocus;
  int _generation = 0;
  int? _catalogRevision;

  /// Capability profiles were read at least once / the last read failed.
  bool _profilesLoaded = false, _profilesFailed = false;
  static const _storeFailures = {'corruptCapabilityStore', 'unsupportedCapabilityStoreVersion'};

  AiTaskDraft get _draft => widget.draft;
  static String _defaultId(TaskCategory c) => 'default-${c.name}';

  GlobalKey _picker(String id) => _pickers.putIfAbsent(id, GlobalKey.new);
  GlobalKey _rowKey(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);
  FocusNode _node(String id) => _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'ai-task-$id'));

  @override
  void initState() {
    super.initState();
    _draft.addListener(_changed);
    _pendingFocus = widget.focus;
    unawaited(_inspect());
  }

  @override
  void didUpdateWidget(AiTaskSettingsPage old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      old.draft.removeListener(_changed);
      widget.draft.addListener(_changed);
    }
    if (!identical(old.focus, widget.focus) && widget.focus != null) {
      _pendingFocus = widget.focus;
      _applyFocusLater();
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_changed);
    _highlightTimer?.cancel();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    unawaited(_inspect());
  }

  /// Re-resolves every row against the draft. Older passes are discarded.
  Future<void> _inspect() async {
    if (!_draft.loaded) return;
    final generation = ++_generation;
    final resolver = ref.read(assistantModelResolverProvider);
    final specs = ref.read(aiTaskRoutingSpecsProvider);
    final config = _draft.toConfig(), defaults = _draft.toConfig(bindings: false);
    TaskRequest<Object?> request(TaskSpec spec) =>
        TaskRequest<Object?>(spec: spec, input: const {}, inputFingerprint: 'settings');
    final List<RoutingRowState> results;
    try {
      // Menus and thinking options read profiles synchronously; load them even
      // when no row resolves far enough to refresh them (nothing assigned yet).
      try {
        await ref.read(assistantCapabilityProfilesProvider).refresh();
      } catch (_) {
        // Optional model metadata is not a prerequisite for using the service.
      }
      // Resolve against the same draft; each feature retains its own contract.
      results = [
        for (final type in TaskType.values) await resolver.inspect(request(specs[type]!), config),
        for (final category in TaskCategory.values)
          await resolver.inspect(
            request(_categorySettingsSpec(TaskType.values.firstWhere((t) => t.category == category))),
            defaults,
          ),
      ];
    } catch (_) {
      // Keep the previous rows and the draft; the page offers a retry.
      if (mounted && generation == _generation) setState(() => _profilesFailed = _profilesLoaded = true);
      return;
    }
    if (!mounted || generation != _generation) return;
    final failed = results.any((r) => _storeFailures.contains(r.failureCode));
    setState(() {
      _profilesLoaded = true;
      _profilesFailed = failed;
      for (final (i, type) in TaskType.values.indexed) {
        _rows[type] = results[i];
      }
      for (final (i, category) in TaskCategory.values.indexed) {
        _defaultRows[category] = results[TaskType.values.length + i];
      }
    });
    _applyFocusLater();
  }

  void _applyFocusLater() => WidgetsBinding.instance.addPostFrameCallback((_) => _applyFocus());

  void _applyFocus() {
    final focus = _pendingFocus;
    if (!mounted || focus == null || !_draft.loaded || _rows.isEmpty) return;
    _pendingFocus = null;
    final ids = <String>[];
    switch (focus) {
      case AiTaskFocusTask(:final type):
        ids.add(type.key);
      case AiTaskFocusModel(:final model):
        for (final category in TaskCategory.values) {
          if (_draft.defaultModel(category) == model) ids.add(_defaultId(category));
        }
        for (final type in TaskType.values) {
          final binding = _draft.binding(type);
          final effective = binding.mode == TaskBindingMode.explicit
              ? binding.model
              : _draft.defaultModel(type.category);
          if (effective == model) ids.add(type.key);
        }
    }
    final quickUnset = _draft.defaultModel(TaskCategory.quick) == null;
    final target = focus is AiTaskFocusModel && (quickUnset || ids.isEmpty)
        ? _defaultId(TaskCategory.quick)
        : ids.firstOrNull;
    final first = ids.isEmpty ? null : _rowKey(ids.first).currentContext;
    if (first != null) unawaited(Scrollable.ensureVisible(first, alignment: .2, duration: MMMotion.quick));
    if (target != null) _node(target).requestFocus();
    _highlightTimer?.cancel();
    setState(() => _highlighted = ids.toSet());
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: no fade; the wash stays until focus leaves the row.
      final node = target == null ? null : _node(target);
      void left() {
        if (node!.hasFocus) return;
        node.removeListener(left);
        if (mounted) setState(() => _highlighted = const {});
      }

      node?.addListener(left);
    } else {
      _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _highlighted = const {});
      });
    }
  }

  void _openPicker(String id) {
    final key = _picker(id);
    final picker = key.currentWidget;
    final context = key.currentContext;
    if (picker is ModelRoutePicker && context != null && picker.onChanged != null) unawaited(picker.open(context));
  }

  Future<void> _reload() async {
    ref.invalidate(assistantRoutingProvider);
    try {
      _draft.reload(await ref.read(assistantRoutingProvider.future));
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  /// Enabled models of enabled services, by service, with why each cannot
  /// serve a feature of [category] needing [spec]'s capabilities.
  List<ModelRouteGroup> _groups(AssistantServices catalog, TaskCategory category, TaskSpec? spec) {
    return [
      for (final service in catalog.services)
        if (service.enabled && (service.protocol != ServiceProtocol.ollama || service.localEnabled))
          if (service.models.where((m) => m.enabled).toList() case final models when models.isNotEmpty)
            ModelRouteGroup(service.name, [
              for (final model in models)
                ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
            ]),
    ];
  }

  /// Heavy thinking choices the model's verified profile compiles; “Auto”
  /// alone while capabilities are unknown. [current] stays listed.
  Set<ReasoningPolicy> _reasoningOptions(AssistantServices catalog, ModelReference? model, ReasoningPolicy? current) {
    final service = catalog.services.where((s) => s.id == model?.serviceId).firstOrNull;
    final entry = service?.models.where((m) => m.id == model?.modelId).firstOrNull;
    final options = {ReasoningPolicy.auto, ?current};
    if (service != null && entry != null) {
      final profile = ref.read(assistantCapabilityProfilesProvider).lookup(serviceCapabilityIdentity(service, entry));
      options.addAll(ref.read(assistantModelResolverProvider).reasoningOptions(profile));
    }
    return options;
  }

  bool _isEmpty(AssistantServices catalog) =>
      catalog.services.every((s) => s.models.isEmpty) &&
      TaskCategory.values.every((c) => _draft.base!.defaultModel(c) == null && _draft.defaultModel(c) == null) &&
      !_draft.hasExplicit &&
      TaskType.values.every((t) => _draft.base!.binding(t).mode == TaskBindingMode.inherit) &&
      ((_draft.base!.document['bindings'] as Map?) ?? const {}).isEmpty;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final routing = ref.watch(assistantRoutingProvider);
    final services = ref.watch(assistantServicesProvider);
    ref.listen(assistantRoutingProvider, (_, next) {
      if (next.value case final config?) _draft.adopt(config);
    });
    ref.listen(assistantServicesProvider, (_, next) {
      final revision = next.value?.revision;
      if (revision == _catalogRevision) return;
      _catalogRevision = revision;
      unawaited(_inspect());
    });
    if (routing.value case final config? when !_draft.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _draft.adopt(config));
    }
    final catalog = services.value;
    if (catalog == null || !_draft.loaded || !_profilesLoaded) {
      return Center(
        key: const ValueKey('settings-ai-tasks'),
        child: routing.hasError || services.hasError
            ? Text(l.assistantErrorFailed, style: context.mmText.bodySecondary)
            : const CupertinoActivityIndicator(radius: 8),
      );
    }
    _catalogRevision ??= catalog.revision;
    if (_isEmpty(catalog)) {
      return Center(
        key: const ValueKey('settings-ai-tasks'),
        child: MMButton(
          key: const ValueKey('ai-tasks-add-model'),
          label: l.aiTasksAddModel,
          variant: MMButtonVariant.primary,
          onPressed: () => widget.onOpenModels(addService: true),
        ),
      );
    }
    final saving = _draft.saving;
    final state = _draft.state;
    final sheet = MMBottomSheet.contains(context);
    final bar = Container(
      key: const ValueKey('ai-tasks-actions'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.mmColors.separator)),
      ),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 10 + (sheet ? MediaQuery.paddingOf(context).bottom : 0)),
      child: SettingsSaveActions(
        key: const ValueKey('ai-tasks-save-status'),
        buttonKey: const ValueKey('ai-tasks-save'),
        dirty: _draft.dirty,
        saving: saving,
        saved: state == AiTaskSaveState.saved,
        failed: state == AiTaskSaveState.failed,
        message: state == AiTaskSaveState.conflict ? l.aiTasksConflict : null,
        onSave: state == AiTaskSaveState.conflict || !_draft.dirty ? null : () => saveAiTaskDraft(ref, _draft),
        secondaryAction: state == AiTaskSaveState.conflict
            ? MMButton(
                key: const ValueKey('ai-tasks-reload'),
                label: l.aiTasksReload,
                variant: MMButtonVariant.plain,
                onPressed: _reload,
              )
            : MMButton(
                key: const ValueKey('ai-tasks-reset'),
                label: l.aiTasksReset,
                variant: MMButtonVariant.plain,
                onPressed: saving || !_draft.hasExplicit ? null : _draft.resetBindings,
              ),
      ),
    );
    final specs = ref.watch(aiTaskRoutingSpecsProvider);
    final page = ListView(
      padding: EdgeInsets.fromLTRB(
        sheet ? MMSpacing.m : MMSpacing.m + 2,
        MMSpacing.xs,
        sheet ? MMSpacing.m : MMSpacing.m + 2,
        MMSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_profilesFailed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(MMSpacing.xs, MMSpacing.s, MMSpacing.xs, 0),
                    child: RoutingIssueLine(
                      key: const ValueKey('ai-tasks-profiles-failed'),
                      text: l.aiTasksProfilesUnavailable,
                      action: l.assistantRetry,
                      actionKey: const ValueKey('ai-tasks-profiles-retry'),
                      onAction: () => unawaited(_inspect()),
                    ),
                  ),
                for (final category in TaskCategory.values) ...[
                  if (category != TaskCategory.values.first) const SizedBox(height: MMSpacing.xs),
                  MMSettingsHeader(category == TaskCategory.quick ? l.aiTasksQuick : l.aiTasksHeavy),
                  MMSettingsGroup(
                    key: ValueKey('ai-tasks-defaults-${category.name}'),
                    children: [_defaultRow(catalog, category, saving), _thinkingRow(catalog, category, saving)],
                  ),
                  const SizedBox(height: MMSpacing.s),
                  MMSettingsGroup(
                    key: ValueKey('ai-tasks-features-${category.name}'),
                    children: [
                      for (final type in TaskType.values)
                        if (type.category == category) _featureRow(catalog, type, specs[type], saving),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    // ⌘S / Ctrl+S is bound by the settings window, which outlives this page.
    return FocusTraversalGroup(
      child: Column(
        key: const ValueKey('settings-ai-tasks'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: page),
          bar,
        ],
      ),
    );
  }

  String _separator(AppLocalizations l) => l.localeName.startsWith('zh') ? '，' : ', ';

  /// The button and its spoken value for a reference with [row]'s state.
  ({String label, ModelRouteTone tone, String semantic, String? tooltip}) _display(
    AssistantServices catalog,
    ModelReference? model,
    RoutingRowState? row, {
    required bool inherited,
    String? placeholder,
  }) {
    final l = context.l10n;
    if (model == null) {
      return (
        label: placeholder ?? l.aiTasksNotSet,
        tone: ModelRouteTone.caution,
        semantic: placeholder ?? l.aiTasksNotSet,
        tooltip: null,
      );
    }
    final snapshot = row?.effective == model;
    final serviceLabel = snapshot ? row?.serviceLabel : null, modelLabel = snapshot ? row?.modelLabel : null;
    final (service, name) = routeModelNames(catalog, model, serviceLabel: serviceLabel, modelLabel: modelLabel);
    final label = routeModelLabel(catalog, model, serviceLabel: serviceLabel, modelLabel: modelLabel);
    final invalid = row != null && row.effective == model && routingIssueInvalid(row.issue);
    final spoken = '$service · $name';
    return (
      label: label,
      tone: invalid
          ? ModelRouteTone.invalid
          : inherited
          ? ModelRouteTone.inherited
          : ModelRouteTone.explicit,
      semantic: invalid
          ? '$spoken${_separator(l)}${routingIssueText(l, row.issue)}'
          : inherited
          ? '${l.aiTasksUseDefault}${_separator(l)}$spoken'
          : spoken,
      tooltip: '$service · ${model.modelId}',
    );
  }

  /// The line under a row, if its state needs a decision.
  Widget? _issue(String id, RoutingRowState? row, {VoidCallback? onChoose, bool showThinking = true}) {
    if (row == null) return null;
    final l = context.l10n;
    final text = routingIssueText(l, row.issue, failureCode: row.failureCode);
    if (text == null) return null;
    if (row.issue == RoutingIssue.thinkingAlwaysOn && !showThinking) return null;
    // A store that cannot be read is reported once for the page, not per row.
    if (_storeFailures.contains(row.failureCode)) return null;
    final model = row.effective;
    switch (row.issue) {
      case RoutingIssue.unknown:
        return null;
      case RoutingIssue.secretUnavailable:
        return RoutingIssueLine(
          key: ValueKey('ai-issue-$id'),
          text: text,
          critical: false,
          action: l.aiTasksOpenModelSettings,
          actionKey: ValueKey('ai-action-$id'),
          onAction: model == null ? null : () => widget.onOpenModels(serviceId: model.serviceId),
        );
      default:
        return RoutingIssueLine(
          key: ValueKey('ai-issue-$id'),
          text: text,
          action: row.issue == RoutingIssue.thinkingAlwaysOn ? l.aiTasksChangeModel : l.aiTasksChooseAgain,
          actionKey: ValueKey('ai-action-$id'),
          onAction: _draft.saving ? null : onChoose,
        );
    }
  }

  Widget _defaultRow(AssistantServices catalog, TaskCategory category, bool saving) {
    final l = context.l10n;
    final id = _defaultId(category);
    final model = _draft.defaultModel(category);
    final row = _defaultRows[category];
    final display = _display(catalog, model, row, inherited: false, placeholder: l.aiTasksChooseModel);
    return _RouteRow(
      key: _rowKey(id),
      label: l.settingsDefaultModel,
      picker: ModelRoutePicker(
        key: _picker(id),
        focusNode: _node(id),
        label: display.label,
        tone: display.tone,
        tooltip: display.tooltip,
        highlighted: _highlighted.contains(id),
        semanticLabel:
            '${category == TaskCategory.quick ? l.aiTasksQuick : l.aiTasksHeavy} · ${l.settingsDefaultModel}',
        semanticValue: display.semantic,
        groups: _groups(catalog, category, null),
        selected: model,
        onChanged: saving
            ? null
            : (choice) {
                if (choice == null) return;
                _draft.setDefault(category, choice);
                if (category == TaskCategory.heavy &&
                    !_reasoningOptions(catalog, choice, null).contains(_draft.heavyReasoning)) {
                  _draft.setHeavyReasoning(ReasoningPolicy.auto);
                }
              },
      ),
      issue: category == TaskCategory.quick && row?.issue == RoutingIssue.thinkingAlwaysOn
          ? null
          : _issue(id, row, onChoose: () => _openPicker(id)),
    );
  }

  Widget _thinkingRow(AssistantServices catalog, TaskCategory category, bool saving) {
    final l = context.l10n;
    final c = context.mmColors;
    if (category == TaskCategory.quick) {
      final id = _defaultId(category);
      final row = _defaultRows[category];
      // Prefer off when the provider has a known control; otherwise use its defaults.
      return _RouteRow(
        key: const ValueKey('ai-tasks-quick-thinking'),
        label: l.aiTasksThinking,
        picker: ExcludeFocus(
          child: Text(
            row?.config?.policy.effective == ReasoningPolicy.off ? l.aiTasksThinkingOff : l.aiTasksThinkingAuto,
            style: context.mmText.body.copyWith(color: c.secondaryLabel),
          ),
        ),
        issue: row?.issue == RoutingIssue.thinkingAlwaysOn ? _issue(id, row, onChoose: () => _openPicker(id)) : null,
      );
    }
    final model = _draft.defaultModel(TaskCategory.heavy);
    final options = _reasoningOptions(catalog, model, _draft.heavyReasoning);
    return _RouteRow(
      key: const ValueKey('ai-tasks-heavy-thinking'),
      label: l.aiTasksThinking,
      picker: MMPopUpButton<ReasoningPolicy>(
        key: const ValueKey('ai-tasks-heavy-reasoning'),
        value: _draft.heavyReasoning,
        semanticLabel: '${l.aiTasksHeavy} · ${l.aiTasksThinking}',
        items: [
          for (final value in ReasoningPolicy.values)
            if (options.contains(value)) (value, reasoningLabel(l, value)),
        ],
        onChanged: saving || model == null ? null : _draft.setHeavyReasoning,
      ),
    );
  }

  Widget _featureRow(AssistantServices catalog, TaskType type, TaskSpec? spec, bool saving) {
    final l = context.l10n;
    final id = type.key;
    final binding = _draft.binding(type);
    final explicit = binding.mode == TaskBindingMode.explicit;
    final row = _rows[type];
    final fallback = _defaultRows[type.category];
    final defaultModel = _draft.defaultModel(type.category);
    final defaultBroken =
        defaultModel == null ||
        (fallback != null && (routingIssueInvalid(fallback.issue) || fallback.issue == RoutingIssue.unset));
    final model = explicit ? binding.model : (defaultBroken ? null : defaultModel);
    final display = _display(catalog, model, row, inherited: !explicit);
    final quickAlwaysOn =
        !explicit && type.category == TaskCategory.quick && fallback?.issue == RoutingIssue.thinkingAlwaysOn;
    // An inherited row repeats nothing the default row already says.
    final ownIssue =
        explicit ||
        row?.issue != fallback?.issue ||
        (row?.issue != RoutingIssue.unknown && row?.failureCode != fallback?.failureCode);
    final followNote = defaultModel == null || defaultBroken
        ? l.aiTasksNotSet
        : routeModelLabel(
            catalog,
            defaultModel,
            serviceLabel: fallback?.serviceLabel,
            modelLabel: fallback?.modelLabel,
          );
    final heavy = type.category == TaskCategory.heavy;
    return _RouteRow(
      key: _rowKey(id),
      label: aiTaskName(l, type),
      picker: ModelRoutePicker(
        key: _picker(id),
        focusNode: _node(id),
        label: display.label,
        tone: quickAlwaysOn && display.tone == ModelRouteTone.inherited ? ModelRouteTone.caution : display.tone,
        tooltip: display.tooltip,
        highlighted: _highlighted.contains(id),
        semanticLabel: aiTaskName(l, type),
        semanticValue: display.semantic,
        followLabel: l.aiTasksUseDefault,
        followNote: followNote,
        groups: _groups(catalog, type.category, spec),
        selected: explicit ? binding.model : null,
        reasoning: binding.reasoning ?? _draft.heavyReasoning,
        reasoningOptions: heavy && explicit ? _reasoningOptions(catalog, binding.model, binding.reasoning) : const {},
        onReasoningChanged: heavy && explicit
            ? (value) => _draft.setBinding(type, TaskModelBinding.explicit(binding.model!, reasoning: value))
            : null,
        onChanged: saving
            ? null
            : (choice) {
                if (choice == null) {
                  _draft.setBinding(type, const TaskModelBinding.inherit());
                  return;
                }
                final keep = heavy && _reasoningOptions(catalog, choice, null).contains(binding.reasoning);
                _draft.setBinding(type, TaskModelBinding.explicit(choice, reasoning: keep ? binding.reasoning : null));
              },
      ),
      issue: !ownIssue || (!explicit && defaultBroken) ? null : _issue(id, row, onChoose: () => _openPicker(id)),
    );
  }
}

/// A feature name and its picker, with an optional state line below. When the
/// pair cannot share a narrow line without cutting the model name, the picker
/// moves under the name, right-aligned.
class _RouteRow extends StatelessWidget {
  const _RouteRow({super.key, required this.label, required this.picker, this.issue});

  final String label;
  final Widget picker;
  final Widget? issue;

  @override
  Widget build(BuildContext context) {
    final t = context.mmText;
    final touch = context.mmTouchPlatform;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final largeText = scaler.scale(13) > 15;
        double width(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: t.body),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = painter.width;
          painter.dispose();
          return w;
        }

        final pickerText = picker is ModelRoutePicker ? (picker as ModelRoutePicker).label : '';
        final needed = width(label) + MMSpacing.m + width(pickerText) + 36 + 28;
        final stacked =
            (touch && constraints.maxWidth < (largeText ? 480 : 300)) ||
            (constraints.maxWidth < 460 && needed > constraints.maxWidth);
        final name = Text(
          label,
          maxLines: stacked ? null : 1,
          style: t.body.copyWith(color: context.mmColors.label),
        );
        final content = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  name,
                  const SizedBox(height: MMSpacing.xs),
                  Align(alignment: Alignment.centerRight, child: picker),
                ],
              )
            : Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth * .5),
                    child: name,
                  ),
                  const SizedBox(width: MMSpacing.m),
                  Expanded(
                    child: Align(alignment: Alignment.centerRight, child: picker),
                  ),
                ],
              );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            stacked ? MMSpacing.s : 0,
            14,
            issue == null ? (stacked ? MMSpacing.s : 0) : 7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked) content else SizedBox(height: touch ? 52 : 40, child: content),
              ?issue,
            ],
          ),
        );
      },
    );
  }
}
