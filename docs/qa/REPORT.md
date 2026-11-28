# WhispIt — QA Report

**Scope:** end-to-end QA of WhispIt 0.1.0 (main app + keyboard extension) against `WhispIt-Spec.md`, run 2026-11-26/27.
**Environment:** Xcode 27.2, iOS 27.2 simulators (iPhone 18 Pro primary, iPhone 17; layout/accessibility UI tests also on iPhone 17e and iPhone 18 Pro Max, all passing), macOS 27 on an M1 Pro host with Apple Intelligence. The production model `openai_whisper-large-v3-v20240930_turbo` was used in simulator E2E; integration tests use `openai_whisper-base.en`.
**Plan:** [`TEST_PLAN.md`](TEST_PLAN.md) · **Device follow-up:** [`device-checklist.md`](device-checklist.md)

## Summary

The keyboard dictation loop did not work at the start of this pass. Three P0 defects each broke it on their own:

1. The microphone converter kept ~1 % of the audio (H2).
2. The keyboard was never told a recording had started, so it couldn't be stopped (H1).
3. Any dictionary word made WhisperKit return an empty transcript (H12). Because the app learns words automatically, this broke dictation for everyone after a few uses.

**23 defects** were found. **20 are fixed**, each in its own PR with a regression test that fails on the old code where it could be run. The 3 still open are P3 polish. With the fixes stacked, the full loop works in the simulator with the production model: tap the mic in Safari, speak, get auto-stop or tap-stop, see "Cleaning up…", and the cleaned text is inserted with a success check.

