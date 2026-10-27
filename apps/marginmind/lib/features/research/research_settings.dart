import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_research/mm_research.dart';

import '../../app/providers.dart';

/// Which AI service answers. Each keeps its own API key in the Keychain.
enum ResearchService { none, anthropic, openai, compatible }

/// Research preferences: the service, its model and limits, and whether the
/// launcher shows what will be sent. The API key itself is never stored
/// here, only whether one was saved.
class ResearchSettings {
  const ResearchSettings({
    this.service = ResearchService.none,
    this.model = '',
    this.endpoint = '',
    this.searches = 3,
    this.pages = 5,
    this.minutes = 2,
    this.showContext = true,
    this.keySaved = false,
  });

  static const anthropicModel = 'claude-opus-5-5';
  static const maxSearches = 10;
  static const maxPages = 12;
  static const maxMinutes = 5;

  final ResearchService service;

  /// Empty means the service's default (Anthropic only); the others need one.
  final String model;

  /// Full chat/completions URL of an OpenAI-compatible service.
  final String endpoint;
  final int searches;
  final int pages;
  final int minutes;
  final bool showContext;

  /// A key for [service] is in the Keychain.
  final bool keySaved;

  Uri? get endpointUri {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasAuthority || !(uri.scheme == 'https' || (uri.scheme == 'http' && _local(uri)))) {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(
      path: path.isEmpty
          ? '/v1/chat/completions'
          : path.endsWith('/v1')
          ? '$path/chat/completions'
          : path,
    );
  }

  static bool _local(Uri uri) => uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

  /// Whether "Ask AI" and "Answer from sources" can run.
  bool get aiConfigured => switch (service) {
    ResearchService.none => false,
    ResearchService.anthropic => keySaved,
    ResearchService.openai => keySaved && model.trim().isNotEmpty,
    // A local service may need no key.
    ResearchService.compatible => endpointUri != null && model.trim().isNotEmpty && (keySaved || _local(endpointUri!)),
  };

  /// Web research needs the service's own search tools.
  bool get webAvailable => aiConfigured && service != ResearchService.compatible;

  ResearchBudget get budget => ResearchBudget(
    searches: searches,
    pages: pages,
    duration: Duration(minutes: minutes),
  );

  ResearchSettings copyWith({
    ResearchService? service,
    String? model,
    String? endpoint,
    int? searches,
    int? pages,
    int? minutes,
    bool? showContext,
    bool? keySaved,
  }) => ResearchSettings(
    service: service ?? this.service,
    model: model ?? this.model,
    endpoint: endpoint ?? this.endpoint,
    searches: searches ?? this.searches,
    pages: pages ?? this.pages,
    minutes: minutes ?? this.minutes,
    showContext: showContext ?? this.showContext,
    keySaved: keySaved ?? this.keySaved,
  );
}

/// API keys: the macOS Keychain. Tests put an in-memory store here.
final researchSecretStoreProvider = Provider<SecretStore>((ref) => const KeychainSecretStore());

/// Opens source pages and external searches in the browser.
final researchLinksProvider = Provider<ExternalLinks>((ref) => const ExternalLinks());

class ResearchSettingsController extends Notifier<ResearchSettings> {
  static const _prefix = 'research.';

  @override
  ResearchSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final service =
        ResearchService.values.where((s) => s.name == prefs.getString('${_prefix}service')).firstOrNull ??
        ResearchService.none;
    return ResearchSettings(
      service: service,
      model: prefs.getString('${_prefix}model.${service.name}') ?? '',
      endpoint: prefs.getString('${_prefix}endpoint') ?? '',
      searches: (prefs.getInt('${_prefix}searches') ?? 3).clamp(1, ResearchSettings.maxSearches),
      pages: (prefs.getInt('${_prefix}pages') ?? 5).clamp(1, ResearchSettings.maxPages),
      minutes: (prefs.getInt('${_prefix}minutes') ?? 2).clamp(1, ResearchSettings.maxMinutes),
      showContext: prefs.getBool('${_prefix}showContext') ?? true,
      keySaved: prefs.getBool('${_prefix}key.${service.name}') ?? false,
    );
  }

  Future<void> setService(ResearchService service) async {
    await ref.read(sharedPreferencesProvider).setString('${_prefix}service', service.name);
    ref.invalidateSelf();
  }

  Future<void> setModel(String model) async {
    await ref.read(sharedPreferencesProvider).setString('${_prefix}model.${state.service.name}', model.trim());
    state = state.copyWith(model: model.trim());
  }

  Future<void> setEndpoint(String endpoint) async {
    await ref.read(sharedPreferencesProvider).setString('${_prefix}endpoint', endpoint.trim());
    state = state.copyWith(endpoint: endpoint.trim());
  }

  Future<void> setLimits({int? searches, int? pages, int? minutes}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final next = state.copyWith(
      searches: searches?.clamp(1, ResearchSettings.maxSearches),
      pages: pages?.clamp(1, ResearchSettings.maxPages),
      minutes: minutes?.clamp(1, ResearchSettings.maxMinutes),
    );
    await prefs.setInt('${_prefix}searches', next.searches);
    await prefs.setInt('${_prefix}pages', next.pages);
    await prefs.setInt('${_prefix}minutes', next.minutes);
    state = next;
  }

  Future<void> setShowContext(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool('${_prefix}showContext', value);
    state = state.copyWith(showContext: value);
  }

  /// Saves [key] for the current service in the Keychain; an empty key
  /// removes it. Throws [ResearchFailure] when the Keychain refuses.
  Future<void> saveKey(String key) async {
    final service = state.service;
    if (service == ResearchService.none) return;
    final store = ref.read(researchSecretStoreProvider);
    final value = key.trim();
    if (value.isEmpty) {
      await store.delete(service.name);
    } else {
      await store.write(service.name, value);
    }
    await ref.read(sharedPreferencesProvider).setBool('${_prefix}key.${service.name}', value.isNotEmpty);
    if (state.service == service) state = state.copyWith(keySaved: value.isNotEmpty);
  }
}

final researchSettingsProvider = NotifierProvider<ResearchSettingsController, ResearchSettings>(
  ResearchSettingsController.new,
);

/// Builds the configured AI service with its key, read from the Keychain
/// only when a request is about to be made. Null when none is configured.
final researchAiFactoryProvider = Provider<Future<AiProvider?> Function()>((ref) {
  return () async {
    final settings = ref.read(researchSettingsProvider);
    if (!settings.aiConfigured) return null;
    final key = settings.keySaved ? await ref.read(researchSecretStoreProvider).read(settings.service.name) : null;
    switch (settings.service) {
      case ResearchService.none:
        return null;
      case ResearchService.anthropic:
        if (key == null || key.isEmpty) return null;
        return AnthropicProvider(
          apiKey: key,
          model: settings.model.isEmpty ? ResearchSettings.anthropicModel : settings.model,
        );
      case ResearchService.openai:
        if (key == null || key.isEmpty) return null;
        return OpenAiResponsesProvider(apiKey: key, model: settings.model);
      case ResearchService.compatible:
        final endpoint = settings.endpointUri!;
        return OpenAiCompatibleProvider(
          endpoint: endpoint,
          model: settings.model,
          apiKey: key ?? '',
          allowLocalhost: ResearchSettings._local(endpoint),
        );
    }
  };
});
