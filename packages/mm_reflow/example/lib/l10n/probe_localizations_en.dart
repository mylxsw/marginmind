// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'probe_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ProbeLocalizationsEn extends ProbeLocalizations {
  ProbeLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get fontSize => 'Font size';

  @override
  String get scroll => 'Scroll';

  @override
  String get benchmark => 'Benchmark';

  @override
  String get chapter => 'Chapter';

  @override
  String get loading => 'Loading';

  @override
  String get failed => 'Unable to load book';
}
