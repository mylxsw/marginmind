import 'package:flutter/widgets.dart';
import 'package:mm_design/mm_design.dart';

import '../l10n/generated/app_localizations.dart';

export '../l10n/generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppLocalizationsX on AppLocalizations {
  String colorName(MMAnnotationColor color) => switch (color) {
    MMAnnotationColor.yellow => colorYellow,
    MMAnnotationColor.green => colorGreen,
    MMAnnotationColor.blue => colorBlue,
    MMAnnotationColor.pink => colorPink,
    MMAnnotationColor.orange => colorOrange,
    MMAnnotationColor.purple => colorPurple,
  };

  /// "Just now", "3 days ago", "Last month"…
  String relativeTime(DateTime time, DateTime now) {
    final d = now.difference(time);
    if (d.inMinutes < 1) return relativeJustNow;
    if (d.inHours < 1) return relativeMinutes(d.inMinutes);
    if (d.inDays < 1) return relativeHours(d.inHours);
    if (d.inDays == 1) return relativeYesterday;
    if (d.inDays < 7) return relativeDays(d.inDays);
    if (d.inDays < 30) return relativeWeeks(d.inDays ~/ 7);
    return relativeMonths(d.inDays ~/ 30);
  }
}
