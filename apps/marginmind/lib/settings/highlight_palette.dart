import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../app/providers.dart';

class HighlightColorUse {
  const HighlightColorUse(this.count, this.lastUsed);
  final int count;
  final DateTime lastUsed;
}

class HighlightPalette {
  const HighlightPalette({this.current = MMAnnotationColor.yellow, this.usage = const {}});
  final MMAnnotationColor current;
  final Map<MMAnnotationColor, HighlightColorUse> usage;

  List<MMAnnotationColor> frequent(DateTime now) {
    // A week's inactivity halves the weight of a color's lifetime use count.
    double score(MMAnnotationColor color) {
      final use = usage[color];
      if (use == null) return 0;
      final days = now.difference(use.lastUsed).inSeconds.clamp(0, 1 << 40) / Duration.secondsPerDay;
      return use.count / (1 + days / 7);
    }

    final colors = [...MMAnnotationColor.values];
    colors.sort((a, b) {
      final weight = score(b).compareTo(score(a));
      if (weight != 0) return weight;
      final recent = (usage[b]?.lastUsed.millisecondsSinceEpoch ?? 0).compareTo(
        usage[a]?.lastUsed.millisecondsSinceEpoch ?? 0,
      );
      return recent != 0 ? recent : a.index.compareTo(b.index);
    });
    return colors.take(3).toList();
  }
}

final highlightPaletteProvider = NotifierProvider<HighlightPaletteController, HighlightPalette>(
  HighlightPaletteController.new,
);

class HighlightPaletteController extends Notifier<HighlightPalette> {
  static const _key = 'settings.highlightPalette';

  @override
  HighlightPalette build() {
    try {
      final data = jsonDecode(ref.watch(sharedPreferencesProvider).getString(_key) ?? '{}') as Map;
      final usage = <MMAnnotationColor, HighlightColorUse>{};
      for (final color in MMAnnotationColor.values) {
        final use = (data['usage'] as Map?)?[color.name];
        if (use is! Map) continue;
        final count = use['count'], last = use['last'];
        if (count is int && count > 0 && last is int) {
          usage[color] = HighlightColorUse(count, DateTime.fromMillisecondsSinceEpoch(last));
        }
      }
      return HighlightPalette(
        current:
            MMAnnotationColor.values.where((c) => c.name == data['current']).firstOrNull ?? MMAnnotationColor.yellow,
        usage: Map.unmodifiable(usage),
      );
    } catch (_) {
      return const HighlightPalette();
    }
  }

  Future<void> choose(MMAnnotationColor color) {
    state = HighlightPalette(current: color, usage: state.usage);
    return _save();
  }

  Future<void> record(MMAnnotationColor color) {
    state = HighlightPalette(
      current: color,
      usage: Map.unmodifiable({
        ...state.usage,
        color: HighlightColorUse((state.usage[color]?.count ?? 0) + 1, ref.read(clockProvider)()),
      }),
    );
    return _save();
  }

  Future<void> _save() async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _key,
          jsonEncode({
            'current': state.current.name,
            'usage': {
              for (final entry in state.usage.entries)
                entry.key.name: {'count': entry.value.count, 'last': entry.value.lastUsed.millisecondsSinceEpoch},
            },
          }),
        );
  }
}