The project went from **0 tests to 172 tests**: unit, keyboard logic, real-model integration, and XCUITest. CI is added (PR #27).

## Defects

| ID | Sev | Area | Finding | Status |
|---|---|---|---|---|
| H2 | P0 | Audio | Converter returned `.endOfStream` per buffer → 341 of ~34,133 frames kept; VAD never saw silence | Fixed #13 |
| H1 | P0 | IPC | No notification that recording started; keyboard couldn't stop a recording | Fixed #14 |
| H12 | P0 | Transcription | Any dictionary prompt → empty transcript (WhisperKit first-token check) | Fixed #16 |
| H4 | P1 | IPC | No feedback when the app isn't running or the model isn't loaded | Fixed #14 |
| H6 | P1 | Pipeline | Silent recording inserted literal `[BLANK_AUDIO]` into the user's text field | Fixed #17 |
| H3 | P1 | Lifecycle | Keep-alive audio never restarted after interruptions or route changes | Fixed #18 |
| H14 | P1 | Storage | 1.5 GB model included in iCloud backups (App Review 2.23 risk) | Fixed #21 |
| U2 | P1 | Onboarding | Keyboard setup steps wrong on iOS 26/27 (Add New Keyboard doesn't list it) | Fixed #22 |
| M1 | P1 | Model | Shipped the ~1.5 GB Whisper turbo build, which Argmax supports only on Macs and M-series iPads; iPhones get the 632 MB build of the same model (found in a model review after the pass; simulator runs can't show it) | Fixed #29 |
| H8 | P2 | Data | Corrupt `dictionary.json` overwritten by the next add (data loss) | Fixed #20 |
| H9 | P2 | Onboarding | Denying the mic left onboarding stuck | Fixed #22 |
| H11 | P2 | Keyboard | Previous session's error shown every time the keyboard opened | Fixed #14 |
| U4 | P2 | Keyboard | "Listening…" with a stop button shown through processing after auto-stop | Fixed #23 |
| H7 | P2 | Lifecycle | Model loaded twice when onboarding finished | Fixed #24 |
| PERF1 | P2 | Latency | First cleanup ~7.8 s cold; now prewarmed during recording | Fixed #24 (gain unmeasured, see ENV1) |
| H13 | P2 | Cleanup | Self-corrections kept both versions ("three or four o'clock"); 7/12 → 12/12 | Fixed #25 |
| H5 | P2 | Keyboard | No Full Access check; misleading "open the app" message | Fixed #26 |
| U1 | P3 | Copy | Raw enum/error text shown; "800 MB" copy for a 1.5 GB model | Fixed #22 |
| U3 | P3 | Keyboard | Duplicate globe key on Face ID iPhones | Fixed #23 |
| L1 | P3 | Learning | Single letters ("plan B") learned as vocabulary | Fixed #25 |
| A1 | P3 | Accessibility | Home Settings button fails contrast | Open (WhispIt-8gf) |
| A2 | P3 | Accessibility | Partial Dynamic Type support / clipping on onboarding | Open (WhispIt-46a) |
| U5 | P3 | Keyboard | Black keys in dark mode; very tall landscape keyboard | Open (WhispIt-e22) |

Also tracked: ENV1 (WhispIt-enu, the simulator's guardrail rejects the first Foundation Models request per process; likely simulator-only) and PRIV1 (WhispIt-14x, WhisperKit fetches tokenizer files from Hugging Face on first model load).

## Spec conformance

9 spec features are not implemented. Each is filed in beads:

- **P1:** live interim transcript (n58), per-app tone adaptation (88g), symbols/123 layer and standard key behaviors (hti)
- **P2:** raw mode and language setting (dr3), Home stats and in-app dictation (es9), dictionary correction pairs (73w)
- **P3:** onboarding test dictation (osf), device compatibility check (2p5), model size choice (wi8)

## Test suite

| Suite | Tests | Runs | Result |
|---|---|---|---|
| `WhispItTests` (unit, Swift Testing) | 109 | CI + local | all pass, 0 known issues |
| `WhispItKeyboardTests` (hostless) | 21 | CI + local | all pass |
| `WhispItUITests` (XCUITest) | 18 (1 opt-in skip) | CI + local | pass (full onboarding opt-in) |
| `WhispItIntegrationTests` (real WhisperKit + Foundation Models) | 24 | local | pass; see ENV1 note |

Coverage of the app target from unit tests: **81.5 %** of non-UI logic (`Shared/` + `WhispItApp/Services/`, unit tests only; plan target 80 %), 44.6 % of the whole app target (SwiftUI views are covered by UI tests, which aren't counted). `CleanupService` and `TranscriptionService` are exercised by the integration suite rather than unit tests. `Shared/Models/TranscriptionResult.swift` is unused (0 %).

## Flow results (simulator, production model)

| Flow | Result |
|---|---|
| Fresh install → onboarding → model download (1.5 GB, ~80 s) → Home "Ready" | ✅ (H7 double load found and fixed) |
| Enable keyboard + Full Access via Settings → Apps → WhispIt → Keyboards | ✅ (U2 copy fixed) |
| Dictate in Safari: silence auto-stop → "Cleaning up…" → cleaned text inserted | ✅ after H1/H2/U4 |
| Tap-stop mid-sentence | ✅ only the spoken part is inserted |
| Silent recording | ✅ "No speech detected", nothing inserted (H6) |
| App killed → tap mic | ✅ "Open the WhispIt app…" within 2.5 s (H4) |
| Full Access off → tap mic | ✅ explains how to enable it (H5) |
| Typing keys, shift, light/dark, landscape | ✅ (U5 cosmetic issues open) |
| Settings, dictionary CRUD, timeout persistence, AX5 text, accessibility audits | ✅ (A1/A2 open) |

## Non-functional

| Check | Result | Notes |
|---|---|---|
| Keyboard extension memory | 37 MB | Under the ~50 MB budget (simulator) |
| Main app memory (sim) | 42 MB, 85 MB peak | Simulator doesn't reflect ANE/GPU model memory; device checklist 6.2 |
| Leaks | keyboard: 119 leaks, 6.5 KB total | Small; app process not inspectable in the simulator |
| Stop → text latency | base.en: p50 **2.1 s**, p90 2.5 s over 20 dictations; 4.3 s for a 6 s clip of the long passage. Production large-v3 turbo in the simulator: 12–15 s (transcription 7–10 s on the Mac CPU) | Spec target < 3 s; simulator runs models on the Mac CPU, so device numbers needed (checklist 2.4) |
| Soak, 20 dictations | ✅ 20/20 dictations accepted with correct outcomes (16 cleaned, 4 silence → nothing inserted); footprint 50 → 52 MB (+1 MB after the first run) | |
| Network after model download | Tokenizer fetch only (PRIV1) | No user data sent |

## What still needs a real iPhone

See `device-checklist.md`:
- real microphone accuracy
- calls, Siri and AirPods interruptions (H3)
- background survival over 30 min
- Full Access off on device (H5)
- latency, memory and thermals on an iPhone 15 Pro or newer
- first-dictation cleanup (ENV1)

## Environment notes

- Any `.playAndRecord` session aborts in the simulator on this host (AURemoteIO RPC timeout). Fixture runs use a playback-only keep-alive (debug only).
- Hugging Face downloads and the 1.5 GB model need about 2 GB free. The host disk was 98 % full early in the pass, which most likely purged Apple Intelligence assets (ENV1).
