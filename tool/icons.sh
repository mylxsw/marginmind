#!/usr/bin/env bash
# Regenerates the app icon artwork and every platform icon from it.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/icon/generate_icon.py
cd apps/marginmind
dart run flutter_launcher_icons
