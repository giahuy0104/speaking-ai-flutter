"""Select an available Apple Silicon iPhone destination from xcodebuild output."""

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
            and fields.get("arch") == "arm64"
            and fields.get("name", "").startswith("iPhone")
            and "error" not in fields
            and re.fullmatch(r"[0-9a-fA-F-]{36}", identifier)
        ):
            return identifier
    raise ValueError(
        "No eligible arm64 iPhone simulator. Check the installed iOS simulator "
        "runtime and Xcode destinations."
    )


if __name__ == "__main__":
    try:
        print(select_destination(sys.stdin.read()))
    except ValueError as error:
        sys.exit(str(error))
