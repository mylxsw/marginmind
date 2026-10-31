#!/usr/bin/env bash
# Package the approved Foliarc icon masters for all platforms.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/icon/generate_icon.py
