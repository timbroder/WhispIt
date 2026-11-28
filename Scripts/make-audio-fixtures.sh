#!/usr/bin/env bash
# Generates the speech fixtures used by integration tests and simulator QA.
# Uses macOS text-to-speech so fixtures are reproducible and need no recording.
#
#   Scripts/make-audio-fixtures.sh [output-dir]
#
# Output: 16 kHz mono 16-bit WAV files (small enough to commit).
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/WhispItIntegrationTests/Fixtures}"
VOICE="${VOICE:-Samantha}"
mkdir -p "$OUT"

make() {
  local name="$1" text="$2"
  say -v "$VOICE" -o "$OUT/$name.wav" --file-format=WAVE --data-format=LEI16@16000 "$text"
  echo "wrote $OUT/$name.wav"
}

# Filler words to strip; meaning: ship the build on Friday.
make fillers "Um, so, basically I think we should, uh, ship the new build on Friday, you know."
# Proper nouns for dictionary-bias tests.
make proper-nouns "Please send the Kubernetes report to Anthropic and Priyanka by Thursday."
# Rare names and brand words for the speech-engine bake-off's dictionary
# biasing test (WhispIt-peu). "twist of lime" is a decoy that biasing towards
# "Tuist" must not rewrite.
make names "Ask Siobhan and Saoirse to send the Tuist config to Nguyen, and add a twist of lime for the WhispIt demo."
# Self-correction: cleanup should keep only "four o'clock".
make self-correction "Let's meet at three, no wait, let's meet at four o'clock tomorrow."
# Five seconds of silence: must not insert hallucinated text.
make silence "[[slnc 5000]]"
# A pause longer than the default 2 s silence timeout, then more speech.
make pause "This is the first part. [[slnc 3500]] This sentence comes after a long pause."
# Roughly 45 seconds of continuous speech for latency and long-input tests.
make long-passage "Good morning everyone. I wanted to give a quick update on the project before our planning meeting. \
Over the last two weeks the team finished the onboarding flow, wired up the keyboard extension, and fixed several bugs \
in the audio pipeline. We also started measuring latency from the moment you stop speaking to the moment text appears, \
and right now it sits at around two seconds on recent phones. Next sprint we plan to focus on tone adaptation for \
different apps, a symbols keyboard, and better error messages when the main app is not running. If you have feedback \
on priorities, please add it to the planning document by Wednesday afternoon so we can review it together on Thursday. \
Thanks, and have a great rest of your week."
