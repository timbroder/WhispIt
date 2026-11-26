#!/usr/bin/env bash
# Copies the speech fixtures into a simulator's WhispIt App Group container so
# the debug build can play them instead of the microphone:
#
#   Scripts/sim-install-fixtures.sh [simulator-udid|booted]
#   xcrun simctl launch --terminate-running-process booted com.whispit.app -WhispItAudioFixture fillers
#
# The app must have been installed (and launched once) on that simulator.
set -euo pipefail
DEVICE="${1:-booted}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GROUP=$(xcrun simctl get_app_container "$DEVICE" com.whispit.app group.com.whispit.shared)
mkdir -p "$GROUP/Fixtures"
cp "$ROOT"/WhispItIntegrationTests/Fixtures/*.wav "$GROUP/Fixtures/"
ls "$GROUP/Fixtures"
