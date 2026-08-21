#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to select an iPhone simulator." >&2
    exit 1
fi

mode="default"
if (( $# > 0 )); then
    if (( $# != 1 )) || [[ "$1" != "--small" ]]; then
        echo "Usage: $0 [--small]" >&2
        exit 2
    fi
    mode="small"
fi

xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
mode = sys.argv[1]
candidates = []
for runtime_identifier, runtime_devices in devices.items():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append((runtime_identifier, device))

if mode == "small":
    preferred_names = ["iPhone SE (3rd generation)", "iPhone 13 mini"]
    candidates = [
        candidate for preferred_name in preferred_names
        for candidate in candidates
        if candidate[1].get("name") == preferred_name
    ]

if not candidates:
    description = "small iPhone" if mode == "small" else "iPhone"
    print("No available {} simulator found.".format(description), file=sys.stderr)
    raise SystemExit(1)

runtime_identifier, device = candidates[0]
runtime_parts = runtime_identifier.rsplit(".SimRuntime.", 1)[-1].split("-")
runtime_name = "{} {}".format(runtime_parts[0], ".".join(runtime_parts[1:]))
print(
    "Selected simulator model: {}; runtime: {} ({}); UDID: {}".format(
        device["name"], runtime_name, runtime_identifier, device["udid"]
    ),
    file=sys.stderr,
)
print("platform=iOS Simulator,id={}".format(device["udid"]))
' "$mode"
