import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('resize_stress', Path(__file__).parents[1] / 'resize_stress.py')
stress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stress)


class ResizeStressTests(unittest.TestCase):
    def test_log_is_flushed_for_foreground_progress(self):
        with patch('builtins.print') as output:
            stress.log('cycle')
        output.assert_called_once_with('cycle', flush=True)

    def test_driver_targets_pid_checks_size_and_times_out(self):
        result = subprocess.CompletedProcess([], 0, '1280, 820, 1279, 819, 1280, 820, 960, 640, 1280, 820')
        with patch.object(stress.subprocess, 'run', return_value=result) as run:
            stress.resize_cycle(123, 0.02)
        args, kwargs = run.call_args
        self.assertEqual(args[0][0], 'osascript')
        self.assertIn('unix id is 123', args[0][2])
        self.assertEqual(args[0][2].count('set size of window'), 5)
        self.assertEqual(args[0][2].count('set end of observed'), 5)
        self.assertTrue(kwargs['check'])
        self.assertGreater(kwargs['timeout'], 0)

    def test_counts_only_completed_cycles(self):
        messages = []
        with patch.object(stress, 'resize_cycle', return_value=stress.SIZES) as cycle:
            self.assertEqual(stress.run(123, 3, 0.02, messages.append), 0)
        self.assertEqual(cycle.call_count, 3)
        result = json.loads(messages[-1])
        self.assertEqual(result['event'], 'passed')
        self.assertEqual(result['resize_requests'], 15)
        self.assertEqual(result['observed_transitions'], 12)

    def test_failure_never_claims_pass_or_restarts_app(self):
        for error in [subprocess.CalledProcessError(1, 'osascript', stderr='app exited'),
                      subprocess.TimeoutExpired('osascript', 30), OSError('missing osascript'), ValueError('no size changes')]:
            messages = []
            with patch.object(stress, 'resize_cycle', side_effect=[stress.SIZES, error]) as cycle:
                self.assertEqual(stress.run(123, 10, 0.02, messages.append), 1)
            self.assertEqual(cycle.call_count, 2)
            self.assertEqual(json.loads(messages[-1])['completed_cycles'], 1)
            self.assertEqual(json.loads(messages[-1])['event'], 'failed')

    def test_invalid_or_unchanged_geometry_fails(self):
        for output in ['1, 2', 'bad', '0, 1, 1, 1, 1, 1, 1, 1, 1, 1', ','.join(['1280, 820'] * 5)]:
            with patch.object(stress.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output)):
                with self.assertRaises(ValueError):
                    stress.resize_cycle(123, 0.02)

    def test_cli_validation(self):
        for args in [['--pid', '0'], ['--pid', '1', '--cycles', '0'], ['--pid', '1', '--delay', '-1']]:
            with patch('sys.argv', ['resize_stress'] + args), self.assertRaises(SystemExit):
                stress.main()
        with patch('sys.argv', ['resize_stress', '--pid', '123']), patch.object(stress, 'run', return_value=0) as run:
            self.assertEqual(stress.main(), 0)
            run.assert_called_once_with(123, 250, 0.02, fullscreen=False)

    def test_fullscreen_checks_both_states_and_fixed_pid(self):
        with patch.object(stress.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'true, false\n')) as run:
            self.assertEqual(stress.fullscreen_cycle(123), [True, False])
        command = run.call_args.args[0]
        self.assertEqual(command[0], 'swift')
        self.assertTrue(command[1].endswith('ax_fullscreen.swift'))
        self.assertEqual(command[2], '123')
        self.assertEqual(run.call_args.kwargs['timeout'], 30)
        for value in ['false, false', 'true', '']:
            with patch.object(stress.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, value)):
                with self.assertRaises(ValueError):
                    stress.fullscreen_cycle(123)

    def test_incomplete_fullscreen_cycle_is_not_counted(self):
        messages = []
        with patch.object(stress, 'resize_cycle', return_value=stress.SIZES), patch.object(
            stress, 'fullscreen_cycle', side_effect=[[True, False], subprocess.TimeoutExpired('osascript', 20)]
        ):
            self.assertEqual(stress.run(123, 2, 0.02, messages.append, fullscreen=True), 1)
        self.assertEqual(json.loads(messages[-1])['completed_cycles'], 1)
        self.assertEqual(json.loads(messages[-2])['fullscreen_states'], [True, False])
        messages.clear()
        with patch.object(stress, 'resize_cycle', return_value=stress.SIZES), patch.object(stress, 'fullscreen_cycle', return_value=[True, False]):
            self.assertEqual(stress.run(123, 2, 0.02, messages.append, fullscreen=True), 0)
        self.assertEqual(json.loads(messages[-1])['fullscreen_transitions'], 4)
