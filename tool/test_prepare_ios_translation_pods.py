import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from prepare_ios_translation_pods import (
    STUB_DEFINE, STUB_ENV, build_environment, prepare, verify_spec,
)


def spec(stub):
    return {
        "dependencies": {"Flutter": [], **({} if stub else {"GoogleMLKit/Translate": ["~> 9.0.0"]})},
        "pod_target_xcconfig": {
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) " + (STUB_DEFINE if stub else ""),
        },
    }


class TranslationPodsTest(unittest.TestCase):
    def test_device_clears_inherited_simulator_flag(self):
        initial = {STUB_ENV: "1", "PATH": "tools"}
        self.assertEqual(build_environment("device", initial), {"PATH": "tools"})
        self.assertEqual(initial[STUB_ENV], "1")

    def test_simulator_sets_stub(self):
        self.assertEqual(build_environment("simulator", {})[STUB_ENV], "1")

    def test_valid_modes(self):
        verify_spec(spec(True), "simulator")
        verify_spec(spec(False), "device")

    def test_device_rejects_stub_or_missing_sdk(self):
        for invalid in (spec(True), {"dependencies": {"Flutter": []}}):
            with self.assertRaises(ValueError):
                verify_spec(invalid, "device")

    def test_simulator_rejects_device_sdk_or_inconsistent_define(self):
        with self.assertRaises(ValueError):
            verify_spec(spec(False), "simulator")
        invalid = spec(True)
        invalid["dependencies"]["GoogleMLKit/Translate"] = []
        with self.assertRaises(ValueError):
            verify_spec(invalid, "simulator")

    def test_prepare_forces_local_pod_resolution_and_checks_installed_spec(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            ios = project / "ios"
            local = ios / "Pods" / "Local Podspecs"
            local.mkdir(parents=True)
            (ios / "Podfile").write_text("", encoding="utf-8")
            (ios / "Podfile.lock").write_text(
                "PODS:\n  - google_mlkit_translation (0.15.1):\n", encoding="utf-8",
            )
            (local / "google_mlkit_translation.podspec.json").write_text(
                json.dumps(spec(False)), encoding="utf-8",
            )
            with patch("prepare_ios_translation_pods.subprocess.run") as run:
                prepare("device", project)
            self.assertEqual(run.call_args.args[0], ["pod", "update", "google_mlkit_translation"])
            self.assertEqual(run.call_args.kwargs["cwd"], ios.resolve())
            self.assertNotIn(STUB_ENV, run.call_args.kwargs["env"])
            self.assertTrue(run.call_args.kwargs["check"])

    def test_clean_checkout_installs_pods_before_any_named_update(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            ios = project / "ios"
            local = ios / "Pods" / "Local Podspecs"
            local.mkdir(parents=True)
            (ios / "Podfile").write_text("", encoding="utf-8")
            (local / "google_mlkit_translation.podspec.json").write_text(
                json.dumps(spec(True)), encoding="utf-8",
            )
            with patch("prepare_ios_translation_pods.subprocess.run") as run:
                prepare("simulator", project)
            self.assertEqual(run.call_args.args[0], ["pod", "install"])
            self.assertEqual(run.call_args.kwargs["env"][STUB_ENV], "1")

    def test_invalid_mode_rejected(self):
        with self.assertRaises(ValueError):
            build_environment("release", {})


@unittest.skipUnless(shutil.which("pod"), "CocoaPods is unavailable")
class TranslationPodspecIntegrationTest(unittest.TestCase):
    def test_real_podspec_loads_for_simulator_and_device(self):
        podspec = (
            Path(__file__).resolve().parent.parent
            / "third_party/google_mlkit_translation/ios/google_mlkit_translation.podspec"
        )
        for mode in ("simulator", "device"):
            with self.subTest(mode=mode):
                result = subprocess.run(
                    ["pod", "ipc", "spec", str(podspec)],
                    env=build_environment(mode), check=True,
                    capture_output=True, text=True,
                )
                loaded = json.loads(result.stdout)
                verify_spec(loaded, mode)
                self.assertEqual(loaded["pod_target_xcconfig"]["DEFINES_MODULE"], "YES")


if __name__ == "__main__":
    unittest.main()
