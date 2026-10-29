// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'probe_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class ProbeLocalizationsZh extends ProbeLocalizations {
  ProbeLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get previous => '上一页';

  @override
  String get next => '下一页';

  @override
  String get fontSize => '字号';

  @override
  String get scroll => '滚动';

  @override
  String get benchmark => '基准';

  @override
  String get chapter => '章节';

  @override
  String get loading => '载入中';

  @override
  String get failed => '无法载入书籍';
}
