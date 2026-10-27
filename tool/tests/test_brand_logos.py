import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import io

spec = importlib.util.spec_from_file_location('brand_logos', Path(__file__).parents[1] / 'brand_logos.py')
logos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(logos)


class BrandLogoTests(unittest.TestCase):
    def test_relative_commands_become_absolute(self):
        lines = logos.to_dart('M1 2h3v4l-1-1H0V0z')
        self.assertEqual(
            lines,
            ['p.moveTo(1, 2);', 'p.lineTo(4, 2);', 'p.lineTo(4, 6);', 'p.lineTo(3, 5);', 'p.lineTo(0, 5);',
             'p.lineTo(0, 0);', 'p.close();'],
        )

    def test_implicit_line_after_move_and_reflected_curves(self):
        lines = logos.to_dart('m1 1 2 0c1 0 2 1 2 2s1 2 2 2q1 0 1 1t1 1')
        self.assertEqual(lines[1], 'p.lineTo(3, 1);')
        self.assertEqual(lines[2], 'p.cubicTo(4, 1, 5, 2, 5, 3);')
        # S reflects the previous second control point (5, 2) about (5, 3).
        self.assertEqual(lines[3], 'p.cubicTo(5, 4, 6, 5, 7, 5);')
        self.assertEqual(lines[4], 'p.quadraticBezierTo(8, 5, 8, 6);')
        self.assertEqual(lines[5], 'p.quadraticBezierTo(8, 7, 9, 7);')

    def test_smooth_curves_without_previous_control_start_at_the_point(self):
        self.assertEqual(logos.to_dart('M0 0S1 1 2 2')[1], 'p.cubicTo(0, 0, 1, 1, 2, 2);')
        self.assertEqual(logos.to_dart('M0 0T2 2')[1], 'p.quadraticBezierTo(0, 0, 2, 2);')

    def test_compact_arc_flags_are_split(self):
        lines = logos.to_dart('M0 0a.5.5 0 01.5.5A1 1 0 1 0 3 3')
        self.assertEqual(
            lines[1],
            'p.arcToPoint(Offset(0.5, 0.5), radius: Radius.elliptical(0.5, 0.5), rotation: 0, largeArc: false, '
            'clockwise: true);',
        )
        self.assertIn('largeArc: true, clockwise: false', lines[2])

    def test_errors(self):
        with self.assertRaises(ValueError):
            logos.to_dart('1 2')
        with self.assertRaises(ValueError):
            logos.to_dart('M1')
        with self.assertRaises(ValueError):
            logos.path_data('<svg><path d="M0 0"/><path d="M1 1"/></svg>')
        with self.assertRaises(ValueError):
            logos.to_dart('M0 0a1 1 0 0 1')

    def test_main_writes_one_function_per_mark(self):
        with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as f:
            f.write('<svg viewBox="0 0 24 24"><path d="M0 0H24V24Z"/></svg>')
        out = io.StringIO()
        with patch.object(logos.sys, 'stdout', out):
            self.assertEqual(logos.main([f'box={f.name}']), 0)
        Path(f.name).unlink()
        text = out.getvalue()
        self.assertIn('Path boxMark() {', text)
        self.assertIn('  p.lineTo(24, 24);', text)
        self.assertIn("import 'dart:ui';", text)


if __name__ == '__main__':
    unittest.main()
