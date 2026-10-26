"""Install and verify the correct translation adapter before an iOS build.

The Google binary supports iPhone arm64, not arm64 Simulator. Simulator tests
explicitly report translation unavailable. A device build must reinstall the
real dependency; the Swift stub also refuses to compile for an iPhone.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess


STUB_ENV = "HOMI_IOS_TRANSLATION_SIMULATOR_STUB"
STUB_DEFINE = "HOMI_TRANSLATION_SIMULATOR_STUB"
PLUGIN = "google_mlkit_translation"


def build_environment(mode, environment=None):
    if mode not in ("simulator", "device"):
        raise ValueError("Expected simulator or device")
    env = dict(os.environ if environment is None else environment)
    if mode == "simulator":
        env[STUB_ENV] = "1"
    else:
        env.pop(STUB_ENV, None)
    return env


def verify_spec(spec, mode):
    env = build_environment(mode, {})
    dependencies = spec.get("dependencies", {})
    settings = spec.get("pod_target_xcconfig", {})
    stub = STUB_DEFINE in settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
    sdk = "GoogleMLKit/Translate" in dependencies
    expected_stub = STUB_ENV in env
    if stub != expected_stub or sdk == expected_stub:
        raise ValueError(f"Translation Pods do not match {mode}; refusing to build")


def prepare(mode, project):
    ios = Path(project).resolve() / "ios"
    if not (ios / "Podfile").is_file():
        raise ValueError("Missing project iOS Podfile")
    # Force evaluation of this local podspec even after switching between SDKs.
    # An ordinary pod install may retain its previously resolved dependencies.
    lock = ios / "Podfile.lock"
    locked_plugin = lock.is_file() and re.search(
        r"(?m)^\s+- google_mlkit_translation \(", lock.read_text(encoding="utf-8"),
    )
    command = ["pod", "update", PLUGIN] if locked_plugin else ["pod", "install"]
    subprocess.run(
        command, cwd=ios,
        env=build_environment(mode), check=True,
    )
    spec_path = ios / "Pods" / "Local Podspecs" / f"{PLUGIN}.podspec.json"
    verify_spec(json.loads(spec_path.read_text(encoding="utf-8")), mode)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("simulator", "device"))
    parser.add_argument("--project", default=str(Path(__file__).resolve().parent.parent))
    args = parser.parse_args()
    prepare(args.mode, args.project)
