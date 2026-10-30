import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('ios_browser', Path(__file__).parents[1] / 'ios_browser_integration.py')
ios = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ios)


def device(name='iPhone 17', available=True):
    return {'name': name, 'isAvailable': available, 'deviceTypeIdentifier': f'type.{name}'}


DEVICES = {
    'com.apple.CoreSimulator.SimRuntime.iOS-9-3': [device()],
    'com.apple.CoreSimulator.SimRuntime.iOS-26-1': [device('iPad'), device('iPhone 17 Pro'), device()],
    'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [device(available=False)],
    'com.apple.CoreSimulator.SimRuntime.tvOS-27-0': [device()],
}


class IOSBrowserTests(unittest.TestCase):
    def test_selection_is_numeric_stable_and_ignores_unavailable_other_platforms(self):
        expected = ('com.apple.CoreSimulator.SimRuntime.iOS-26-1', 'type.iPhone 17')
        self.assertEqual(ios.select_device(DEVICES), expected)
        self.assertEqual(ios.select_device(dict(reversed(list(DEVICES.items())))), expected)
        with self.assertRaisesRegex(ValueError, 'No available iPhone'):
            ios.select_device({'com.apple.CoreSimulator.SimRuntime.iOS-26-1': [device('iPad')]})

    def test_run_saves_output_and_propagates_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as directory, patch('builtins.print'):
            log = Path(directory) / 'run.log'
            self.assertIn('hello', ios.run([sys.executable, '-c', 'print("hello")'], timeout=5, log=log))
            with self.assertRaises(subprocess.CalledProcessError) as error:
                ios.run([sys.executable, '-c', 'import sys; print("failed"); sys.exit(7)'], timeout=5, log=log)
            self.assertEqual(error.exception.returncode, 7)
            self.assertIn('failed', log.read_text())

    def test_timeout_kills_child_processes_and_keeps_log(self):
        with tempfile.TemporaryDirectory() as directory, patch('builtins.print'):
            marker = Path(directory) / 'orphan'
            child = f'import time; from pathlib import Path; time.sleep(0.8); Path({str(marker)!r}).touch()'
            parent = ('import subprocess,sys,time; '
                      f'subprocess.Popen([sys.executable, "-c", {child!r}]); '
                      'print("started", flush=True); time.sleep(30)')
            log = Path(directory) / 'timeout.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                ios.run([sys.executable, '-c', parent], timeout=0.3, log=log)
            self.assertIn('started', log.read_text())
            time.sleep(0.9)
            self.assertFalse(marker.exists(), 'timed-out Flutter/simctl descendants must not survive')

    def test_timeout_race_still_reaps_parent(self):
        with tempfile.TemporaryDirectory() as directory, patch('builtins.print'), \
                patch.object(ios.subprocess, 'Popen') as popen, \
                patch.object(ios.os, 'killpg', side_effect=ProcessLookupError):
            popen.return_value.wait.side_effect = [subprocess.TimeoutExpired('flutter', 1), 0]
            with self.assertRaises(subprocess.TimeoutExpired):
                ios.run(['flutter'], timeout=1, log=Path(directory) / 'race.log')
            self.assertEqual(popen.return_value.wait.call_count, 2)

    def test_macos_group_permission_error_falls_back_to_child_and_preserves_timeout(self):
        with tempfile.TemporaryDirectory() as directory, patch('builtins.print'), \
                patch.object(ios.subprocess, 'Popen') as popen, \
                patch.object(ios.os, 'killpg', side_effect=PermissionError):
            popen.return_value.wait.side_effect = [subprocess.TimeoutExpired('simctl', 1), 0]
            with self.assertRaises(subprocess.TimeoutExpired):
                ios.run(['simctl'], timeout=1, log=Path(directory) / 'permission.log')
            popen.return_value.kill.assert_called_once_with()
            self.assertEqual(popen.return_value.wait.call_count, 2)

    def invoke_main(self, *, failures=(), devices=None):
        calls = []

        def run(command, *, timeout, log, cwd):
            name = log.stem
            calls.append((name, command, timeout, cwd))
            if name in failures:
                raise subprocess.TimeoutExpired(command, timeout)
            if name == 'devices':
                return json.dumps({'devices': DEVICES if devices is None else devices})
            if name == 'create':
                return 'fresh-udid\n'
            return 'All tests passed!'

        with tempfile.TemporaryDirectory() as directory, patch.object(ios, 'OUT', Path(directory)), \
                patch.object(ios, 'run', side_effect=run), patch('builtins.print'):
            result = ios.main()
        return result, calls

    def test_full_run_uses_fresh_udid_bounded_boot_launch_and_cleanup(self):
        result, calls = self.invoke_main()
        self.assertEqual(result, 0)
        self.assertEqual([call[0] for call in calls],
                         ['devices', 'create', 'boot', 'simulator', 'bootstatus', 'flutter', 'shutdown', 'delete'])
        commands = {name: command for name, command, _, _ in calls}
        self.assertEqual(commands['create'][-2:], ['type.iPhone 17', 'com.apple.CoreSimulator.SimRuntime.iOS-26-1'])
        self.assertIn('fresh-udid', commands['simulator'])
        self.assertIn('fresh-udid', commands['flutter'])
        self.assertIn('--verbose', commands['flutter'])
        for _, _, timeout, _ in calls:
            self.assertGreater(timeout, 0)
            self.assertLessEqual(timeout, 900)
        self.assertEqual(next(cwd for name, _, _, cwd in calls if name == 'flutter'), ios.ROOT / 'apps/marginmind')

    def test_boot_or_launch_timeout_fails_without_retry_and_collects_diagnostics(self):
        for failure in ['bootstatus', 'flutter']:
            with self.subTest(failure=failure):
                result, calls = self.invoke_main(failures=[failure])
                names = [call[0] for call in calls]
                self.assertEqual(result, 1)
                self.assertEqual(names.count(failure), 1)
                self.assertEqual(names[-4:], ['state', 'system', 'shutdown', 'delete'])

    def test_diagnostic_and_cleanup_errors_preserve_failure(self):
        result, calls = self.invoke_main(failures=['flutter', 'state', 'system', 'shutdown', 'delete'])
        self.assertEqual(result, 1)
        self.assertEqual([call[0] for call in calls][-4:], ['state', 'system', 'shutdown', 'delete'])

    def test_missing_runtime_or_failed_creation_never_operates_on_an_unowned_device(self):
        result, calls = self.invoke_main(devices={})
        self.assertEqual(result, 1)
        self.assertEqual([call[0] for call in calls], ['devices'])
        result, calls = self.invoke_main(failures=['create'])
        self.assertEqual(result, 1)
        self.assertEqual([call[0] for call in calls], ['devices', 'create'])


if __name__ == '__main__':
    unittest.main()
