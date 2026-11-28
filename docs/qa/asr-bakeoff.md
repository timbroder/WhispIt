# Speech-engine bake-off: Whisper turbo vs SpeechAnalyzer vs Parakeet

**Issue:** WhispIt-peu · **Date:** 2026-11-28 · **Host:** M1 Pro MacBook Pro (macOS 27.0.1), Xcode 27.2, iOS 27.2 simulator (iPhone 18 Pro)

## Recommendation

**Switch the default English engine to Parakeet TDT 0.6B v2 (through FluidAudio), with Apple SpeechAnalyzer as the no-download fallback, once one iPhone run ([device checklist §8](device-checklist.md)) confirms the Mac numbers below. Until then keep WhisperKit, and merge [PR #30](https://github.com/timbroder/WhispIt/pull/30) (WhispIt-3lu) first: on the WhisperKit 0.18 that `qa/report` ships, any dictionary word blanks every turbo transcript.**

Why Parakeet v2:

- **Accuracy matches Whisper turbo** on every clean fixture (0 % WER), with punctuation and capitals, and it behaves better on **silence**: it returns nothing, where turbo says "Thank you." with or without a dictionary. Today only the VAD heuristic hides turbo's silence output, and that heuristic also drops soft short replies (checklist 2.7b).
- **10–15× faster stop-to-text** on the Neural Engine: 0.10 s against 0.96 s for a 6 s clip, and 0.23 s against 3.49 s for 41 s. On a long dictation, turbo's 3.5 s alone uses up the spec's < 3 s budget before cleanup starts.
- **Lighter:** a 451 MB download (plus 99 MB for dictionary boosting) against 624 MB; 92 MB peak app memory against 139 MB for turbo 632 MB; and no multi-minute Neural Engine compile on first load. Turbo's took about 5 minutes and peaked near 770 MB on the M1 Pro.
- **Testable:** it runs in the iOS simulator, so the integration suite keeps covering the real engine. SpeechAnalyzer can't run there.

What it costs:

- **Weaker dictionary biasing.** On the rare-names fixture, FluidAudio's boosting takes Parakeet from 1/5 to 2/5 names (3/5 with its recall-tuned thresholds). Whisper's prompt takes turbo from 2/5 to 4/5. Both left ordinary speech and the "twist of lime" decoy alone. If spelling the user's dictionary words right matters more than speed and memory, keep Whisper.
- **English only.** v3 covers 25 European languages at the same speed, but its boosting did nothing here. Whisper auto-detects about 99 languages, and WhispIt relies on that today, so non-English dictation needs the fallback.
- A second model (CTC 110M) for boosting, CC-BY-4.0 attribution for the model weights, and a new SwiftPM dependency (FluidAudio, Apache-2.0; see [Shipping cost](#shipping-cost-of-the-prototypes)).

Why SpeechAnalyzer is the fallback, not the primary engine:

- For: **nothing to download** (a system asset shared with dictation: 214 MB compressed and 395 MB on disk on this Mac, already present here, so "install" took 0.4 s). Its model runs **outside WhispIt's process** (12 MB in-app; the system's `localspeechrecognition` process peaked at 244 MB). It has the **best streaming latency** (0.06 s and 1.0 s from stop to text, because it works while you talk), no silence hallucination, and volatile results that could drive the live transcript the spec asks for (WhispIt-n58).
- Against: the **weakest accuracy** here (3.4 % WER: "Cuban needs" for Kubernetes even with the dictionary, sparse punctuation). Contextual strings fixed "Priyanka" but none of the five rarer names. It **can't run in the iOS simulator**, and the OS decides when its assets are available.
- So it fits the cases where Parakeet can't run: first launch before the model download finishes, locales Parakeet doesn't cover, and a missing or corrupt model.

Whisper-specific findings, whatever the decision:

- On WhisperKit 0.18 (`qa/report` today) both turbo builds return an **empty transcript whenever the dictionary prompt is set**. The prompted decode stops after 5 special tokens. `base.en`, which the integration suite uses, is unaffected, which is how H12's fix looked complete. argmax-oss-swift 1.1.1 ([PR #30](https://github.com/timbroder/WhispIt/pull/30)) fixes it, and the prompt then works well. `usePrefillPrompt = false` is not a workaround: it avoids the blank output, but WhisperKit then ignores the prompt entirely.
- The 632 MB turbo build ([PR #29](https://github.com/timbroder/WhispIt/pull/29), WhispIt-4yf) beat the 1.5 GB build on speed (0.96 s against 2.05 s, and 3.49 s against 5.64 s), with near-identical transcripts.

## Results

### Native macOS (M1 Pro, Neural Engine): the comparison to use

All three engines through the same harness, one process per engine, warm runs. WhisperKit rows use argmax-oss-swift 1.1.1 ([PR #30](https://github.com/timbroder/WhispIt/pull/30)) unless marked 0.18.

| Engine | WER, 5 speech fixtures | Proper nouns, plain → with dictionary | Rare names, plain → with dictionary | Decoy "twist" kept | Dictionary leaks | Silence (plain / dictionary) | Stop→text, 6 s clip | Stop→text, 41 s clip | Peak app memory | Model on disk | Load from cache |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **WhisperKit turbo 632 MB** (baseline) | 0.0 % | 3/3 → 3/3 | 2/5 → **4/5** | yes | none | "Thank you." / "Thank you." | 0.96 s | 3.49 s | 139 MB | 624 MB | 2.0 s |
| WhisperKit turbo 632 MB on **WhisperKit 0.18** (`qa/report`) | 0.0 % | 3/3 → **0/3** (empty) | 2/5 → **0/5** (empty) | no (empty) | every transcript empty | "Thank you." / "" | 0.93 s | 3.44 s | 310 MB¹ | 624 MB | 1.7 s |
| WhisperKit turbo 1.5 GB (today's default) | 0.0 % | 3/3 → 3/3 | 2/5 → 4/5 | yes | none | "Thank you." / "Thank you." | 2.05 s | 5.64 s | 171 MB | 1,584 MB | 1.3 s |
| WhisperKit base.en (integration-test model) | 0.0 % | 3/3 → 3/3 | 0/5 → 4/5 | yes | none | clean | 0.17 s | 0.94 s | 83 MB | 143 MB | 0.5 s |
| **SpeechAnalyzer** DictationTranscriber, streaming | 3.4 % | 1/3 → 2/3 | 1/5 → 1/5 | yes | none | clean | **0.06 s** | 1.01 s | 12 MB² | system (395 MB, shared) | 0.0 s |
| SpeechAnalyzer DictationTranscriber, batch | 3.4 % | 1/3 → 2/3 | 1/5 → 1/5 | yes | none | clean | 0.20 s | 2.07 s | 12 MB² | system | 0.0 s |
| **Parakeet TDT 0.6B v2**, dictation boosting | 0.0 % | 3/3 → 3/3 | 1/5 → 2/5 | yes | none | clean | 0.10 s | **0.23 s** | 92 MB | 451 + 99 MB | 0.4 s |
| Parakeet TDT 0.6B v2, recall boosting | 0.0 % | 3/3 → 3/3 | 1/5 → 3/5 | yes | none | clean | 0.08 s | 0.23 s | 93 MB | 451 + 99 MB | 0.4 s |
| Parakeet TDT 0.6B v3, dictation boosting | 0.0 % | 3/3 → 3/3 | 1/5 → 1/5 | yes | none | clean | 0.09 s | 0.33 s | 94 MB | 469 + 99 MB | 0.4 s |

¹ That run compiled the model for the Neural Engine in-process (about 5 minutes), which inflates its memory. Turbo's first-ever load, download included, took 312 s and peaked at 773 MB. The 1.1.1 rows reused the compiled cache.
² WhispIt's own process. The model runs in the system's `localspeechrecognition` process, which grew from 0 to 244 MB during the run and kept 222 MB afterwards.

Cold first load on this host's connection, download included: Parakeet v2 80 s including the CTC model; Whisper turbo 632 MB 312 s, mostly the Neural Engine compile; SpeechAnalyzer 0.4 s, because the system already had the English asset.

What the names fixture shows (spoken: *Siobhan, Saoirse, Tuist, Nguyen, WhispIt*):

| Engine | Without dictionary | With dictionary |
|---|---|---|
| Whisper turbo 632 MB (1.1.1) | Siobhan, Saoirse, "two as", "win", "Wispit" | Siobhan, Saoirse, **Tuist**, "win", **WhispIt** |
| SpeechAnalyzer | Siobhan, "Sasha", "two as", "win", "whisper" | unchanged |
| Parakeet v2 (dictation) | Siobhan, "Sercia", "twist", "win", "Wispit" | Siobhan, "Sercia", **Tuist**, "win", "Wispit" |
| Parakeet v2 (recall) | same | Siobhan, "Sercia", **Tuist**, "win", **WhispIt** |
| Parakeet v3 (dictation) | Siobhan, "Sersha", "twoist", "win", "Wispit" | unchanged |

Only base.en wrote "Nguyen", and only with the dictionary. Every engine kept "a twist of lime".

### iOS simulator (CPU only): indicative

`WhispItIntegrationTests/Bakeoff` in the iPhone 18 Pro simulator, iOS 27.2, on the same M1 Pro. Core ML runs on the CPU here, so latencies are roughly 4–10× the Mac's and memory differs; use this for the ordering, not the values. WhisperKit here is the app's own 0.18 (`qa/report`). SpeechAnalyzer skips itself (see above).

| Engine | WER, 5 speech fixtures | Proper nouns, plain → with dictionary | Rare names, plain → with dictionary | Decoy kept | Silence (plain / dictionary) | Stop→text, 6 s clip | Stop→text, 41 s clip | Peak app memory | Model on disk | First load (download + compile) |
|---|---|---|---|---|---|---|---|---|---|---|
| WhisperKit turbo 632 MB, 0.18 | 0.0 % | 3/3 → **0/3** (empty) | 2/5 → **0/5** (empty) | no (empty) | "Thank you." / "" | 9.41 s | 30.01 s | 224 MB | 620 MB | 51 s |
| WhisperKit base.en, 0.18 | 0.0 % | 3/3 → 3/3 | 1/5 → 4/5 | yes | clean | 0.84 s | 4.09 s | 69 MB | 140 MB | 1 s (cached) |
| Parakeet v2, dictation boosting | 0.0 % | 3/3 → 3/3 | 1/5 → 2/5 | yes | clean | 1.33 s | 3.54 s | 166 MB | 550 MB | 32 s |
| Parakeet v2, recall boosting | 0.0 % | 3/3 → 3/3 | 1/5 → 3/5 | yes | clean | 1.33 s | 3.53 s | 159 MB | 550 MB | (cached) |
| Parakeet v3, dictation boosting | 0.6 % | 2/3 → 3/3 | 1/5 → 1/5 | yes | clean | 1.40 s | 3.85 s | 159 MB | 568 MB | 27 s |

Transcripts match the Mac run except Parakeet v3, which wrote "Preianka" on the CPU; boosting corrected it. The simulator confirms the turbo prompt bug inside the app itself: the integration suite passes only because it uses `base.en`.

### On-device results (iPhone)

Not run yet (WhispIt-man). Follow [device checklist §8](device-checklist.md) and add the `BAKEOFF_RESULT` lines here, tabulated with `Scripts/asr-bakeoff-table.py`.

### Download and install

| Engine | What downloads | Size | Where | Offline after install |
|---|---|---|---|---|
| WhisperKit turbo 632 MB | Core ML model from Hugging Face (argmaxinc/whisperkit-coreml, MIT) | 624 MB on disk | App Group container, excluded from backup | Yes. Tokenizer files are fetched on first load (WhispIt-14x). |
| Parakeet v2 / v3 | Core ML models from Hugging Face (FluidInference, CC-BY-4.0) | 451 / 469 MB, plus 99 MB CTC model for boosting | `Application Support/FluidAudio/Models` (prototype; production would move it to the App Group and exclude it from backup) | Yes |
| SpeechAnalyzer | System asset `com.apple.speech.asr.transcription.en` through `AssetInventory` | 214 MB compressed, 395 MB on disk (macOS); shared with system dictation, and often already present | Managed by the OS | Yes, per Apple. Status was `installed` on later runs. On a phone, check with airplane mode (§8.4). |

`AssetInventory` flow in the prototype: `DictationTranscriber.supportedLocale(equivalentTo:)` → `AssetInventory.status(forModules:)` → if not `.installed`, `reserve(locale:)` then `assetInstallationRequest(supporting:)?.downloadAndInstall()`. On this Mac the first run found the status `supported`; the request completed in 0.4 s and later runs reported `installed`. Every buffer is converted to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` (16 kHz mono Int16 here): the analyzer accepts other formats and silently returns nothing.

### Shipping cost of the prototypes

Release builds don't change. `xcodebuild -configuration Release` for a device, unsigned, before and after this branch:

| | `qa/report` | This branch | First attempt (FluidAudio linked into the app) |
|---|---|---|---|
| `WhispIt.app` | 9,984 KB | 9,980 KB | 39,976 KB |
| `WhispIt` binary | 9,560,384 B | 9,558,704 B | 39,247,656 B |
| Prototype symbols in the binary | – | none | 51,109 FluidAudio symbols, plus `FluidAudio_LuxTtsG2pResources.bundle` |

Xcode links a package product in every build configuration, and FluidAudio 0.18.4 brings a 31 MB static Rust library for text normalization (`NemoTextProcessing`), its TTS lexicon bundle and all its Swift code. So the app only links WhisperKit, as before, and FluidAudio is linked into `WhispItIntegrationTests` alone. If Parakeet is adopted, depend on FluidAudio with `traits: []` (ASR and VAD only; its `Package@swift-6.2.swift` drops NemoTextProcessing, TTS and diarization that way) and measure what's left. The SpeechAnalyzer prototype adds nothing: it's a system framework, and the prototype is compiled out of Release.


## What was compared

| Engine | How it runs | Dictionary biasing used |
|---|---|---|
| **WhisperKit** `openai_whisper-large-v3-v20240930_turbo_632MB` (baseline) | `TranscriptionService` as shipped, with the 632 MB compressed turbo build Argmax supports on iPhone (WhispIt-4yf) | Dictionary words as Whisper's prompt (`DictionaryPromptBuilder`), as shipped |
| WhisperKit `…turbo` (1.5 GB, today's default) and `base.en` (integration-test model) | Same code | Same |
| **Apple SpeechAnalyzer + `DictationTranscriber`** (iOS 26+) | `SpeechAnalyzerTranscriber`. Streaming mode feeds the analyzer while the user talks; batch mode analyzes after stop, like Whisper. | `AnalysisContext.contextualStrings[.general]` |
| **NVIDIA Parakeet TDT 0.6B v2** (English) and **v3** (25 languages) via FluidAudio 0.18.4 | `ParakeetTranscriber`, batch after stop | FluidAudio vocabulary boosting: a second, 110M-parameter CTC model spots dictionary words and a rescorer swaps them in. Default "dictation" thresholds (`cbw 0`, similarity ≥ 0.7, FluidAudio#967), plus a run with FluidAudio's recall-tuned defaults. |

All three engines sit behind the existing `Transcribing` protocol, and the shipping default doesn't change: `DictationPipelineCoordinator.makeTranscriber()` returns WhisperKit's `TranscriptionService` unless a Debug build passes `-WhispItASREngine`.

- **SpeechAnalyzer** is compiled into the app in Debug builds only (`WhispItApp/Services/Debug/SpeechAnalyzerTranscriber.swift`). `-WhispItASREngine speech-analyzer` (or `speech-analyzer-batch`) swaps it into the real pipeline. It uses the system's assets, so onboarding still downloads a Whisper model; add `-WhispItModelVariant openai_whisper-tiny` to keep that download small.
- **Parakeet** lives in the integration-test bundle (`WhispItIntegrationTests/Bakeoff/ParakeetTranscriber.swift`), which is the only target that links FluidAudio. In the app, FluidAudio added about 30 MB to Release builds even with every use behind `#if DEBUG` (see [Shipping cost](#shipping-cost-of-the-prototypes)), so it can't be selected in the app. The harness measures it the same way, on a phone too.

## Method

The same harness (`WhispItIntegrationTests/Bakeoff/BakeoffCore.swift`) drives every engine through `Transcribing`, exactly as `DictationPipelineCoordinator` does: `reset()`, `appendAudio(_:)` with 16 kHz mono buffers, then `transcribe(prompt:)`.

- **Fixtures:** the speech fixtures in `WhispItIntegrationTests/Fixtures` (macOS `say`, voice Samantha), plus a new `names.wav` with rarer names and brand words (Siobhan, Saoirse, Tuist, Nguyen, WhispIt) and a decoy ("a twist of lime" next to "Tuist").
- **Word accuracy:** WER against the fixture scripts over `fillers`, `proper-nouns`, `self-correction`, `pause` and `long-passage` (179 reference words). Before scoring, both sides are lowercased and stripped of punctuation and apostrophes, numbers 0–12 are spelled out, and hesitations (um, uh…) are dropped, as Whisper's English normalizer does. The cleanup step removes fillers anyway.
- **Proper nouns:** names spelled exactly right, without and then with the dictionary. Every biased run passes all eight dictionary words, as a real dictionary holds many words that aren't in a given sentence.
- **Dictionary safety:** with the dictionary on, the `fillers`, `self-correction` and `long-passage` transcripts must not gain any dictionary word ("leaks"), and the decoy "twist" must survive.
- **Silence:** `silence.wav` (5 s of digital silence), with and without the dictionary. The pipeline's VAD guard is not applied here; this is the raw engine output.
- **Stop-to-text latency:** time from handing over the last audio to getting the final text. Median of 3 warm runs on the 6 s `fillers` clip and the 41 s `long-passage`. Batch engines get the whole clip at stop. Streaming SpeechAnalyzer is fed in real time in 100 ms buffers, as from the mic, so its work overlaps the recording as it would in the app.
- **Memory:** the process's `phys_footprint` (what iOS's memory limit is enforced against), sampled every 20 ms, before and after loading and at peak during transcription. SpeechAnalyzer runs its model in a system process (`localspeechrecognition`), so its in-app number is small by design; that process was sampled separately on macOS.
- **Download and install:** bytes on disk after the first download, cold download-and-load time, and load time for a fresh instance once models are cached (what each app launch pays).

### Where it ran, and how far to trust the numbers

- **iOS simulator** (the integration suites): Core ML runs on the Mac's CPU only, with no Neural Engine or GPU, so latency and memory are much worse than on a phone and are **indicative only**. SpeechAnalyzer **does not run in the iOS 27.2 simulator**: `DictationTranscriber` reports its assets as installed but offers no audio format (the GeneralASR asset fetch fails), `bestAvailableAudioFormat` returns nil, and `SpeechTranscriber.isAvailable` is false. The suite skips itself there.
- **macOS native** (`Scripts/asr-bakeoff-mac`): the same engine sources and harness, compiled for the Mac. Core ML can use the M1 Pro's Neural Engine and GPU, which is much closer to an iPhone than the simulator, but an M1 Pro is not an iPhone either. This is the only place on this host where all three engines ran.
- **iPhone:** not run here. Running needs a Debug install on a physical phone, which replaces its TestFlight build; see [`device-checklist.md`](device-checklist.md) §8.
- **Fixture limits:** the fixtures are clean synthetic speech from one US voice. They separate the engines on names, biasing, silence, latency and resources, but they are too easy to rank everyday accuracy (several engines score close to 0 %). Real voices, accents and noise are on the device checklist.

## How to re-run

Integration suites (simulator or device), one engine per process:

```bash
TEST_RUNNER_WHISPIT_BAKEOFF=1 xcodebuild test -project WhispIt.xcodeproj -scheme WhispItApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:WhispItIntegrationTests/ParakeetV2Bakeoff
```

Suites: `WhisperTurboBakeoff`, `WhisperTurboFullBakeoff`, `WhisperBaseBakeoff`, `SpeechAnalyzerBakeoff` (device only), `ParakeetV2Bakeoff`, `ParakeetV3Bakeoff`. Without `WHISPIT_BAKEOFF` they are skipped, so the normal integration run doesn't download about 2 GB of models. `BakeoffHarnessTests` (WER, chunking, fixture scripts) always runs.

Native macOS runner:

```bash
cd Scripts/asr-bakeoff-mac
swift build -c release
.build/release/ASRBakeoffMac speech-analyzer   # or whisper-turbo-632, parakeet-v2, …
```

Turn the `BAKEOFF_RESULT` lines from either into the tables below with `Scripts/asr-bakeoff-table.py <logs>`. The Mac runner stores WhisperKit models in `~/Library/Caches/WhispItBakeoff` and FluidAudio's in `~/Library/Application Support/FluidAudio`; delete those folders afterwards to reclaim about 3 GB.
