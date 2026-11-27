# WhispIt — End-to-End QA Plan (as approved)

## Context

WhispIt (main app + keyboard extension, ~2,200 lines of Swift) has **zero automated tests**. `project.yml` declares `testTargets: []`, the spec's `WhispItTests/` folder was never created, and there's no CI. The code builds cleanly on Xcode 27.2 (PR #11), but nobody has checked the core loop end to end: keyboard taps mic → app records → WhisperKit → Foundation Models → text inserted. Reading the code already turned up several likely P0/P1 defects (listed below).

Goal: a QA pass, run by me in the iOS Simulator, that (1) builds a lasting test suite and CI, (2) checks every user-facing flow end to end, (3) fixes the real bugs it finds, each with a regression test, and (4) hands you a device checklist and a TestFlight build for what only a real iPhone can check.

**Decisions made with you:** missing spec features → filed as beads issues, not built. Device coverage → checklist + TestFlight build. CI → add a GitHub Actions workflow.

## Ground rules

- **Severity:** P0 = crash, data loss, or the dictation loop is broken · P1 = a major feature is broken with no workaround · P2 = degraded, or a workaround exists · P3 = cosmetic.
- **Fix policy:** every confirmed bug gets a beads issue, a failing regression test, the fix, and its **own PR**. Spec gaps get beads issues only. I never merge; you merge.
- **Branching:** test work stacks on `bugfix/xcode27-build-warnings` (PR #11) until you merge it, then I rebase onto `main`. Bug-fix PRs branch from the test-infra branch so their regression tests can run.
- **Beads:** one task per phase deliverable plus one issue per defect, with dependencies (per your CLAUDE.md).
- **Environment:** Xcode 27.2. Simulators: iPhone 18 Pro (primary), iPhone 17e, iPhone 18 Pro Max, all on iOS 27.2. Apple Intelligence is **available on this Mac**, so Foundation Models really runs in the simulator. Automated runs use the small `openai_whisper-tiny`/`base` models. The production `large-v3 turbo` model runs once, in Phase 4.
- **Disk caveat:** only **12 GB free**. I'll keep one production model download and clean up simulator data and DerivedData between heavy phases.

## Risks found in code review (verify these first)

| ID | Area | Hypothesis | Sev. if real |
|---|---|---|---|
| H1 | Keyboard ↔ app IPC | The app writes `recordingActive=true` but never posts a Darwin notification, so the keyboard never shows "recording". A second mic tap re-sends **start** instead of stop, and only the silence timeout can end a recording. `transcriptionUpdated` is never posted anywhere (`DictationPipelineCoordinator.swift`, `KeyboardViewController.swift:43`). | P0 |
| H2 | Audio conversion | `AudioCaptureService.process` returns `.endOfStream` to `AVAudioConverter` on every buffer. After the first end-of-stream, later conversions may produce nothing, so most mic audio is dropped. | P0 |
| H3 | Keep-alive | After an interruption (phone call) the system stops the engine, but `BackgroundAudioSessionManager.isActive` stays `true`, so `start()` does nothing. The app gets suspended and dictation dies silently. | P1 |
| H4 | Keyboard feedback | If the main app isn't running, is suspended, or hasn't loaded the model, tapping mic does nothing: no timeout, no message. | P1 |
| H5 | Full Access | There's no `hasFullAccess` check. With Full Access off, the shared container is unavailable and dictation fails silently with no guidance. | P2 |
| H6 | Whisper hallucination | Silent or very short audio can produce "Thank you." and similar phantom text. The pipeline only rejects an *empty* string, so that text gets inserted. | P2 |
| H7 | Model load | Finishing onboarding switches to `HomeView`, whose `.task` calls `bootstrapIfReady()`, which loads WhisperKit a second time (memory spike, delay). | P2 |
| H8 | Dictionary | If `dictionary.json` is corrupt, loading falls back to `[]`, and the next `add` overwrites the file: data loss. | P2 |
| H9 | Onboarding | If mic permission is denied, the user is stuck on the step with no path to Settings. Model download failures show a raw `String(describing: error)`, with no disk-space check (about 1.6 GB). | P2/P3 |
| H10 | Long dictation | A long transcript can exceed the Foundation Models context window or trip a guardrail. The fallback to raw text needs testing. | P2 |

## Phases

### Phase 0 — Test infrastructure (PR A)
- `project.yml`: add `WhispItTests` (unit, hosted in the app) and `WhispItUITests` targets, wire them into the `WhispItApp` scheme, and add an `.xctestplan` with **Unit**, **Integration** (local only) and **UI** configurations.
- Testability seams, kept minimal, with behavior unchanged:
  - `DictionaryManager`: an internal `init(fileURL:)` so tests use temp dirs; the singleton stays.
  - `VoiceActivityDetector`: an injectable clock instead of `Date()`.
  - `AudioCaptureService`: an input-source seam. A DEBUG-only file-backed source feeds 48 kHz buffers **through the same converter path**, so H2 is exercised and not bypassed.
  - DEBUG launch arguments: `-WhispItAudioFixture <name>` (read from the App Group container), `-WhispItModelVariant <variant>`, `-WhispItResetState`.
- Fixtures: `Scripts/make-audio-fixtures.sh` generates WAVs with macOS `say`. Clips: a filler-heavy sentence, proper nouns (for dictionary bias), a self-correction, 5 s of silence, a 60 s passage, and speech with a long pause (VAD).
- `os.Logger` plus signposts at each pipeline stage, for latency measurement. Transcript text is never logged.
- Fill in the `CLAUDE.md` "Build & Test" section with the real commands.

### Phase 1 — Unit tests (in PR A)
- `DictionaryManager`: add/trim/empty, case-insensitive dedupe bumps frequency, remove, search, source filter, persistence round-trip, corrupt-file handling (H8).
- `DictionaryLearningService.extractCandidates`: sentence starts, all-caps, exclusions, punctuation and quotes, newlines; promotion at 3 sightings; candidate persistence.
- `DictionaryPromptBuilder`: ordering by frequency, the 50-word cap, empty input → nil.
- `VoiceActivityDetector`: RMS math, fires once after the timeout, speech resets it, all-silence start.
- `AudioCaptureService` conversion: 48 kHz stereo → 16 kHz mono, frame counts across 100 consecutive buffers (H2).
- `SettingsManager` defaults and persistence. `IPCManager` JSON and text round-trips. `SharedState` coding. `KeyboardState.apply`.
- Coordinator state machine with stubbed services: start/stop/interrupt/double-start/stop-while-finalizing, and the notifications posted (H1).

### Phase 2 — Integration tests (PR B; local only: they need a model and Apple Intelligence)
- `TranscriptionService` + tiny model + fixtures → expected keywords; dictionary prompt improves proper-noun accuracy; silence → empty or rejected (H6).
- `CleanupService` (real Foundation Models): fillers removed, meaning kept (keyword assertions), self-correction collapsed, empty input, long input fallback (H10).
- Full pipeline: post `recordingStartRequested`/`StopRequested` Darwin notifications against a fixture source → `cleaned-text.txt` is written, `cleanedTextReady` is posted, the shared state transitions correctly, and dictionary learning updates.

### Phase 3 — Main app UI tests (XCUITest, in PR B)
- Onboarding: every step, mic permission allow and deny (interruption monitor, H9), model download with the tiny variant, Apple Intelligence step, keyboard step, completion → Home without a second model load (H7).
- Home states: idle, loading, ready, failed. Settings navigation. Version and privacy link.
- Dictionary: add, search, filter, swipe-delete, duplicate add, empty state. Dictation Preferences timeout persists across relaunch.
- Portrait and landscape (PR #11), dark mode, largest Dynamic Type, `performAccessibilityAudit()` on every screen.
- Matrix: iPhone 18 Pro on every run; iPhone 17e and 18 Pro Max for the layout tests.

### Phase 4 — Keyboard end-to-end in the simulator (I drive it with simulator taps, screenshots and `simctl`)
- Setup: install, add the WhispIt keyboard in the Settings app, turn on Full Access, open Notes / Messages / a Safari text field, switch keyboards with the globe key.
- Happy path with the production model: tap mic → "Listening…" → stop (by tap **and** by silence) → "Cleaning up…" → text inserted → checkmark → idle (H1).
- Typing keys: letters, shift, caps lock, backspace, space, return, globe.
- Error paths: app killed or suspended (H4), model not loaded, silence fixture (H6), Full Access off (H5), rapid repeated taps, a stop during processing, an interruption simulated by posting `AVAudioSession` notifications (H3).
- Keyboard in light/dark and portrait/landscape; the extension's height.

### Phase 5 — Non-functional checks
- **Latency**, stop → insert, from signposts. Spec target is under 3 s. Simulator numbers are indicative only.
- **Memory:** keyboard extension under 50 MB (`footprint` on the simulator process); main app peak with both models loaded; `leaks` after 20 dictations.
- **Soak:** 20 dictations in a row with no state drift.
- **Privacy:** no network traffic after the model download (network monitoring on the simulator process); no transcript text in logs.

### Phase 6 — CI (PR C)
- `.github/workflows/ci.yml`: XcodeGen → build → Unit and UI test plan configurations on a simulator. Integration tests are excluded. `.xcresult` uploaded as an artifact.
- Risk: GitHub-hosted runners may lag on Xcode 27.2. I'll use the newest available image, and if the iOS 26 SDK isn't there yet I'll pin with `xcode-select` and tell you.
- Iterate until it's green (`gh pr checks`).

### Phase 7 — Spec conformance audit
- One beads issue per gap: tone adaptation, live interim transcript, 123/symbols keyboard, Home stats, raw mode and language settings, correction pairs, the onboarding test-dictation step, the device-compatibility check, Add Custom App.

### Phase 8 — Device checklist + TestFlight
- `docs/qa/device-checklist.md`: real-mic accuracy, phone call / Siri / AirPods route change, lock screen and background survival over 30 min, haptics, latency and memory on an iPhone 15 Pro or newer, the Full Access trust prompt, thermal behavior during a long session.
- After you merge the fix PRs: run the CLAUDE.md pre-flight checks (team ID, Info.plist keys, icon), bump `CURRENT_PROJECT_VERSION`, then archive → export → upload, closing beads `WhispIt-dab`.

### Phase 9 — Report (PR D)
- `docs/qa/TEST_PLAN.md` (this plan) and `docs/qa/REPORT.md`: a pass/fail matrix per flow and device, defects found and fixed (with links to their PRs), open issues by severity, coverage numbers, and measured latency and memory.

## Exit criteria
- All P0/P1 defects fixed, each with a regression test (PRs open for you to merge).
- Unit, UI and integration suites green locally; CI green on Unit and UI.
- At least 80% line coverage of non-UI logic in `Shared/` and `WhispItApp/Services/`.
- The keyboard dictation loop verified end to end in the simulator with the production model.
- Every P2/P3 defect and spec gap filed in beads; device checklist and TestFlight build delivered.

## Verification
- `xcodebuild test -testPlan WhispIt -only-test-configuration Unit|UI|Integration` on iPhone 18 Pro, with `.xcresult` coverage from `xcrun xccov`.
- Simulator screenshots for every Phase 4 step, linked in the report.
- `gh pr checks` green on the CI PR.

## Expected PRs
A: test infra + unit tests · B: integration + UI tests · C: CI · one PR per bug fix · D: QA docs and report. Each is small enough to review on its own.
