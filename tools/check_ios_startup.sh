#!/usr/bin/env bash
# Run from apps/client on the hosted Mac. Uses a simulator, no Apple signing.
set -euo pipefail

mkdir -p build/ci
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
choices = [
    device
    for runtime in sorted(devices, reverse=True) if ".iOS-" in runtime
    for device in devices[runtime]
    if device.get("isAvailable") and device["name"].startswith("iPhone")
    and device["state"] == "Shutdown"
]
if not choices:
    raise SystemExit("No available iPhone simulator on this runner")
print(choices[0]["udid"])
')"

trap 'xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
flutter test integration_test/startup_smoke_test.dart \
  -d "$simulator_id" --no-pub --reporter expanded \
  2>&1 | tee build/ci/ios-startup.log
