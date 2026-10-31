// Simulator-only entry point for native keyboard UI checks. Does not save keys
// or send model requests. Reinstall lib/main.dart after collecting evidence.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/features/assistant/assistant_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('settings.language', 'zh');
  await prefs.setString('settings.appearance', 'light');
  await prefs.setString(
    AssistantServicesStore.settingsKey,
    jsonEncode(
      AssistantServices(
        services: [
          AssistantService(
            id: 'phone-ui-local',
            protocol: ServiceProtocol.ollama,
            name: '本机模型',
            endpoint: 'http://localhost:11434/v1/chat/completions',
            localEnabled: true,
            models: const [ServiceModel(id: 'local-model', name: '本机模型')],
          ),
        ],
        defaultModel: const ModelReference('phone-ui-local', 'local-model'),
      ).toJson(),
    ),
  );
  await app.main();
}
