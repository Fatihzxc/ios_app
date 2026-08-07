#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to select an iPhone simulator." >&2
    exit 1
fi

xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
for runtime_identifier, runtime_devices in devices.items():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            runtime_parts = runtime_identifier.rsplit(".SimRuntime.", 1)[-1].split("-")
            runtime_name = "{} {}".format(runtime_parts[0], ".".join(runtime_parts[1:]))
            print(
                "Selected simulator model: {}; runtime: {} ({}); UDID: {}".format(
                    device["name"], runtime_name, runtime_identifier, device["udid"]
                ),
                file=sys.stderr,
            )
            print("platform=iOS Simulator,id={}".format(device["udid"]))
            raise SystemExit(0)

print("No available iPhone simulator found.", file=sys.stderr)
raise SystemExit(1)
'
