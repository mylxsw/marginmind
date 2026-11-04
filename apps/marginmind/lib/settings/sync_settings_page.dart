import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_data/mm_data.dart';

import '../shared/l10n.dart';
import '../shared/sync_details.dart';
import 'settings_window.dart';
import 'sync_settings_controller.dart';

enum SyncSettingsSection { overview, connection, devices, files, advanced }

class SyncSettingsPage extends ConsumerStatefulWidget {
  const SyncSettingsPage({super.key, this.initialSection = SyncSettingsSection.overview});
  final SyncSettingsSection initialSection;
  @override
  ConsumerState<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends ConsumerState<SyncSettingsPage> {
  final _code = TextEditingController(), _name = TextEditingController();
  final _directory = TextEditingController(), _account = TextEditingController(), _password = TextEditingController();
  final _feedback = GlobalKey();
  late SyncSettingsSection _section = widget.initialSection;
  bool _joining = false, _adopted = false, _renaming = false, _copyDestination = false;
  bool _icloud = false;
  String? _nameRevision;

  @override
  void dispose() {
    for (final input in [_code, _name, _directory, _account, _password]) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _perform(SyncSettingsController service, Future<void> Function() action) async {
    await action();
    if (!mounted || service.failure == null) return;
    // The form keeps its values. Bring the visible error to the operation,
    // including when a keyboard or large text changes the available height.
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _feedback.currentContext != null) {
      await Scrollable.ensureVisible(
        _feedback.currentContext!,
        alignment: .6,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  Widget _input(String key, String label, TextEditingController controller, bool enabled, {bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: context.mmText.subheadline),
            const SizedBox(height: 6),
            MMTextField(
              key: ValueKey(key),
              controller: controller,
              semanticLabel: label,
              enabled: enabled,
              obscureText: secret,
            ),
          ],
        ),
      );

  Widget _group(List<Widget> children) => MMSettingsGroup(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    ],
  );

  Widget _actions(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(spacing: 8, runSpacing: 8, children: children),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel)),
  );

  Widget _error(SyncSettingsController service) => service.failure == null
      ? const SizedBox.shrink()
      : Container(
          key: _feedback,
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.mmColors.quaternaryFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.mmColors.caution),
          ),
          child: Semantics(liveRegion: true, child: Text(_failure(context.l10n, service.failure!))),
        );

  void _go(SyncSettingsSection section) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _section = section);
  }

  Widget _link(SyncSettingsSection section, String title, bool enabled) => MMSettingsRow(
    key: ValueKey('sync-nav-${section.name}'),
    leading: Text(title, style: context.mmText.body),
    trailing: const Icon(MMIcons.chevronRight, size: 14),
    onTap: enabled ? () => _go(section) : null,
  );

  Future<void> _disconnect(SyncSettingsController service) async {
    final target = service.target;
    if (target == null) return;
    final l = context.l10n;
    final confirmed = await showMMSheet<bool>(
      context: context,
      builder: (context) => MMSheet(
        title: target.service == 'icloud' ? l.syncDisconnectICloud : l.syncDisconnect,
        actions: [
          MMButton(label: l.cancel, onPressed: () => Navigator.pop(context, false)),
          MMButton(
            key: const ValueKey('sync-disconnect-confirm'),
            label: l.syncDisconnectConfirm,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
        child: Text(target.service == 'icloud' ? l.syncDisconnectICloudHint : l.syncDisconnectHint),
      ),
    );
    // A confirmation cannot disconnect a target that changed while it was open.
    if (!mounted || confirmed != true || service.busy || service.target != target) return;
    await _perform(service, service.disconnect);
    if (mounted && service.failure == null) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(syncSettingsControllerProvider), l = context.l10n;
    if (service == null) return SettingsPage(children: [_note(l.syncSettingsUnavailable)]);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!_adopted && service.initialized) {
          _adopted = true;
          _name.text = service.deviceName ?? '';
          _icloud = service.target?.service == 'icloud';
          if (service.target?.service == 'webdav') {
            _directory.text = service.target!.location;
            _account.text = service.target!.account;
          }
        }
        final enabled = !service.busy;
        final title = switch (_section) {
          SyncSettingsSection.overview => l.syncSettingsTitle,
          SyncSettingsSection.connection => l.syncServiceTitle,
          SyncSettingsSection.devices => l.syncLibraryDevices,
          SyncSettingsSection.files => l.syncResourcesTitle,
          SyncSettingsSection.advanced => l.syncAdvancedTitle,
        };
        return SettingsPage(
          key: ValueKey(_section),
          children: [
            if (_section != SyncSettingsSection.overview) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: MMButton(
                  key: const ValueKey('sync-back'),
                  label: l.syncBack,
                  variant: MMButtonVariant.plain,
                  onPressed: enabled ? () => _go(SyncSettingsSection.overview) : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: context.mmText.title3),
              const SizedBox(height: 16),
            ],
            if (service.busy) ...[
              _note(l.syncSettingsRunning),
              _actions([
                MMButton(key: const ValueKey('sync-pause'), label: l.syncSettingsPause, onPressed: service.pause),
              ]),
            ],
            if (!service.initialized) ...[
              _error(service),
              MMButton(
                label: l.syncSettingsRetry,
                onPressed: enabled ? () => _perform(service, service.initialize) : null,
              ),
            ] else if (service.restartRequired) ...[
              _group([
                Text(l.syncSetupReady, style: context.mmText.headline),
                _note(l.syncSettingsRestart),
                _error(service),
                _actions([
                  MMButton(
                    key: const ValueKey('sync-cancel-activation'),
                    label: l.cancel,
                    onPressed: enabled ? () => _perform(service, service.cancelActivation) : null,
                  ),
                ]),
              ]),
              const SizedBox(key: ValueKey('sync-restart')),
            ] else if (service.libraryId == null)
              ..._setup(service)
            else
              ...switch (_section) {
                SyncSettingsSection.overview => _overview(service),
                SyncSettingsSection.connection => _connection(service),
                SyncSettingsSection.devices => _devices(service),
                SyncSettingsSection.files => _files(service),
                SyncSettingsSection.advanced => _advanced(service),
              },
          ],
        );
      },
    );
  }

  List<Widget> _setup(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy;
    return [
      MMSettingsHeader(l.syncSetupTitle),
      _group([
        Text(l.syncSettingsLocal, style: context.mmText.headline),
        _note(l.syncSetupIntro),
        if (!s.canActivate)
          _note(l.syncSettingsUnavailable)
        else ...[
          MMPopUpButton<bool>(
            value: _joining,
            semanticLabel: l.syncSettingsTitle,
            items: [(false, l.syncSettingsNew), (true, l.syncSettingsJoin)],
            onChanged: enabled ? (value) => setState(() => _joining = value) : null,
          ),
          if (_joining) _input('sync-library-code', l.syncSettingsLibraryId, _code, enabled),
          _input('sync-device-name', l.syncSettingsDeviceName, _name, enabled),
          _note(l.syncDeviceExample),
          if (_joining) _note(l.syncSettingsIdentityHint),
          _error(s),
          _actions([
            MMButton(
              key: const ValueKey('sync-prepare'),
              label: l.syncSettingsPrepare,
              variant: MMButtonVariant.primary,
              onPressed: enabled
                  ? () => _perform(
                      s,
                      () => s.activate(existingLibraryId: _joining ? _code.text.trim() : null, deviceName: _name.text),
                    )
                  : null,
            ),
          ]),
        ],
      ]),
    ];
  }

  List<Widget> _overview(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy, target = s.target;
    return [
      _group([
        Text(
          target == null
              ? l.syncNotConnected
              : target.service == 'icloud'
              ? 'iCloud Drive'
              : 'WebDAV',
          style: context.mmText.title3,
        ),
        if (target != null) ...[
          if (target.service == 'webdav') Text(target.account, style: context.mmText.callout),
          const SizedBox(height: 12),
          if (!s.busy) Text(l.syncSettingsPaused),
          Text('${l.syncSettingsPending}: ${s.pending}'),
        ] else
          _note(l.syncConnectIntro),
        if (s.result case final result?) ...[
          const SizedBox(height: 12),
          Text('${l.syncSettingsReceived}: ${result.received}'),
          Text('${l.syncSettingsConfirmed}: ${result.confirmed}'),
          if (result.staged > 0) _note('${l.syncSettingsStaged}: ${result.staged}'),
        ],
        _error(s),
        _actions([
          MMButton(
            key: ValueKey(target == null ? 'sync-start-connection' : 'sync-once'),
            label: target == null ? l.syncServiceTitle : l.syncSettingsOnce,
            variant: MMButtonVariant.primary,
            onPressed: enabled
                ? () => target == null ? _go(SyncSettingsSection.connection) : _perform(s, s.syncOnce)
                : null,
          ),
        ]),
      ]),
      const SizedBox(height: 20),
      MMSettingsGroup(
        children: [
          _link(SyncSettingsSection.connection, l.syncServiceTitle, enabled),
          _link(SyncSettingsSection.devices, l.syncLibraryDevices, enabled),
          _link(SyncSettingsSection.files, l.syncResourcesTitle, enabled),
          _link(SyncSettingsSection.advanced, l.syncAdvancedTitle, enabled),
        ],
      ),
    ];
  }

  List<Widget> _connection(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy;
    return [
      _group([
        MMPopUpButton<bool>(
          key: const ValueKey('sync-service-picker'),
          value: _icloud,
          semanticLabel: l.syncServiceTitle,
          items: const [(false, 'WebDAV'), (true, 'iCloud Drive')],
          onChanged: enabled ? (v) => setState(() => _icloud = v) : null,
        ),
        if (!_icloud && s.canStoreSecrets) ...[
          _input('sync-directory', l.syncSettingsDirectory, _directory, enabled),
          _input('sync-account', l.syncSettingsAccount, _account, enabled),
          _input('sync-password', l.syncSettingsPassword, _password, enabled, secret: true),
        ],
        if (!_icloud && !s.canStoreSecrets) _note(l.syncSettingsUnavailable),
        if (_icloud) _note(l.syncICloudIntro),
        _note(l.syncSettingsConnectHint),
        _error(s),
        _actions([
          MMButton(
            key: ValueKey(_icloud ? 'sync-icloud' : 'sync-connect'),
            label: _icloud ? l.syncSettingsICloud : l.syncSettingsConnect,
            variant: MMButtonVariant.primary,
            onPressed: enabled && (_icloud || s.canStoreSecrets)
                ? () async {
                    await _perform(
                      s,
                      () => _icloud
                          ? s.connectICloud(copyDestination: _copyDestination)
                          : s.connectWebDav(
                              directory: _directory.text,
                              username: _account.text,
                              password: _password.text,
                              copyDestination: _copyDestination,
                            ),
                    );
                    if (mounted && s.failure == null) {
                      _password.clear();
                      _go(SyncSettingsSection.overview);
                    }
                  }
                : null,
          ),
        ]),
      ]),
      const SizedBox(height: 16),
      SyncDetails(
        key: const ValueKey('sync-connection-options'),
        title: l.syncConnectionOptions,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: MMCheckbox(
              key: const ValueKey('sync-copy-destination'),
              value: _copyDestination,
              label: l.syncCopyDestination,
              onChanged: enabled ? (v) => setState(() => _copyDestination = v) : null,
            ),
          ),
        ],
      ),
      if (s.target case final target?) ...[
        MMSettingsHeader(l.syncCurrentConnection),
        _group([
          Text('${target.service == 'icloud' ? 'iCloud Drive' : 'WebDAV'} · ${target.location}'),
          _actions([
            MMButton(
              key: const ValueKey('sync-disconnect'),
              label: target.service == 'icloud' ? l.syncDisconnectICloud : l.syncDisconnect,
              variant: MMButtonVariant.plain,
              destructive: true,
              onPressed: enabled ? () => _disconnect(s) : null,
            ),
          ]),
        ]),
      ],
    ];
  }

  List<Widget> _devices(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy;
    return [
      MMSettingsHeader(l.syncSettingsDeviceName),
      _group([
        if (_renaming) ...[
          _input('sync-rename-input', l.syncSettingsDeviceName, _name, enabled),
          _actions([
            MMButton(
              key: const ValueKey('sync-rename-save'),
              label: l.save,
              variant: MMButtonVariant.primary,
              onPressed: enabled
                  ? () async {
                      await _perform(s, () => s.renameDevice(_name.text, expectedRevision: _nameRevision));
                      if (mounted && s.failure == null) setState(() => _renaming = false);
                    }
                  : null,
            ),
            MMButton(label: l.cancel, onPressed: enabled ? () => setState(() => _renaming = false) : null),
          ]),
        ] else ...[
          Text(s.deviceName ?? l.syncSettingsDeviceName, style: context.mmText.headline),
          _actions([
            MMButton(
              key: const ValueKey('sync-rename'),
              label: l.syncDeviceRename,
              onPressed: enabled
                  ? () {
                      _name.text = s.deviceName ?? '';
                      _nameRevision = s.devices.where((d) => d.local).firstOrNull?.revision;
                      setState(() => _renaming = true);
                    }
                  : null,
            ),
          ]),
        ],
        _error(s),
      ]),
      if (s.devices.any((d) => !d.local)) ...[
        MMSettingsHeader(l.syncOtherDevices),
        MMSettingsGroup(
          children: [
            for (final device in s.devices.where((d) => !d.local))
              Padding(padding: const EdgeInsets.all(16), child: Text(device.name)),
          ],
        ),
      ],
      if (s.deviceProblems > 0) _note(l.syncDeviceHistoryProblem),
      MMSettingsHeader(l.syncSettingsLibraryId),
      _group([SelectableText(s.libraryId!), _note(l.syncLibraryCodeHint)]),
    ];
  }

  List<Widget> _files(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy;
    return [
      _error(s),
      if (s.resources.isEmpty) _group([Text(l.syncFilesEmpty)]),
      for (final r in s.resources)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _group([
            Text(r.title, style: context.mmText.headline),
            _note(switch (r.availability) {
              SyncResourceAvailability.available => l.syncResourceAvailable,
              SyncResourceAvailability.missing => l.syncResourceMissing,
              SyncResourceAvailability.changed => l.syncResourceChanged,
              SyncResourceAvailability.unverified => l.syncResourceUnverified,
            }),
            if (r.availability == SyncResourceAvailability.missing) ...[
              if (s.target == null) _note(l.syncConnectIntro),
              _actions([
                MMButton(
                  key: ValueKey('sync-download-${r.group}'),
                  label: l.syncResourceDownload,
                  onPressed: enabled && s.target != null ? () => _perform(s, () => s.downloadResource(r)) : null,
                ),
              ]),
            ],
            if (r.availability == SyncResourceAvailability.changed) _note(l.syncChangedHelp),
          ]),
        ),
      _actions([
        MMButton(
          key: const ValueKey('sync-resources-refresh'),
          label: l.syncSettingsRetry,
          onPressed: enabled ? () => _perform(s, s.refreshResources) : null,
        ),
      ]),
    ];
  }

  List<Widget> _advanced(SyncSettingsController s) {
    final l = context.l10n, enabled = !s.busy;
    return [
      _error(s),
      _group([
        _note(l.syncCopyHint),
        if (s.target == null)
          _note(l.syncConnectIntro)
        else ...[
          _actions([
            MMButton(
              key: const ValueKey('sync-copy-preview'),
              label: l.syncCopyPreview,
              onPressed: enabled ? () => _perform(s, s.previewHistoryCopy) : null,
            ),
          ]),
          if (s.historyCopy case final plan?) ...[
            const SizedBox(height: 12),
            Text('${plan.target.service} · ${plan.target.location}'),
            if (plan.target.service == 'webdav') Text(plan.target.account),
            _note(
              l.syncCopySummary(
                plan.commits,
                plan.otherDeviceCommits,
                plan.chunks,
                plan.excluded,
                plan.unverifiedVersions,
              ),
            ),
            _actions([
              MMButton(
                key: const ValueKey('sync-copy-confirm'),
                label: l.syncCopyConfirm,
                onPressed: enabled ? () => _perform(s, () => s.copyHistory(plan)) : null,
              ),
              MMButton(label: l.cancel, onPressed: enabled ? s.pause : null),
            ]),
          ],
        ],
      ]),
      const SizedBox(height: 20),
      _group([
        _note(l.syncCacheHint),
        if (s.cacheUsage case final cache?) ...[
          Text(l.syncCacheReadable(_size(cache.bytes), _size(cache.reclaimableBytes))),
          if (cache.staging) _note(l.syncCacheStaging),
          if (cache.incompleteHistory) _note(l.syncCacheIncomplete),
          if (cache.reclaimedBytes > 0) _note(l.syncCacheFreed(_size(cache.reclaimedBytes))),
          if (cache.canReclaim)
            _actions([
              MMButton(
                key: const ValueKey('sync-cache-reclaim'),
                label: l.syncCacheReclaim,
                onPressed: enabled && cache.reclaimableChunks > 0 ? () => _perform(s, s.reclaimCache) : null,
              ),
            ]),
        ],
        _actions([
          MMButton(
            key: const ValueKey('sync-cache-inspect'),
            label: l.syncCacheInspect,
            onPressed: enabled ? () => _perform(s, s.inspectCache) : null,
          ),
        ]),
      ]),
    ];
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }

  String _failure(AppLocalizations l, SyncSettingsFailure failure) => switch (failure) {
    SyncSettingsFailure.timedOut => l.syncSettingsTimedOut,
    SyncSettingsFailure.staleDevice => l.syncDeviceStale,
    SyncSettingsFailure.staleHistory => l.syncCopyStale,
    SyncSettingsFailure.historyResources => l.syncCopyResources,
    SyncSettingsFailure.resources => l.syncResourceChanged,
    SyncSettingsFailure.invalidInput => l.syncSettingsInvalid,
    SyncSettingsFailure.incompleteLibrary => l.syncSettingsRepair,
    SyncSettingsFailure.missingLibrary => l.syncSettingsMissing,
    SyncSettingsFailure.unsupported => l.syncSettingsUnavailable,
    SyncSettingsFailure.authentication => l.syncSettingsAuth,
    SyncSettingsFailure.accountChanged => l.syncSettingsAccountChanged,
    SyncSettingsFailure.legacyProtocol => l.syncSettingsLegacy,
    SyncSettingsFailure.missingHistory => l.syncSettingsHistory,
    SyncSettingsFailure.paused => l.syncSettingsPaused,
    SyncSettingsFailure.storage || SyncSettingsFailure.service => l.syncSettingsError,
  };
}
