import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/settings_window.dart' show SettingsPage;
import '../../../shared/l10n.dart';
import '../assistant_services.dart';
import '../assistant_settings.dart';
import '../../../settings/settings_save_actions.dart';

/// Checks a search backend; tests replace it to stay off the network.
typedef WebSearchChecker = Future<ConnectionStatus> Function(
  SearchProvider provider, {
  CancellationToken? cancellation,
});

final webSearchCheckerProvider = Provider<WebSearchChecker>((ref) => checkWebSearch);

/// Settings › Web Search: which service searches the web, independent of
/// the model that answers.
class WebSearchSettingsPage extends ConsumerStatefulWidget {
  const WebSearchSettingsPage({super.key});

  @override
  ConsumerState<WebSearchSettingsPage> createState() => _WebSearchSettingsPageState();
}

class _WebSearchSettingsPageState extends ConsumerState<WebSearchSettingsPage> {
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _account = TextEditingController();
  CancellationToken? _check;
  late WebSearchBackend _backend;
  bool _checking = false, _saving = false, _dirty = false, _saved = false, _saveFailed = false;
  bool _keyEdited = false, _accountEdited = false;
  int _load = 0;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _backend = ref.read(webSearchSettingsProvider).backend;
    _endpoint.text = ref.read(webSearchSettingsProvider).endpoint;
    unawaited(_loadSecrets(ref.read(webSearchSettingsProvider).backend));
  }

  void _cancelCheck() {
    _check?.cancel();
    _check = null;
  }

  @override
  void dispose() {
    _cancelCheck();
    _endpoint.dispose();
    _key.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _loadSecrets(WebSearchBackend backend) async {
    final load = ++_load;
    if (backend == WebSearchBackend.none || backend == WebSearchBackend.searxng) return;
    final secrets = ref.read(assistantSecretsProvider);
    try {
      final key = await secrets.read(WebSearchSettingsController.account(backend));
      final account = backend == WebSearchBackend.cloudflare
          ? await secrets.read(WebSearchSettingsController.cloudflareAccount)
          : null;
      if (!mounted || _backend != backend || load != _load) return;
      if (!_keyEdited) _key.text = key ?? '';
      if (!_accountEdited) _account.text = account ?? '';
    } on ResearchFailure {
      if (mounted && _backend == backend && load == _load) {
        setState(() => _failure = context.l10n.assistantSavedKeyUnavailable);
      }
    }
  }

  Future<void> _choose(WebSearchBackend backend) async {
    _cancelCheck();
    setState(() {
      _backend = backend;
      _checking = false;
      _failure = null;
      _dirty = true;
      _saved = _saveFailed = false;
      _keyEdited = _accountEdited = false;
      _key.clear();
      _account.clear();
    });
    await _loadSecrets(backend);
  }

  void _changed(String field) {
    _cancelCheck();
    if (field == 'search-key') _keyEdited = true;
    if (field == 'search-account') _accountEdited = true;
    setState(() {
      _checking = false;
      _failure = null;
      _dirty = true;
      _saved = _saveFailed = false;
    });
  }

  /// Whether every field the backend needs is filled in.
  bool _complete(WebSearchBackend backend) => switch (backend) {
    WebSearchBackend.none => false,
    WebSearchBackend.searxng => _endpoint.text.trim().isNotEmpty,
    WebSearchBackend.cloudflare => _key.text.trim().isNotEmpty && _account.text.trim().isNotEmpty,
    _ => _key.text.trim().isNotEmpty,
  };

  Future<void> _saveAndCheck() async {
    if (_saving) return;
    final l = context.l10n;
    final backend = _backend;
    if (backend != WebSearchBackend.none && !_complete(backend)) {
      setState(() => _failure = l.settingsRequiredFields);
      return;
    }
    final settings = WebSearchSettings(backend: backend, endpoint: _endpoint.text.trim());
    final key = _key.text.trim(), account = _account.text.trim();
    _cancelCheck();
    setState(() {
      _saving = true;
      _saveFailed = false;
      _failure = null;
    });
    try {
      // Verify credentials before publishing the selected search backend.
      if (backend != WebSearchBackend.none && backend != WebSearchBackend.searxng) {
        await ref
            .read(webSearchSettingsProvider.notifier)
            .saveKey(backend, key, accountId: backend == WebSearchBackend.cloudflare ? account : null);
      }
      await ref.read(webSearchSettingsProvider.notifier).configure(settings);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
          _failure = l.settingsSaveFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
      _saved = true;
    });
    if (!_complete(backend)) return;
    final token = _check = CancellationToken();
    setState(() => _checking = true);
    ConnectionStatus status;
    try {
      final provider = configuredWebSearchProvider(settings: settings, key: key, accountId: account);
      status = await ref.read(webSearchCheckerProvider)(provider, cancellation: token);
    } on ResearchFailure catch (e) {
      if (e.kind == ResearchFailureKind.cancelled) return;
      status = ConnectionStatus.unreachable; // An address the policy refuses.
    }
    if (!mounted || !identical(token, _check)) return;
    setState(() {
      _checking = false;
      _failure = switch (status) {
        ConnectionStatus.ok => null,
        ConnectionStatus.authFailed =>
          backend == WebSearchBackend.cloudflare ? l.settingsTokenInvalid : l.assistantErrorKey,
        ConnectionStatus.unreachable => l.settingsSearchUnreachable,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final backend = _backend;
    MMSettingsRow input(
      String label,
      TextEditingController controller,
      String key, {
      required String hint,
      bool secret = false,
    }) => MMSettingsRow(
      label: label,
      trailing: MMTextField.settings(
        key: ValueKey(key),
        controller: controller,
        obscureText: secret,
        enabled: !_saving,
        placeholder: hint,
        semanticLabel: label,
        onChanged: (_) => _changed(key),
      ),
    );
    return SettingsPage(
      key: const ValueKey('settings-web-search'),
      children: [
        const SizedBox(height: MMSpacing.s),
        MMSettingsGroup(
          children: [
            MMSettingsRow(
              label: l.settingsSearchService,
              trailing: MMPopUpButton<WebSearchBackend>(
                key: const ValueKey('search-backend'),
                value: backend,
                semanticLabel: l.settingsSearchService,
                onChanged: _saving ? null : (b) => unawaited(_choose(b)),
                items: [
                  (WebSearchBackend.none, l.settingsSearchUnconfigured),
                  (WebSearchBackend.cloudflare, 'Cloudflare'),
                  (WebSearchBackend.searxng, 'SearXNG'),
                  (WebSearchBackend.tavily, 'Tavily'),
                  (WebSearchBackend.brave, 'Brave Search'),
                ],
              ),
            ),
            if (backend == WebSearchBackend.searxng)
              input(l.settingsAddress, _endpoint, 'search-endpoint', hint: 'http://localhost:8080'),
            if (backend == WebSearchBackend.cloudflare) ...[
              input(l.settingsAccountId, _account, 'search-account', hint: l.settingsAccountIdPlaceholder),
              input('API Token', _key, 'search-key', hint: l.settingsApiTokenPlaceholder, secret: true),
            ],
            if (backend == WebSearchBackend.tavily || backend == WebSearchBackend.brave)
              input('API Key', _key, 'search-key', hint: l.assistantPasteKey, secret: true),
            if (_checking || _failure != null)
              MMSettingsRow(
                height: 32,
                trailing: _checking
                    ? const SizedBox(width: 10, height: 10, child: CupertinoActivityIndicator(radius: 5))
                    : Row(
                        key: const ValueKey('search-failure'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(MMIcons.warning, size: 11, color: c.critical),
                          const SizedBox(width: MMSpacing.xs),
                          Flexible(
                            child: Text(_failure!, style: t.footnote.copyWith(color: c.critical)),
                          ),
                        ],
                      ),
              ),
          ],
        ),
        const SizedBox(height: MMSpacing.m),
        SettingsSaveActions(
          buttonKey: const ValueKey('search-save'),
          dirty: _dirty,
          saving: _saving,
          saved: _saved,
          failed: _saveFailed,
          onSave: _saveAndCheck,
        ),
      ],
    );
  }
}
