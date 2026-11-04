"""Real Foundation/file-coordination tests; no signed container or account used."""
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(platform.system() == "Darwin" and shutil.which("swiftc"),
                     "Apple Foundation and Swift compiler required")
class ICloudDriveStoreTests(unittest.TestCase):
    def test_store(self):
        with tempfile.TemporaryDirectory(prefix="foliarc-icloud-") as directory:
            executable = Path(directory) / "drive-store-tests"
            subprocess.run([
                "swiftc", "-swift-version", "5",
                str(ROOT / "apps/marginmind/apple/ICloudDriveStore.swift"),
                str(ROOT / "tool/tests/swift/icloud_drive_store_test.swift"),
                "-o", str(executable),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("iCloud native store tests passed", result.stdout)
