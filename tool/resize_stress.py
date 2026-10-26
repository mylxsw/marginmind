#!/usr/bin/env python3
"""Resize an already-open macOS Release app, failing on exit or AX errors.

Open a PDF first. Requires Accessibility permission for the invoking terminal.
Example: python3 tool/resize_stress.py --pid 1234 --cycles 250 > resize.jsonl
Each cycle exercises a one-point A/B/A flip and a 960x640 window
(the native toolbar raises the 600pt content minimum).
Add --fullscreen to enter/exit native fullscreen each cycle (requires Swift CLI).
This external AX driver does not reproduce in-process NSWindow timing exactly.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time


SIZES = ((1280, 820), (1279, 819), (1280, 820), (960, 640), (1280, 820))


def resize_cycle(pid, delay):
    steps = '\n'.join(
        f'set size of window 1 to {{{w}, {h}}}\n'
        f'delay {delay}\n'
        f'set end of observed to (size of window 1)' for w, h in SIZES)
    script = f'''tell application "System Events"
      set targetProcess to first process whose unix id is {pid}
      set observed to {{}}
      tell targetProcess
        {steps}
      end tell
      return observed
    end tell'''
    result = subprocess.run(['osascript', '-e', script], check=True, capture_output=True,
                            text=True, timeout=30 + delay * len(SIZES))
    values = [int(value.strip()) for value in result.stdout.split(',')]
    if len(values) != 2 * len(SIZES) or any(value <= 0 for value in values):
        raise ValueError('Invalid AX size readback: ' + result.stdout)
    sizes = list(zip(values[::2], values[1::2]))
    # AppKit can coalesce rapid requests or constrain the frame. Record the
    # actual sizes instead of treating a clamped request as an app crash.
    if len(set(sizes)) < 2:
        raise ValueError('Window did not resize during the cycle')
    return sizes


def fullscreen_cycle(pid):
    """Enter and exit native fullscreen, checking AX state after each request.

    Waiting for animation completion is deliberate: a successful AX write alone
    does not prove that AppKit switched surfaces. Never target a replacement PID.
    """
    result = subprocess.run(['swift', str(Path(__file__).with_name('ax_fullscreen.swift')), str(pid)],
                            check=True, capture_output=True, text=True, timeout=30)
    if result.stdout.strip() != 'true, false':
        raise ValueError('Invalid AX fullscreen readback: ' + result.stdout)
    return [True, False]


def log(message):
    print(message, flush=True)


def run(pid, cycles, delay, emit=log, fullscreen=False):
    started = time.monotonic()
    emit(json.dumps({'event': 'start', 'pid': pid, 'cycles': cycles,
                     'sizes': SIZES, 'delay_seconds': delay, 'fullscreen': fullscreen}))
    transitions = 0
    previous = None
    for cycle in range(1, cycles + 1):
        try:
            sizes = resize_cycle(pid, delay)
            states = fullscreen_cycle(pid) if fullscreen else []
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            emit(json.dumps({'event': 'failed', 'completed_cycles': cycle - 1,
                             'error': str(error), 'stderr': getattr(error, 'stderr', None)}))
            return 1
        for size in sizes:
            if previous is not None and previous != size:
                transitions += 1
            previous = size
        emit(json.dumps({'event': 'cycle', 'completed_cycles': cycle,
                         'resize_requests': cycle * len(SIZES), 'observed_sizes': sizes,
                         'fullscreen_states': states}))
    emit(json.dumps({'event': 'passed', 'cycles': cycles, 'resize_requests': cycles * len(SIZES),
                     'observed_transitions': transitions,
                     'fullscreen_transitions': cycles * 2 if fullscreen else 0,
                     'elapsed_seconds': round(time.monotonic() - started, 2)}))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--cycles', type=int, default=250)
    parser.add_argument('--delay', type=float, default=0.02)
    parser.add_argument('--fullscreen', action='store_true', help='enter/exit native fullscreen each cycle')
    args = parser.parse_args()
    if args.pid <= 0 or args.cycles <= 0 or not 0 <= args.delay <= 5:
        parser.error('positive PID/cycles and delay between 0 and 5 required')
    return run(args.pid, args.cycles, args.delay, fullscreen=args.fullscreen)


if __name__ == '__main__':
    raise SystemExit(main())
