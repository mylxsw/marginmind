"""Execute the extension's real Foundation store on macOS or Linux Swift."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
class IncomingShareStoreTests(unittest.TestCase):
    def test_store(self):
        with tempfile.TemporaryDirectory(prefix="foliarc-incoming-") as directory:
            executable = Path(directory) / "share-store-tests"
            subprocess.run([
                "swiftc", str(ROOT / "apps/marginmind/ios/Shared/IncomingShareStore.swift"),
                str(ROOT / "tool/tests/swift/incoming_share_store_test.swift"),
                "-o", str(executable),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("policy passed", result.stdout)
