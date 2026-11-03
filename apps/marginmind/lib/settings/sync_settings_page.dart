import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_data/mm_data.dart';

import '../shared/l10n.dart';
import 'settings_window.dart';
import 'sync_settings_controller.dart';

class SyncSettingsPage extends ConsumerStatefulWidget {
  const SyncSettingsPage({super.key});
  @override
  ConsumerState<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends ConsumerState<SyncSettingsPage> {
  final _code = TextEditingController(), _name = TextEditingController();
  final _directory = TextEditingController(), _account = TextEditingController(), _password = TextEditingController();
  bool _joining = false, _adopted = false, _renaming = false, _copyDestination = false;
  String? _nameRevision;
  @override
  void dispose() {
    for (final input in [_code, _name, _directory, _account, _password]) {
      input.dispose();
    }
    super.dispose();
  }

  Widget _input(String key, String label, TextEditingController controller, bool enabled, {bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const SizedBox(height: 4),
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

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(syncSettingsControllerProvider), l = context.l10n;
    if (service == null) return SettingsPage(children: [Text(l.syncSettingsUnavailable)]);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!_adopted && service.initialized) {
          _adopted = true;
          _name.text = service.deviceName ?? '';
          if (service.target?.service == 'webdav') {
            _directory.text = service.target!.location;
            _account.text = service.target!.account;
          }
        }
        final enabled = !service.busy;
        return SettingsPage(
          children: [
            Text(l.syncSettingsScope, style: context.mmText.callout),
            const SizedBox(height: 16),
            if (service.failure != null) ...[
              Semantics(liveRegion: true, child: Text(_failure(l, service.failure!))),
              const SizedBox(height: 12),
            ],
            if (!service.initialized)
              MMButton(label: l.syncSettingsRetry, onPressed: enabled ? service.initialize : null)
            else if (service.restartRequired) ...[
              Text(l.syncSettingsRestart, key: const ValueKey('sync-restart')),
              const SizedBox(height: 12),
              MMButton(
                key: const ValueKey('sync-cancel-activation'),
                label: l.cancel,
                onPressed: enabled ? service.cancelActivation : null,
              ),
            ] else if (service.libraryId == null) ...[
              Text(l.syncSettingsLocal),
              if (!service.canActivate)
                Text(l.syncSettingsUnavailable)
              else ...[
                const SizedBox(height: 12),
                MMPopUpButton<bool>(
                  value: _joining,
                  semanticLabel: l.syncSettingsTitle,
                  items: [(false, l.syncSettingsNew), (true, l.syncSettingsJoin)],
                  onChanged: enabled ? (value) => setState(() => _joining = value) : null,
                ),
                Text(l.syncSettingsIdentityHint, style: context.mmText.callout),
                if (_joining) _input('sync-library-code', l.syncSettingsLibraryId, _code, enabled),
                _input('sync-device-name', l.syncSettingsDeviceName, _name, enabled),
                const SizedBox(height: 12),
                MMButton(
                  key: const ValueKey('sync-prepare'),
                  label: l.syncSettingsPrepare,
                  onPressed: enabled
                      ? () => service.activate(
                          existingLibraryId: _joining ? _code.text.trim() : null,
                          deviceName: _name.text,
                        )
                      : null,
                ),
              ],
            ] else ...[
              Text(l.syncSettingsLibraryId, style: context.mmText.headline),
              SelectableText(service.libraryId!),
              if (service.deviceName != null) Text('${l.syncSettingsDeviceName}: ${service.deviceName}'),
              Text(l.syncDeviceNameHint, style: context.mmText.callout),
              if (_renaming) ...[
                _input('sync-rename-input', l.syncSettingsDeviceName, _name, enabled),
                Wrap(
                  spacing: 8,
                  children: [
                    MMButton(
                      key: const ValueKey('sync-rename-save'),
                      label: l.save,
                      onPressed: enabled
                          ? () async {
                              await service.renameDevice(_name.text, expectedRevision: _nameRevision);
                              if (mounted && service.failure == null) setState(() => _renaming = false);
                            }
                          : null,
                    ),
                    MMButton(label: l.cancel, onPressed: enabled ? () => setState(() => _renaming = false) : null),
                  ],
                ),
              ] else
                MMButton(
                  key: const ValueKey('sync-rename'),
                  label: l.syncDeviceRename,
                  onPressed: enabled
                      ? () {
                          _name.text = service.deviceName ?? '';
                          _nameRevision = service.devices.where((d) => d.local).firstOrNull?.revision;
                          setState(() => _renaming = true);
                        }
                      : null,
                ),
              for (final device in service.devices.where((d) => !d.local)) Text(device.name),
              if (service.deviceProblems > 0) Text(l.syncDeviceHistoryProblem),
              const SizedBox(height: 12),
              Text(service.busy ? l.syncSettingsRunning : l.syncSettingsPaused),
              if (service.target case final target?) ...[
                Text('${target.service} · ${target.location}'),
                // iCloud's account identifier is local and opaque, not a human name.
                if (target.service == 'webdav') Text(target.account),
                Text('${l.syncSettingsPending}: ${service.pending}'),
                Text(
                  target.service == 'icloud' ? l.syncDisconnectICloudHint : l.syncDisconnectHint,
                  style: context.mmText.callout,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MMButton(
                      key: const ValueKey('sync-disconnect'),
                      label: target.service == 'icloud' ? l.syncDisconnectICloud : l.syncDisconnect,
                      onPressed: enabled
                          ? () async {
                              await service.disconnect();
                              if (mounted && service.failure == null) _password.clear();
                            }
                          : null,
                    ),
                    MMButton(
                      key: const ValueKey('sync-once'),
                      label: l.syncSettingsOnce,
                      onPressed: enabled ? service.syncOnce : null,
                    ),
                  ],
                ),
              ],
              if (service.target != null) ...[
                const SizedBox(height: 16),
                Text(l.syncCopyHint, style: context.mmText.callout),
                MMButton(
                  key: const ValueKey('sync-copy-preview'),
                  label: l.syncCopyPreview,
                  onPressed: enabled ? service.previewHistoryCopy : null,
                ),
                if (service.historyCopy case final plan?) ...[
                  Text('${plan.target.service} · ${plan.target.location}'),
                  if (plan.target.service == 'webdav') Text(plan.target.account),
                  Text(
                    l.syncCopySummary(
                      plan.commits,
                      plan.otherDeviceCommits,
                      plan.chunks,
                      plan.excluded,
                      plan.unverifiedVersions,
                    ),
                  ),
                  MMButton(
                    key: const ValueKey('sync-copy-confirm'),
                    label: l.syncCopyConfirm,
                    onPressed: enabled ? () => service.copyHistory(plan) : null,
                  ),
                  MMButton(label: l.cancel, onPressed: enabled ? service.pause : null),
                ],
              ],
              if (service.busy)
                MMButton(key: const ValueKey('sync-pause'), label: l.syncSettingsPause, onPressed: service.pause),
              if (service.result case final result?) ...[
                Text('${l.syncSettingsReceived}: ${result.received}'),
                Text('${l.syncSettingsConfirmed}: ${result.confirmed}'),
                if (result.staged > 0) Text('${l.syncSettingsStaged}: ${result.staged}'),
              ],
              const SizedBox(height: 20),
              Text(l.syncResourcesTitle, style: context.mmText.headline),
              Text(l.syncResourcesHint, style: context.mmText.callout),
              const SizedBox(height: 10),
              Text(l.syncCacheHint, style: context.mmText.callout),
              MMButton(
                key: const ValueKey('sync-cache-inspect'),
                label: l.syncCacheInspect,
                onPressed: enabled ? service.inspectCache : null,
              ),
              if (service.cacheUsage case final cache?) ...[
                Text(l.syncCacheUsage(cache.bytes, cache.reclaimableBytes)),
                if (cache.staging) Text(l.syncCacheStaging),
                if (cache.incompleteHistory) Text(l.syncCacheIncomplete),
                if (cache.reclaimedBytes > 0) Text(l.syncCacheReclaimed(cache.reclaimedBytes)),
                if (cache.canReclaim)
                  MMButton(
                    key: const ValueKey('sync-cache-reclaim'),
                    label: l.syncCacheReclaim,
                    onPressed: enabled && cache.reclaimableChunks > 0 ? service.reclaimCache : null,
                  ),
              ],
              MMButton(
                key: const ValueKey('sync-resources-refresh'),
                label: l.syncSettingsRetry,
                onPressed: enabled ? service.refreshResources : null,
              ),
              for (final resource in service.resources) ...[
                const SizedBox(height: 10),
                Text(resource.title),
                Text(switch (resource.availability) {
                  SyncResourceAvailability.available => l.syncResourceAvailable,
                  SyncResourceAvailability.missing => l.syncResourceMissing,
                  SyncResourceAvailability.changed => l.syncResourceChanged,
                  SyncResourceAvailability.unverified => l.syncResourceUnverified,
                }),
                if (resource.availability == SyncResourceAvailability.missing)
                  MMButton(
                    key: ValueKey('sync-download-${resource.group}'),
                    label: l.syncResourceDownload,
                    onPressed: enabled && service.target != null ? () => service.downloadResource(resource) : null,
                  ),
              ],
              const SizedBox(height: 20),
              Text(l.syncSettingsConnectHint),
              CheckboxListTile(
                key: const ValueKey('sync-copy-destination'),
                value: _copyDestination,
                title: Text(l.syncCopyDestination),
                onChanged: enabled ? (value) => setState(() => _copyDestination = value ?? false) : null,
              ),
              if (service.canStoreSecrets) ...[
                _input('sync-directory', l.syncSettingsDirectory, _directory, enabled),
                _input('sync-account', l.syncSettingsAccount, _account, enabled),
                _input('sync-password', l.syncSettingsPassword, _password, enabled, secret: true),
                const SizedBox(height: 12),
                MMButton(
                  key: const ValueKey('sync-connect'),
                  label: l.syncSettingsConnect,
                  onPressed: enabled
                      ? () async {
                          await service.connectWebDav(
                            directory: _directory.text,
                            username: _account.text,
                            password: _password.text,
                            copyDestination: _copyDestination,
                          );
                          if (mounted && service.failure == null) _password.clear();
                        }
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              MMButton(
                key: const ValueKey('sync-icloud'),
                label: l.syncSettingsICloud,
                onPressed: enabled ? () => service.connectICloud(copyDestination: _copyDestination) : null,
              ),
            ],
          ],
        );
      },
    );
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
