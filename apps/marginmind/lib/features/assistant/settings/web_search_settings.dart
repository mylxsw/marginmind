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
import 'model_settings.dart' show serviceCheckDelay;

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
  Timer? _timer;
  CancellationToken? _check;
  bool _checking = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _endpoint.text = ref.read(webSearchSettingsProvider).endpoint;
    unawaited(_loadSecrets(ref.read(webSearchSettingsProvider).backend));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _check?.cancel();
    _endpoint.dispose();
    _key.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _loadSecrets(WebSearchBackend backend) async {
    if (backend == WebSearchBackend.none || backend == WebSearchBackend.searxng) return;
    final secrets = ref.read(assistantSecretsProvider);
    try {
      final key = await secrets.read(WebSearchSettingsController.account(backend));
      final account = backend == WebSearchBackend.cloudflare
          ? await secrets.read(WebSearchSettingsController.cloudflareAccount)
          : null;
      if (!mounted || ref.read(webSearchSettingsProvider).backend != backend) return;
      _key.text = key ?? '';
      _account.text = account ?? '';
    } on ResearchFailure {
      // Saved credentials may be unavailable; users can still edit the form.
    }
  }

  Future<void> _choose(WebSearchBackend backend) async {
    _timer?.cancel();
    _check?.cancel();
    setState(() {
      _checking = false;
      _failure = null;
      _key.clear();
      _account.clear();
    });
    await ref
        .read(webSearchSettingsProvider.notifier)
        .configure(WebSearchSettings(backend: backend, endpoint: _endpoint.text.trim()));
    await _loadSecrets(backend);
  }

  void _changed(String _) {
    _timer?.cancel();
    _check?.cancel();
    setState(() => _checking = false);
    _timer = Timer(serviceCheckDelay, () => unawaited(_saveAndCheck()));
  }

  /// Whether every field the backend needs is filled in.
  bool _complete(WebSearchBackend backend) => switch (backend) {
    WebSearchBackend.none => false,
    WebSearchBackend.searxng => _endpoint.text.trim().isNotEmpty,
    WebSearchBackend.cloudflare => _key.text.trim().isNotEmpty && _account.text.trim().isNotEmpty,
    _ => _key.text.trim().isNotEmpty,
  };

  Future<void> _saveAndCheck() async {
    final l = context.l10n;
    final backend = ref.read(webSearchSettingsProvider).backend;
    final settings = WebSearchSettings(backend: backend, endpoint: _endpoint.text.trim());
    try {
      await ref.read(webSearchSettingsProvider.notifier).configure(settings);
      if (backend != WebSearchBackend.none && backend != WebSearchBackend.searxng) {
        await ref
            .read(webSearchSettingsProvider.notifier)
            .saveKey(backend, _key.text, accountId: backend == WebSearchBackend.cloudflare ? _account.text : null);
      }
    } catch (_) {
      if (mounted) setState(() => _failure = l.assistantErrorFailed);
      return;
    }
    if (!mounted) return;
    if (!_complete(backend)) {
      setState(() => _failure = null);
      return;
    }
    final token = _check = CancellationToken();
    setState(() => _checking = true);
    ConnectionStatus status;
    try {
      final provider = configuredWebSearchProvider(
        settings: settings,
        key: _key.text.trim(),
        accountId: _account.text.trim(),
      );
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
    final settings = ref.watch(webSearchSettingsProvider);
    final backend = settings.backend;
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
        placeholder: hint,
        semanticLabel: label,
        onChanged: _changed,
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
                onChanged: (b) => unawaited(_choose(b)),
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
                          Text(_failure!, style: t.footnote.copyWith(color: c.critical)),
                        ],
                      ),
              ),
          ],
        ),
      ],
    );
  }
}
