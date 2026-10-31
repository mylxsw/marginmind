import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppIconPreference {
  paperArc('paper_arc'),
  leafFolio('leaf_folio'),
  foldedF('folded_f');

  const AppIconPreference(this.assetName);
  final String assetName;
  String get previewAsset => 'assets/icon/$assetName.png';

  static AppIconPreference parse(String? value) => values.where((icon) => icon.name == value).firstOrNull ?? paperArc;
}

const appIconPreferenceKey = 'settings.appIcon';

/// The OS owns the installed icon on iOS; macOS restores its Dock icon each launch.
class AppIconService {
  const AppIconService();
  static const channel = MethodChannel('marginmind/app_icon');

  bool get supported => !kIsWeb && {TargetPlatform.macOS, TargetPlatform.iOS}.contains(defaultTargetPlatform);
  bool get dockOnly => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<AppIconPreference> current() async => AppIconPreference.parse(await channel.invokeMethod<String>('get'));

  Future<void> apply(AppIconPreference icon) async {
    if (!supported) throw UnsupportedError('Alternate app icons are unavailable');
    await channel.invokeMethod<void>('set', {'icon': icon.name});
  }

  Future<void> initialize(SharedPreferences prefs) async {
    if (!supported) return;
    if (dockOnly) {
      try {
        await apply(AppIconPreference.parse(prefs.getString(appIconPreferenceKey)));
      } catch (_) {
        // The running Dock may still show B if restoring A/C failed. Settings
        // must display the confirmed native state, not the requested choice.
        await prefs.setString(appIconPreferenceKey, (await current()).name);
        rethrow;
      }
    } else {
      // Avoid an icon-change system alert at startup, and honor OS state after
      // a restore/reinstall rather than assuming a backed-up preference is live.
      await prefs.setString(appIconPreferenceKey, (await current()).name);
    }
  }
}

final appIconServiceProvider = Provider<AppIconService>((ref) => const AppIconService());
