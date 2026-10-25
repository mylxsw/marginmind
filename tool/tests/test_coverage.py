import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('coverage_tool', Path(__file__).parents[1] / 'coverage.py')
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class CoverageTest(unittest.TestCase):
    def test_normalizes_and_merges_duplicate_source_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / 'first.info'
            second = root / 'second.info'
            first.write_text('SF:lib/a.dart\nDA:1,0\nDA:2,2\nend_of_record\n')
            second.write_text(f'SF:{root}/packages/mm_core/lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n'
                              'SF:/pub/cache/external.dart\nDA:1,1\nend_of_record\n')
            lines = coverage.merge([('packages/mm_core', first), ('apps/marginmind', second)], root)
            self.assertEqual(lines, {('packages/mm_core/lib/a.dart', 1): 1, ('packages/mm_core/lib/a.dart', 2): 2})
            output = root / 'out/lcov.info'
            coverage.write_lcov(lines, output)
            self.assertIn('LF:2\nLH:2\n', output.read_text())

    def test_gate_accepts_80_percent_and_rejects_below_threshold(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / 'packages/mm_core/coverage/lcov.info'
            report.parent.mkdir(parents=True)
            for covered, expected in [(4, 0), (3, 1)]:
                report.write_text('SF:lib/a.dart\n' + ''.join(
                    f'DA:{number},{int(number <= covered)}\n' for number in range(1, 6)
                ) + 'end_of_record\n')
                with patch.object(coverage, 'ROOT', root), patch.object(coverage, 'PACKAGES', {'packages/mm_core': 'dart'}), \
                        patch('sys.argv', ['coverage.py', '--report-only']), patch('builtins.print'), \
                        patch.dict(coverage.os.environ, {}, clear=True):
                    self.assertEqual(coverage.main(), expected)
                self.assertTrue((root / 'coverage/lcov.info').exists())
                self.assertIn(f'{covered * 20:.2f}%', (root / 'coverage/summary.md').read_text())

    def test_missing_or_empty_reports_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / 'empty.info'
            with self.assertRaises(FileNotFoundError):
                coverage.merge([('packages/mm_core', report)], root)
            report.write_text('')
            with self.assertRaises(ValueError):
                coverage.merge([('packages/mm_core', report)], root)
            with self.assertRaises(ValueError):
                coverage.merge([], root)


if __name__ == '__main__':
    unittest.main()
