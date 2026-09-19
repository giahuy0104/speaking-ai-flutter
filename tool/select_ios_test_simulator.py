"""Select an available Intel iPhone destination from xcodebuild output.

Use Xcode's eligible destinations, not the first simctl device: installed
Apple-Silicon-only runtimes cannot run MLImage's simulator binary.
"""

import re
import sys


def select_destination(output):
    eligible = output.split("Ineligible destinations", 1)[0]
    for entry in re.findall(r"\{([^{}]+)\}", eligible):
        fields = dict(
            part.strip().split(":", 1)
            for part in entry.split(",")
            if ":" in part
        )
        fields = {key.strip(): value.strip() for key, value in fields.items()}
        identifier = fields.get("id", "")
        if (
            fields.get("platform") == "iOS Simulator"
            and fields.get("arch") == "x86_64"
            and fields.get("name", "").startswith("iPhone")
            and "error" not in fields
            and re.fullmatch(r"[0-9a-fA-F-]{36}", identifier)
        ):
            return identifier
    raise ValueError(
        "No eligible x86_64 iPhone simulator. Check Rosetta and the Universal "
        "iOS runtime installation; do not fall back to an arm64 simulator."
    )


if __name__ == "__main__":
    try:
        print(select_destination(sys.stdin.read()))
    except ValueError as error:
        sys.exit(str(error))
