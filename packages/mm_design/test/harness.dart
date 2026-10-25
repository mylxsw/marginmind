import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Wraps [child] in an app with the MarginMind theme.
Widget harness(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
    home: MMHudHost(
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
