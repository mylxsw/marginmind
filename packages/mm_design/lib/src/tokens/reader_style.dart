import 'package:flutter/material.dart';

/// Reading colors affect page pixels only, keeping annotation colors intact.
enum MMReaderStyle {
  white(Color(0xFFFFFFFF), Color(0xFF000000)),
  dark(Color(0xFF252729), Color(0xFFE3E5E7)),
  paper(Color(0xFFF7F0DE), Color(0xFF29261F)),
  green(Color(0xFFE5F0E3), Color(0xFF202B22));

  const MMReaderStyle(this.paperColor, this.inkColor);
  final Color paperColor;
  final Color inkColor;

  ColorFilter? get pageFilter => this == white
      ? null
      : ColorFilter.matrix([
          paperColor.r - inkColor.r,
          0,
          0,
          0,
          inkColor.r * 255,
          0,
          paperColor.g - inkColor.g,
          0,
          0,
          inkColor.g * 255,
          0,
          0,
          paperColor.b - inkColor.b,
          0,
          inkColor.b * 255,
          0,
          0,
          0,
          1,
          0,
        ]);
}
