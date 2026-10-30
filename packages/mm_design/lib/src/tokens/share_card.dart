import 'package:flutter/painting.dart';

/// Export artwork is fixed across light and dark system appearances.
enum MMShareCardTheme {
  paper(Color(0xfffbf7ee), Color(0xff2b2a27)),
  plain(Color(0xffffffff), Color(0xff1d1d1f)),
  night(Color(0xff1c1c1e), Color(0xfff2f2f7));

  const MMShareCardTheme(this.background, this.foreground);
  final Color background, foreground;
}

abstract final class MMShareCardStyle {
  static const width = 330.0, padding = 24.0, radius = 14.0;
  static const quoteBar = 2.5, rule = .5, icon = 18.0;
  static const annotation = Color(0xffffcc00);
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4);
  static const section = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.7);
  static const body = TextStyle(fontSize: 12, height: 1.7);
  static const caption = TextStyle(fontSize: 10, height: 1.6);
  static const excerpt = TextStyle(fontFamily: 'Songti SC', fontSize: 13.5, height: 1.8);
  static const quote = TextStyle(fontFamily: 'Songti SC', fontSize: 20, height: 1.7);
  static const quotationMark = TextStyle(fontFamily: 'Songti SC', fontSize: 44, height: 1);
}
