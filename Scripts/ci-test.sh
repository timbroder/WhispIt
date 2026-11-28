#!/usr/bin/env bash
# Builds and runs the CI test suites on an iOS simulator. Used by
# .github/workflows/ci.yml and runnable locally:
#
#   Scripts/ci-test.sh [simulator-udid]
#
# Signs ad hoc (no Apple team or certificates needed). Simulator builds
# still embed entitlements, so App Group tests run.
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
def version(key):
    return [int(p) for p in key.split("iOS-")[-1].split("-") if p.isdigit()]
runtimes = sorted((k for k in devices if "iOS" in k and devices[k]), key=version)
phones = [d for d in devices[runtimes[-1]] if d["name"].startswith("iPhone")]
print(phones[-1]["udid"])')
fi
echo "Simulator: $(xcrun simctl list devices | grep "$UDID")"

OUT="${CI_RESULTS_DIR:-build/results}"
DERIVED="${CI_DERIVED_DATA:-build/DerivedData}"
rm -rf "$OUT"; mkdir -p "$OUT"
SIGNING=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER=)
COMMON=(-project WhispIt.xcodeproj -scheme WhispItApp -destination "id=$UDID" -derivedDataPath "$DERIVED")

command -v xcodegen >/dev/null && xcodegen generate --quiet

xcodebuild build-for-testing "${COMMON[@]}" -skipPackagePluginValidation -skipMacroValidation \
  "${SIGNING[@]}" -quiet

# Unit + keyboard logic: hermetic, except BackgroundAudioSessionManagerTests,
# which start a real AVAudioEngine. On hosted runners the simulator's audio
# server sometimes deadlocks on the first engine starts ("Cleanup: RPC
# timeout. Apparently deadlocked. Aborting now.") and kills the test host.
# A retry in a fresh process gets past it; a real failure fails both times.
xcodebuild test-without-building "${COMMON[@]}" \
  -only-testing:WhispItTests -only-testing:WhispItKeyboardTests \
  -retry-tests-on-failure -test-iterations 2 \
  -resultBundlePath "$OUT/unit.xcresult" "${SIGNING[@]}"

# UI tests. Full onboarding downloads a model and needs a simulator mic, so
# it only runs when WHISPIT_FULL_ONBOARDING=1 (it skips itself otherwise).
xcodebuild test-without-building "${COMMON[@]}" \
  -only-testing:WhispItUITests -retry-tests-on-failure -test-iterations 2 \
  -resultBundlePath "$OUT/ui.xcresult" "${SIGNING[@]}"
