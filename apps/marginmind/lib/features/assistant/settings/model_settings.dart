import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/settings_window.dart' show SettingsPage;
import '../../../settings/settings_save_actions.dart';
import '../../../shared/l10n.dart';
import '../../workspace/widgets/notices.dart' show showConfirmSheet;
import '../assistant_services.dart';
import '../assistant_settings.dart';
import '../widgets/service_logo.dart';

/// “Model ID” key of a model in pop-ups: unique across services.
String modelKey(String serviceId, String modelId) => '$serviceId\u0000$modelId';

/// Why a service cannot be reached, in the words the settings use.
String connectionFailure(AppLocalizations l, ConnectionStatus status) =>
    status == ConnectionStatus.authFailed ? l.assistantErrorKey : l.assistantCannotConnect;

/// Settings › Models: the default model, then one card per service.
class ModelSettingsPage extends ConsumerStatefulWidget {
  const ModelSettingsPage({super.key});

  @override
  ConsumerState<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends ConsumerState<ModelSettingsPage> {
  String? _open;

  /// A service just added: its card opens with the key field focused.
  String? _fresh;

  Future<void> _add(BuildContext button) async {
    final l = context.l10n;
    final protocol = await showServiceList(button);
    if (protocol == null || !mounted) return;
    final value = await ref.read(assistantServicesProvider.future);
    final service = newAssistantService(protocol, serviceTitle(l, protocol), value.services.map((s) => s.id));
    await ref.read(assistantServicesProvider.notifier).upsert(service);
    if (mounted) {
      setState(() {
        _open = service.id;
        _fresh = service.id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final services = ref.watch(assistantServicesProvider);
    final value = services.value;
    final controller = ref.read(assistantServicesProvider.notifier);
    return SettingsPage(
      key: const ValueKey('settings-models'),
      children: [
        if (value == null)
          Padding(
            padding: const EdgeInsets.all(MMSpacing.xl),
            child: services.hasError
                ? Text(l.assistantErrorFailed, textAlign: TextAlign.center, style: context.mmText.bodySecondary)
                : const Center(child: CupertinoActivityIndicator(radius: 8)),
          )
        else ...[
          const SizedBox(height: MMSpacing.s),
          MMSettingsGroup(
            children: [
              MMSettingsRow(
                label: l.settingsDefaultModel,
                trailing: MMPopUpButton<String>(
                  key: const ValueKey('settings-default-model'),
                  semanticLabel: l.settingsDefaultModel,
                  value: value.defaultModel == null
                      ? null
                      : modelKey(value.defaultModel!.serviceId, value.defaultModel!.modelId),
                  items: [
                    for (final s in value.services)
                      for (final m in value.enabledModelsByService[s.id] ?? const <AssistantModel>[])
                        (modelKey(s.id, m.model), modelLabel(value, m)),
                  ],
                  onChanged: (key) {
                    final [service, model] = key.split('\u0000');
                    unawaited(controller.setDefault(ModelReference(service, model)));
                  },
                ),
              ),
            ],
          ),
          MMSettingsHeader(l.settingsServices),
          for (final s in value.services) ...[
            ServiceCard(
              key: ValueKey('service-${s.id}'),
              service: s,
              defaultModel: value.defaultModel,
              open: _open == s.id,
              focusKey: _fresh == s.id,
              onToggle: () => setState(() {
                _open = _open == s.id ? null : s.id;
                _fresh = null;
              }),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (button) => MMButton(
                key: const ValueKey('settings-add-service'),
                label: l.settingsAddService,
                icon: MMIcons.add,
                variant: MMButtonVariant.plain,
                color: c.accent,
                onPressed: () => _add(button),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A model's name for menus: its display name; the model ID when the
/// service no longer lists it.
String modelLabel(AssistantServices services, AssistantModel model) =>
    services.services
        .where((s) => s.id == model.serviceId)
        .expand((s) => s.models)
        .where((m) => m.id == model.model)
        .map((m) => m.displayName)
        .firstOrNull ??
    model.model;

/// What the add-service list calls each protocol, and a new service's name.
String serviceTitle(AppLocalizations l, ServiceProtocol p) => switch (p) {
  ServiceProtocol.anthropic => 'Anthropic',
  ServiceProtocol.openai => 'OpenAI',
  ServiceProtocol.gemini => 'Gemini',
  ServiceProtocol.ollama => 'Ollama',
};

/// One horizontal row per service, above [anchor], scrollable as the list grows.
Future<ServiceProtocol?> showServiceList(BuildContext anchor) {
  final l = anchor.l10n;
  final box = anchor.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final services = [
    (ServiceProtocol.anthropic, ServiceBrand.anthropic, 'Anthropic'),
    (ServiceProtocol.openai, ServiceBrand.openai, l.settingsOpenAiCompatible),
    (ServiceProtocol.gemini, ServiceBrand.gemini, 'Google Gemini'),
    (ServiceProtocol.ollama, ServiceBrand.ollama, l.settingsOllamaLocal),
  ];
  return showGeneralDialog<ServiceProtocol>(
    context: anchor,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
    transitionDuration: MMMotion.popup,
    pageBuilder: (context, _, _) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: FocusScope(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _AboveLayout(rect),
          child: Material(
            type: MaterialType.transparency,
            child: MMGlass(
              key: const ValueKey('service-list'),
              borderRadius: BorderRadius.circular(MMRadii.card),
              padding: const EdgeInsets.all(MMSpacing.xs),
              child: SizedBox(
                width: MMSizes.sidebarWidth + MMSpacing.xxl,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 2),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final (protocol, brand, name) in services)
                        MMInteractive(
                          key: ValueKey('service-option-${protocol.name}'),
                          onTap: () => Navigator.of(context).pop(protocol),
                          semanticLabel: name,
                          builder: (context, s) => AnimatedContainer(
                            duration: MMMotion.quick,
                            padding: const EdgeInsets.all(MMSpacing.s),
                            decoration: BoxDecoration(
                              color: s.hovered || s.focused ? context.mmColors.hover : Colors.transparent,
                              borderRadius: BorderRadius.circular(MMRadii.row),
                            ),
                            child: Row(
                              children: [
                                ServiceLogo(brand: brand, name: name, size: MMSizes.field),
                                const SizedBox(width: MMSpacing.m),
                                Expanded(
                                  child: Text(name, style: context.mmText.body.copyWith(color: context.mmColors.label)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

/// Above [anchor] when there is room, else below; inside the window.
class _AboveLayout extends SingleChildLayoutDelegate {
  _AboveLayout(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final y = anchor.top - child.height - 6 >= 8 ? anchor.top - child.height - 6 : anchor.bottom + 6;
    final x = anchor.left.clamp(8.0, (size.width - child.width - 8).clamp(8.0, double.infinity));
    return Offset(x, y.clamp(8.0, (size.height - child.height - 8).clamp(8.0, double.infinity)));
  }

  @override
  bool shouldRelayout(_AboveLayout old) => old.anchor != anchor;
}

/// One service: its mark, name and state with an on/off switch; opens in
/// place to its address, key and models.
class ServiceCard extends ConsumerStatefulWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.defaultModel,
    required this.open,
    required this.onToggle,
    this.focusKey = false,
  });

  final AssistantService service;
  final ModelReference? defaultModel;
  final bool open;
  final VoidCallback onToggle;

  /// Just added: the key (or address) field takes the focus.
  final bool focusKey;

  @override
  ConsumerState<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<ServiceCard> {
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _keyFocus = FocusNode();
  final _endpointFocus = FocusNode();
  CancellationToken? _check;
  bool _checking = false, _custom = false, _openingModels = false;
  bool _nameDirty = false, _endpointDirty = false, _keyDirty = false, _keyEdited = false;
  bool _saved = false, _saveFailed = false, _keyUnavailable = false;
  int _revision = 0;
  Future<bool>? _saving;
  late final AssistantServicesController _controller;
  late AppLocalizations _l;
  int _pendingWrites = 0;

  /// Why the last check failed; null when it passed or none ran.
  String? _failure;

  AssistantService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(assistantServicesProvider.notifier);
    _name.text = widget.service.name;
    _endpoint.text = widget.service.endpoint;
    unawaited(_loadKey());
    if (widget.focusKey) WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst());
  }

  @override
  void didUpdateWidget(ServiceCard old) {
    super.didUpdateWidget(old);
    if (widget.focusKey && !old.focusKey) WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = context.l10n;
  }

  void _focusFirst() {
    if (!mounted) return;
    (_service.protocol == ServiceProtocol.ollama ? _endpointFocus : _keyFocus).requestFocus();
  }

  Future<void> _loadKey() async {
    try {
      final key = await assistantServiceKey(ref.read(assistantSecretsProvider), _service.id, _service.provider);
      if (!mounted) return;
      if (!_keyEdited && key != null) _key.text = key;
      setState(() => _keyUnavailable = false);
    } on ResearchFailure {
      if (mounted) setState(() => _keyUnavailable = true);
    }
  }

  void _cancelCheck() {
    _check?.cancel();
    _check = null;
  }

  @override
  void dispose() {
    _cancelCheck();
    _name.dispose();
    _endpoint.dispose();
    _key.dispose();
    _keyFocus.dispose();
    _endpointFocus.dispose();
    super.dispose();
  }

  bool get _showsEndpoint => !serviceEndpointOptional(_service.protocol) || _custom || _endpointChanged;
  bool get _endpointChanged => _service.endpoint.trim() != defaultServiceEndpoint(_service.protocol);
  bool get _needsKey => _service.protocol != ServiceProtocol.ollama;

  void _nameChanged(String _) {
    _nameDirty = true;
    _markChanged();
  }

  void _connectionChanged(String _, {bool key = false}) {
    if (key) {
      _keyDirty = _keyEdited = true;
    } else {
      _endpointDirty = true;
    }
    _markChanged();
  }

  void _markChanged() {
    _revision++;
    _cancelCheck();
    setState(() {
      _checking = false;
      _saved = _saveFailed = false;
      _failure = null;
    });
  }

  bool get _dirty => _nameDirty || _endpointDirty || _keyDirty;

  /// Save only after the explicit action, keeping drafts out of live settings.
  Future<bool> _savePending() {
    if (!_nameDirty && !_endpointDirty && !_keyDirty) return _saving ?? Future.value(true);
    final nameDirty = _nameDirty, endpointDirty = _endpointDirty, keyDirty = _keyDirty;
    final name = _name.text.trim(), endpoint = _endpoint.text.trim(), key = _key.text;
    final revision = _revision;
    final l = _l;
    _nameDirty = _endpointDirty = _keyDirty = false;
    _pendingWrites++;
    final save = _controller.updateDetails(
      _service.id,
      name: nameDirty && name.isNotEmpty ? name : null,
      endpoint: endpointDirty && endpoint.isNotEmpty ? endpoint : null,
      key: keyDirty ? key : null,
    );
    // Delay UI notifications so disposal can safely flush without setState.
    final result = save.then(
      (_) {
        _pendingWrites--;
        if (mounted && revision == _revision) {
          setState(() {
            _saved = true;
            _saveFailed = false;
            if (keyDirty) _keyUnavailable = false;
            _failure = null;
          });
        }
        return true;
      },
      onError: (Object _) {
        _pendingWrites--;
        _nameDirty |= nameDirty;
        _endpointDirty |= endpointDirty;
        _keyDirty |= keyDirty;
        if (mounted && revision == _revision) {
          setState(() {
            _saveFailed = true;
            _failure = keyDirty ? l.assistantKeySaveUnavailable : l.settingsSaveFailed;
          });
        }
        return false;
      },
    );
    _saving = result;
    return result;
  }

  Future<void> _saveAndCheck() async {
    if (_pendingWrites > 0) return;
    if (_name.text.trim().isEmpty || _endpoint.text.trim().isEmpty) {
      setState(() {
        _saveFailed = true;
        _failure = context.l10n.settingsRequiredFields;
      });
      return;
    }
    // Also re-save a loaded key so an explicit save verifies its readability.
    if (_needsKey && _key.text.trim().isNotEmpty) _keyDirty = true;
    setState(() {});
    final revision = _revision;
    if (!await _savePending() || !mounted || revision != _revision) return;
    final service = ref.read(assistantServicesProvider).value!.services.firstWhere((s) => s.id == _service.id);
    await _runCheck(service);
  }

  Future<void> _addModels() async {
    if (_openingModels || _dirty || _pendingWrites > 0) return;
    setState(() => _openingModels = true);
    _cancelCheck();
    try {
      final service = ref.read(assistantServicesProvider).value!.services.firstWhere((s) => s.id == _service.id);
      await showAddModels(context, service);
    } finally {
      if (mounted) setState(() => _openingModels = _checking = false);
    }
  }

  Future<void> _runCheck(AssistantService service) async {
    if (!mounted) return;
    final l = context.l10n;
    if (_needsKey && _key.text.trim().isEmpty) {
      setState(() {
        _checking = false;
        _failure = null;
      });
      return;
    }
    final token = _check = CancellationToken();
    setState(() => _checking = true);
    ConnectionStatus status;
    try {
      status = await ref.read(serviceCatalogProvider).check(service, _key.text.trim(), cancellation: token);
    } on ResearchFailure {
      return; // Cancelled by a newer edit.
    }
    if (!mounted || !identical(token, _check)) return;
    setState(() {
      _checking = false;
      _failure = status == ConnectionStatus.ok ? null : connectionFailure(l, status);
    });
  }

  Future<void> _remove() async {
    final l = context.l10n;
    final ok = await showConfirmSheet(
      context,
      title: l.settingsRemoveServiceTitle(_service.name),
      message: l.settingsRemoveServiceMessage,
      confirmLabel: l.settingsRemoveService,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(assistantServicesProvider.notifier).remove(_service.id);
    } catch (_) {
      if (mounted) MMHud.show(context, l.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final s = _service;
    final enabled = s.models.where((m) => m.enabled).length;
    final Widget status = _checking
        ? const SizedBox(width: 10, height: 10, child: CupertinoActivityIndicator(radius: 5))
        : !s.enabled
        ? Text(
            l.settingsServiceOff,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.footnote.copyWith(color: c.secondaryLabel),
          )
        : _failure != null
        ? Row(
            key: const ValueKey('service-failure'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(MMIcons.warning, size: 11, color: c.critical),
              const SizedBox(width: MMSpacing.xs),
              Flexible(
                child: Text(
                  _failure!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.footnote.copyWith(color: c.critical),
                ),
              ),
            ],
          )
        : Text(
            s.models.isEmpty ? l.settingsServiceNoModels : l.settingsServiceModels(enabled),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.footnote.copyWith(color: c.secondaryLabel),
          );
    final header = MMInteractive(
      key: ValueKey('service-header-${s.id}'),
      onTap: widget.onToggle,
      semanticValue: widget.open ? '▾' : '▸',
      builder: (context, state) => Container(
        constraints: BoxConstraints(
          minHeight: 52,
          maxHeight: context.mmTouchPlatform
              ? ((MediaQuery.textScalerOf(context).scale(15) + MediaQuery.textScalerOf(context).scale(13)) * 1.4 + 12)
                    .clamp(52.0, 200.0)
              : 52,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Opacity(
              opacity: s.enabled ? 1 : .5,
              child: ServiceLogo(brand: serviceBrand(s.protocol, s.endpoint), name: s.name),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(fontWeight: FontWeight.w600, color: c.label),
                  ),
                  const SizedBox(height: 1),
                  status,
                ],
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            if (widget.open) ...[
              MMIconButton(
                key: const ValueKey('service-remove'),
                icon: MMIcons.trash,
                iconSize: 13,
                size: MMSizes.field,
                tooltip: l.settingsRemoveService,
                onPressed: _remove,
              ),
              const SizedBox(width: MMSpacing.s),
            ],
            MMSwitch(
              key: ValueKey('service-switch-${s.id}'),
              value: s.enabled,
              color: c.positive,
              semanticLabel: s.name,
              onChanged: (v) => unawaited(ref.read(assistantServicesProvider.notifier).setEnabled(s.id, v)),
            ),
            const SizedBox(width: MMSpacing.s),
            Icon(widget.open ? MMIcons.chevronDown : MMIcons.chevronRight, size: 12, color: c.icon),
          ],
        ),
      ),
    );
    if (!widget.open) return MMSettingsGroup(children: [header]);
    return MMSettingsGroup(
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSaveActions(
            key: const ValueKey('service-save-status'),
            buttonKey: const ValueKey('service-save'),
            dirty: _dirty,
            saving: _pendingWrites > 0,
            saved: _saved,
            failed: _saveFailed,
            onSave: _saveAndCheck,
          ),
          if (_keyUnavailable) Text(l.assistantSavedKeyUnavailable, style: t.footnote.copyWith(color: c.critical)),
          if (serviceEndpointOptional(s.protocol) && !_showsEndpoint)
            MMButton(
              key: const ValueKey('service-custom-address'),
              label: l.settingsCustomAddress,
              variant: MMButtonVariant.plain,
              onPressed: () {
                setState(() => _custom = true);
                WidgetsBinding.instance.addPostFrameCallback((_) => _endpointFocus.requestFocus());
              },
            ),
        ],
      ),
      children: [
        header,
        MMSettingsRow(
          label: l.settingsName,
          trailing: MMTextField.settings(
            key: const ValueKey('service-name'),
            enabled: _pendingWrites == 0,
            controller: _name,
            placeholder: l.settingsNamePlaceholder,
            semanticLabel: l.settingsName,
            onChanged: _nameChanged,
          ),
        ),
        if (_showsEndpoint)
          MMSettingsRow(
            label: l.settingsAddress,
            trailing: MMTextField.settings(
              key: const ValueKey('service-endpoint'),
              enabled: _pendingWrites == 0,
              controller: _endpoint,
              focusNode: _endpointFocus,
              placeholder: defaultServiceEndpoint(s.protocol),
              semanticLabel: l.settingsAddress,
              onChanged: _connectionChanged,
            ),
          ),
        if (_needsKey)
          MMSettingsRow(
            label: 'API Key',
            trailing: MMTextField.settings(
              key: const ValueKey('service-key'),
              enabled: _pendingWrites == 0,
              controller: _key,
              focusNode: _keyFocus,
              obscureText: true,
              placeholder: l.assistantPasteKey,
              semanticLabel: 'API Key',
              onChanged: (value) => _connectionChanged(value, key: true),
            ),
          ),
        MMSettingsRow(
          height: MMSpacing.xxxl,
          leading: Text(
            l.settingsModels,
            key: const ValueKey('service-models-heading'),
            style: t.subheadline.copyWith(fontWeight: FontWeight.w600, color: c.secondaryLabel),
          ),
          trailing: MMIconButton(
            key: const ValueKey('service-add-model'),
            icon: MMIcons.add,
            iconSize: 13,
            size: MMSizes.field,
            tooltip: _dirty ? l.settingsSaveBeforeModels : l.settingsAddModel,
            color: c.accent,
            onPressed: _openingModels || _dirty || _pendingWrites > 0 ? null : _addModels,
          ),
        ),
        for (final m in s.models)
          _ModelRow(
            key: ValueKey('model-${m.id}'),
            service: s,
            model: m,
            isDefault: widget.defaultModel?.serviceId == s.id && widget.defaultModel?.modelId == m.id,
          ),
      ],
    );
  }
}

/// A model of a service: its name (double-click renames; the ID is in the
/// tooltip), “Make Default” and remove on hover, and its switch.
class _ModelRow extends ConsumerStatefulWidget {
  const _ModelRow({super.key, required this.service, required this.model, required this.isDefault});

  final AssistantService service;
  final ServiceModel model;
  final bool isDefault;

  @override
  ConsumerState<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends ConsumerState<_ModelRow> {
  bool _hover = false, _editing = false;
  final _name = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _edit() {
    _name.text = widget.model.displayName;
    _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (!_editing) return;
    final name = _name.text.trim();
    setState(() => _editing = false);
    // Empty goes back to the name the service gave.
    final next = name == widget.model.id ? '' : name;
    if (next != widget.model.name) {
      unawaited(
        ref.read(assistantServicesProvider.notifier).upsertModel(widget.service.id, widget.model.copyWith(name: next)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final m = widget.model;
    final controller = ref.read(assistantServicesProvider.notifier);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: MMSettingsRow(
        leading: _editing
            ? MMInlineTextField(
                controller: _name,
                focusNode: _focus,
                style: t.body.copyWith(color: c.label),
                semanticLabel: l.settingsName,
                maxLines: 1,
                onSubmitted: _commit,
                onCancel: () => setState(() => _editing = false),
                onTapOutside: _commit,
              )
            : Tooltip(
                message: m.id,
                child: GestureDetector(
                  onDoubleTap: _edit,
                  child: Text(
                    m.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: m.enabled ? c.label : c.secondaryLabel),
                  ),
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isDefault)
              Row(
                key: const ValueKey('model-default'),
                children: [
                  Icon(MMIcons.check, size: 11, color: c.secondaryLabel),
                  const SizedBox(width: 2),
                  Text(l.settingsIsDefault, style: t.footnote.copyWith(color: c.secondaryLabel)),
                ],
              )
            else if (_hover && m.enabled && widget.service.enabled)
              MMButton(
                key: ValueKey('model-set-default-${m.id}'),
                label: l.settingsSetDefault,
                variant: MMButtonVariant.plain,
                onPressed: () =>
                    unawaited(controller.setDefault(ModelReference(widget.service.id, m.id)).catchError((Object _) {})),
              ),
            const SizedBox(width: MMSpacing.xs),
            Opacity(
              opacity: _hover ? 1 : 0,
              child: MMIconButton(
                key: ValueKey('model-remove-${m.id}'),
                icon: MMIcons.remove,
                iconSize: 13,
                size: 22,
                tooltip: l.settingsRemoveModel,
                onPressed: () => unawaited(controller.removeModel(widget.service.id, m.id)),
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            MMSwitch(
              key: ValueKey('model-switch-${m.id}'),
              value: m.enabled,
              color: c.positive,
              semanticLabel: m.displayName,
              onChanged: (v) => unawaited(controller.setModelEnabled(widget.service.id, m.id, v)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The “Add Models” sheet: lists what the service offers, filtered as one
/// types; an ID it does not list can be added by name.
Future<void> showAddModels(BuildContext context, AssistantService service) => showMMSheet<void>(
  context: context,
  width: 460,
  builder: (_) => AddModelsSheet(service: service),
);

class AddModelsSheet extends ConsumerStatefulWidget {
  const AddModelsSheet({super.key, required this.service});

  final AssistantService service;

  @override
  ConsumerState<AddModelsSheet> createState() => _AddModelsSheetState();
}

class _AddModelsSheetState extends ConsumerState<AddModelsSheet> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _cancel = CancellationToken();
  final _picked = <String>[];
  List<ServiceModel>? _models;
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queryFocus.requestFocus();
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _cancel.cancel();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _models = null;
      _error = null;
    });
    final l = context.l10n;
    try {
      final key =
          await assistantServiceKey(ref.read(assistantSecretsProvider), widget.service.id, widget.service.provider) ??
          '';
      final models = await ref.read(serviceCatalogProvider).list(widget.service, key, cancellation: _cancel);
      if (mounted) setState(() => _models = models);
    } on ResearchFailure catch (e) {
      if (!mounted || e.kind == ResearchFailureKind.cancelled) return;
      setState(() {
        _models = const [];
        _error = e.code == 'secret_store'
            ? l.assistantSavedKeyUnavailable
            : e.kind == ResearchFailureKind.authentication
            ? l.assistantErrorKey
            : l.assistantCannotConnect;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _models = const [];
          _error = l.assistantCannotConnect;
        });
      }
    }
  }

  void _toggle(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  Future<void> _add() async {
    if (_picked.isEmpty || _adding) return;
    setState(() => _adding = true);
    final controller = ref.read(assistantServicesProvider.notifier);
    final listed = {for (final m in _models ?? const <ServiceModel>[]) m.id: m};
    try {
      await controller.addModels(widget.service.id, [
        for (final id in _picked) (listed[id] ?? ServiceModel(id: id)).copyWith(enabled: true),
      ]);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
      MMHud.show(context, context.l10n.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final added = {for (final m in widget.service.models) m.id};
    final query = _query.text.trim();
    final lower = query.toLowerCase();
    final models = _models;
    final rows = [
      for (final m in models ?? const <ServiceModel>[])
        if (lower.isEmpty || m.id.toLowerCase().contains(lower) || m.name.toLowerCase().contains(lower)) m,
    ];
    final manual =
        query.isNotEmpty &&
            !(models ?? const <ServiceModel>[]).any((m) => m.id.toLowerCase() == lower) &&
            models != null
        ? query
        : null;
    final count = _picked.where((id) => !added.contains(id)).length;
    Widget pick(String id, String label, {bool manualRow = false}) {
      final have = added.contains(id);
      final on = have || _picked.contains(id);
      return MMInteractive(
        key: ValueKey(manualRow ? 'add-model-manual' : 'add-model-$id'),
        onTap: have || _adding ? null : () => _toggle(id),
        semanticLabel: label,
        semanticValue: on ? '✓' : null,
        builder: (context, s) => Opacity(
          opacity: have ? .45 : 1,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: s.hovered && !have ? c.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MMMotion.quick,
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? c.accent : Colors.transparent,
                    border: Border.all(color: on ? c.accent : c.separator, width: 1.2),
                  ),
                  child: on ? Icon(MMIcons.check, size: 10, color: c.onAccent) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: id,
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                  ),
                ),
                if (have) Text(l.settingsAdded, style: t.footnote.copyWith(color: c.secondaryLabel)),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('add-models'),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          border: Border.all(color: c.hairline, width: .5),
          boxShadow: c.sheetShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, MMSpacing.m),
              child: Row(
                children: [
                  ServiceLogo(
                    brand: serviceBrand(widget.service.protocol, widget.service.endpoint),
                    name: widget.service.name,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.settingsAddModelTitle, style: t.headline.copyWith(color: c.label)),
                        Text(widget.service.name, style: t.footnote.copyWith(color: c.secondaryLabel)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: MMSearchField(
                key: const ValueKey('add-model-search'),
                controller: _query,
                focusNode: _queryFocus,
                placeholder: l.settingsSearchModels,
              ),
            ),
            const SizedBox(height: MMSpacing.s),
            SizedBox(
              height: 300,
              child: models == null
                  ? const Center(child: CupertinoActivityIndicator(radius: 8))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        if (_error != null)
                          Padding(
                            key: const ValueKey('add-model-error'),
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Icon(MMIcons.warning, size: 13, color: c.critical),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_error!, style: t.callout.copyWith(color: c.critical)),
                                ),
                              ],
                            ),
                          ),
                        for (final m in rows) pick(m.id, m.displayName),
                        if (manual != null) pick(manual, l.settingsAddManual(manual), manualRow: true),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.separator)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: MMSpacing.s),
                  if (_adding)
                    const SizedBox(width: 72, child: Center(child: CupertinoActivityIndicator(radius: 7)))
                  else
                    MMButton(
                      key: const ValueKey('add-models-confirm'),
                      label: count == 0 ? l.settingsAdd : l.settingsAddCount(count),
                      variant: MMButtonVariant.primary,
                      onPressed: count == 0 ? null : _add,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
