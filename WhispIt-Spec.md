# WhispIt — iOS App Technical Specification

## Overview

WhispIt is an iOS app that provides a system-wide custom keyboard with AI-powered voice-to-text dictation. Users speak naturally into any text field on their phone, and WhispIt transcribes their speech using WhisperKit (on-device Whisper model), then automatically cleans and polishes the text using Apple's Foundation Models framework — removing filler words, fixing grammar, adding punctuation, and adapting tone to the current app context.

**Minimum Requirements:** iPhone 15 Pro or later (A17 Pro+), iOS 26+, Apple Intelligence enabled.

---

## Architecture

The app has two primary components that communicate via a shared App Group container:

### 1. Main App (Container App)
- Hosts all heavy processing: WhisperKit speech recognition + Foundation Models cleanup
- Manages settings UI, personal dictionary, per-app tone configuration
- Runs an audio processing pipeline triggered by the keyboard extension
- Stores shared state (dictionary, settings, processed text) in the App Group

### 2. Keyboard Extension
- Lightweight custom keyboard built with `UIInputViewController`
- Renders a standard QWERTY layout with a prominent mic button
- On mic tap: coordinates with the main app to start/stop recording and receive cleaned text
- Inserts final polished text into the active text field via `textDocumentProxy`
- Displays real-time transcription status (recording indicator, processing state)
- Must stay under ~50MB RAM — no models loaded in-process

### IPC Strategy (Keyboard ↔ Main App)

Use a combination of:
- **App Group shared `UserDefaults`** (`group.com.whispit.shared`) for settings, dictionary, and tone config
- **App Group shared file container** for passing audio data and processed text
- **Darwin notifications** (`CFNotificationCenterGetDarwinNotifyCenter`) for signaling between processes (e.g., "recording started", "text ready")
- **Background audio session** in the main app to keep it alive during recording

Flow:
```
1. User taps mic on keyboard
2. Keyboard writes "start" signal to shared container + posts Darwin notification
3. Main app wakes, begins audio capture via AVAudioEngine
4. Audio streams through WhisperKit for real-time transcription
5. Interim transcription written to shared file (keyboard reads + displays preview)
6. User taps mic again (or silence timeout)
7. Final raw transcript passed to Foundation Models for cleanup
8. Cleaned text written to shared file + Darwin notification sent
9. Keyboard reads cleaned text + inserts via textDocumentProxy
```

---

## Speech Recognition — WhisperKit

### Setup
- Use [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Swift package)
- Download the model on first launch (offer a progress indicator)
- Use `whisper-large-v3-turbo` or best available model that fits device RAM alongside Foundation Models
- Store model files in the App Group container so both targets can reference them if needed

### Recording Pipeline
- `AVAudioEngine` with tap on input node
- Audio format: 16kHz mono Float32 (Whisper's expected input)
- Stream audio buffers to WhisperKit's transcription pipeline
- Support real-time interim results (partial transcription displayed in keyboard UI)
- Implement Voice Activity Detection (VAD) for automatic stop after sustained silence (~2 seconds)
- Handle interruptions (phone call, Siri activation) gracefully

### Personal Dictionary Integration
- Before WhisperKit transcription, prepend a "prompt" or "prefix" containing the user's custom dictionary words to bias recognition toward known proper nouns, acronyms, and jargon
- WhisperKit supports initial prompt/prefix tokens — use this to boost accuracy for custom terms

---

## Text Cleanup — Foundation Models Framework

### Processing Pipeline
After WhisperKit produces the raw transcript:

```swift
import FoundationModels

@Generable
struct CleanedTranscript {
    let text: String
}

func cleanTranscript(raw: String, appContext: AppToneContext) async throws -> String {
    let model = SystemLanguageModel.default
    let session = model.makeSession()

    let prompt = """
    You are a dictation cleanup assistant. Clean up this raw voice transcription:
    - Remove filler words (um, uh, like, you know, so, basically)
    - Remove false starts and self-corrections (keep only the corrected version)
    - Fix grammar and punctuation
    - Maintain the speaker's intended meaning exactly
    - Do NOT add, embellish, or change the meaning
    - Apply this tone: \(appContext.toneDescription)
    - Format appropriately (paragraph breaks for long passages)

    Raw transcription:
    \(raw)
    """

    let response = try await session.respond(to: prompt, as: CleanedTranscript.self)
    return response.output.text
}
```

### Tone Adaptation

Detect the frontmost app using the keyboard extension's `hostBundleID` (accessible via `self.parent` or `UIInputViewController`'s host info). Map known bundle IDs to tone presets:

```swift
enum AppTonePreset: String, Codable, CaseIterable {
    case formal      // Mail, Outlook, Gmail
    case casual      // iMessage, WhatsApp, Messenger, Telegram
    case professional // Slack, Teams, Discord (work servers)
    case technical   // Xcode, terminal apps, dev tools
    case neutral     // Default fallback

    var toneDescription: String {
        switch self {
        case .formal:
            return "Professional and polished. Use complete sentences, proper salutations where appropriate. No slang or abbreviations."
        case .casual:
            return "Conversational and natural. Contractions are fine. Keep it brief and friendly. Lowercase OK for short messages."
        case .professional:
            return "Clear and concise workplace communication. Direct but friendly. Use standard punctuation."
        case .technical:
            return "Precise and technical. Preserve code terms, variable names, and technical jargon exactly. Minimal reformatting."
        case .neutral:
            return "Clean and clear. Standard grammar and punctuation. No particular style emphasis."
        }
    }
}
```

**Default app mappings** (stored in shared `UserDefaults`):

| Bundle ID Pattern | Preset |
|---|---|
| `com.apple.mobilemail` | formal |
| `com.microsoft.Office.Outlook` | formal |
| `com.google.Gmail` | formal |
| `com.apple.MobileSMS` | casual |
| `net.whatsapp.WhatsApp` | casual |
| `com.facebook.Messenger` | casual |
| `org.telegram.Telegram-iOS` | casual |
| `com.tinyspeck.chatlyio` (Slack) | professional |
| `com.microsoft.skype.teams` | professional |
| All others | neutral |

Users can override any mapping in Settings.

---

## Personal Dictionary

### Data Model

```swift
struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    let word: String
    let dateAdded: Date
    let source: EntrySource
    var frequency: Int // times encountered

    enum EntrySource: String, Codable {
        case automatic  // learned from usage
        case manual     // user-added
    }
}
```

### Auto-Learning Logic

After each transcription cycle, compare the raw WhisperKit output against the Foundation Models cleaned output:

1. Extract proper nouns, acronyms, and unusual words from the cleaned text (words that are capitalized mid-sentence, all-caps words, words not in a standard dictionary)
2. If WhisperKit consistently produces the same proper noun correctly across multiple sessions, add it to the dictionary automatically
3. If WhisperKit misspells a word that Foundation Models corrects, store the correction pair (wrong → right) so future WhisperKit prompts include the correct spelling
4. New auto-learned words appear in Settings with an "automatic" badge
5. Frequency counter tracks how often each word appears

### Storage
- Persisted in App Group shared container as JSON
- Loaded into memory on keyboard extension launch
- Synced back on every update via shared `UserDefaults` change notification

### Settings UI
- Searchable list of all dictionary entries
- Swipe-to-delete on any entry
- Manual "Add Word" button
- Filter by source (automatic / manual)
- Show frequency count

---

## Keyboard Extension UI

### Layout
- Standard QWERTY keyboard layout (use system appearance cues for light/dark mode)
- **Mic button** prominently placed (replace or augment the dictation key area)
- Globe button for keyboard switching (required by Apple)
- Return, space, backspace, shift, symbols — standard keys
- Consider using [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) as a base for the keyboard UI to avoid reimplementing standard keyboard behavior

### Recording State UI
- **Idle:** Mic button in default state
- **Recording:** Mic button pulses/glows red, waveform or level meter animation shown above the keyboard in a small banner
- **Processing:** Spinner or shimmer animation with "Cleaning up..." label
- **Done:** Text inserted, brief checkmark flash, return to idle

### Interim Transcription Display
- While recording, show a floating banner/strip above the keyboard with the live partial transcript from WhisperKit
- This helps the user see what's being captured in real time
- On completion, the banner shows the cleaned version briefly before inserting

### Haptic Feedback
- Light tap on mic button press (start recording)
- Medium tap on recording stop
- Success haptic on text insertion

---

## Main App UI

### Screens

#### 1. Onboarding / Setup
- Request microphone permission
- Request Speech Recognition permission
- Guide user to Settings → General → Keyboards → Add "WhispIt" keyboard
- Guide user to enable "Allow Full Access" (required for App Group communication)
- Download WhisperKit model with progress bar
- Verify Apple Intelligence is enabled (show instructions if not)
- Test dictation with a sample sentence

#### 2. Home / Dashboard
- Quick-start dictation area (can also dictate directly in the main app and copy)
- Stats: words dictated today, total words, time saved estimate
- Link to Settings

#### 3. Settings
- **Tone Settings**
  - List of detected apps with current tone preset
  - Tap to change preset for any app
  - "Add Custom App" option
  - Reset to defaults
- **Personal Dictionary**
  - Searchable list with swipe-to-delete
  - Add word manually
  - Filter: All / Automatic / Manual
  - Frequency count per word
- **Dictation Preferences**
  - Silence timeout duration (1s / 2s / 3s / 5s)
  - Auto-punctuation on/off (Foundation Models handles this, but option to disable cleanup entirely for raw mode)
  - Language selection (primary language for WhisperKit)
- **About**
  - Version info
  - Privacy policy
  - Device compatibility check

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│                   KEYBOARD EXTENSION                 │
│                                                      │
│  ┌──────────┐    ┌──────────────┐    ┌───────────┐  │
│  │ Mic Btn  │───▶│ Signal Start │───▶│ Show Live │  │
│  │          │    │ (Darwin Ntf) │    │ Preview   │  │
│  └──────────┘    └──────────────┘    └───────────┘  │
│                                            ▲        │
│  ┌──────────────┐                          │        │
│  │ Insert Text  │◀── Read cleaned text ────┘        │
│  │ into Field   │    from shared file               │
│  └──────────────┘                                   │
└────────────────────────┬────────────────────────────┘
                         │ App Group
                         │ Shared Container
┌────────────────────────▼────────────────────────────┐
│                     MAIN APP                         │
│                                                      │
│  ┌──────────────┐    ┌──────────────┐               │
│  │ AVAudioEngine│───▶│  WhisperKit  │               │
│  │ (16kHz mono) │    │ Transcription│               │
│  └──────────────┘    └──────┬───────┘               │
│                             │ raw transcript         │
│                             ▼                        │
│                    ┌─────────────────┐               │
│                    │  Foundation     │               │
│                    │  Models Cleanup │               │
│                    │  + Tone Adapt   │               │
│                    └────────┬────────┘               │
│                             │ cleaned text           │
│                             ▼                        │
│                    ┌─────────────────┐               │
│                    │ Dictionary      │               │
│                    │ Auto-Learn      │               │
│                    └─────────────────┘               │
└─────────────────────────────────────────────────────┘
```

---

## Project Structure

```
WhispIt/
├── WhispIt.xcodeproj
├── Shared/                          # App Group shared code
│   ├── Models/
│   │   ├── DictionaryEntry.swift
│   │   ├── AppTonePreset.swift
│   │   ├── SharedState.swift        # Codable state for IPC
│   │   └── TranscriptionResult.swift
│   ├── Services/
│   │   ├── IPCManager.swift         # Darwin notifications + shared files
│   │   ├── DictionaryManager.swift  # CRUD + auto-learn logic
│   │   └── SettingsManager.swift    # UserDefaults wrapper
│   └── Constants.swift              # App Group ID, notification names
├── WhispItApp/                      # Main app target
│   ├── App/
│   │   └── WhispItApp.swift
│   ├── Views/
│   │   ├── OnboardingView.swift
│   │   ├── HomeView.swift
│   │   ├── SettingsView.swift
│   │   ├── ToneSettingsView.swift
│   │   ├── DictionaryView.swift
│   │   └── DictationPreferencesView.swift
│   ├── Services/
│   │   ├── AudioCaptureService.swift    # AVAudioEngine management
│   │   ├── TranscriptionService.swift   # WhisperKit integration
│   │   ├── CleanupService.swift         # Foundation Models pipeline
│   │   ├── ToneDetectionService.swift   # Bundle ID → tone mapping
│   │   └── DictionaryLearningService.swift
│   └── Resources/
│       └── Assets.xcassets
├── WhispItKeyboard/                 # Keyboard extension target
│   ├── KeyboardViewController.swift # UIInputViewController subclass
│   ├── Views/
│   │   ├── KeyboardView.swift       # Main keyboard layout
│   │   ├── MicButton.swift          # Recording toggle button
│   │   ├── TranscriptionBanner.swift # Live preview strip
│   │   └── StatusIndicator.swift    # Recording/processing states
│   └── Info.plist                   # RequestsOpenAccess = YES
└── WhispItTests/
    ├── CleanupServiceTests.swift
    ├── DictionaryManagerTests.swift
    └── ToneDetectionTests.swift
```

---

## Dependencies

| Package | Purpose | Source |
|---|---|---|
| WhisperKit | On-device speech recognition (Whisper) | SPM: `github.com/argmaxinc/WhisperKit` |
| KeyboardKit | Base keyboard UI + standard key behavior (optional) | SPM: `github.com/KeyboardKit/KeyboardKit` |
| Foundation Models | Text cleanup + tone adaptation | System framework (iOS 26+) |

No cloud services, no API keys, no backend required for v1.

---

## Privacy & Permissions

| Permission | Reason |
|---|---|
| Microphone | Voice dictation recording |
| Speech Recognition | Required by iOS when using audio input (even though we use WhisperKit, not Apple's recognizer — may still trigger the permission prompt depending on AVAudioSession config) |
| Full Access (Keyboard) | Required for App Group communication between keyboard extension and main app |

**Privacy stance:** All processing is on-device. No audio or text ever leaves the device. No analytics, no telemetry in v1.

---

## Known Risks & Open Questions

1. **Background app lifecycle:** The main app must stay alive (or wake quickly) while the keyboard is active. Test extensively with `BGProcessingTask` and audio session `category: .record` to ensure reliable wake behavior. May need to explore `NSExtensionFileProviderDocumentGroup` or other IPC mechanisms if Darwin notifications prove unreliable.

2. **WhisperKit + Foundation Models memory pressure:** Both models in memory simultaneously could push RAM usage high on iPhone 15 Pro (8GB). Profile carefully. May need to unload WhisperKit before loading Foundation Models for the cleanup step (sequential, not parallel).

3. **Keyboard extension "Allow Full Access" trust prompt:** Users may hesitate. Onboarding needs to clearly explain why it's needed and that no data leaves the device.

4. **`hostBundleID` availability:** The ability to detect which app the keyboard is typing into may be limited or private API. Research `UIInputViewController`'s `textDocumentProxy` and any available host app identification. Fallback: let user manually set the current tone via a button on the keyboard.

5. **WhisperKit model download size:** The large-v3 model is ~1.5GB. Consider offering a smaller model option for users who want faster setup, with an upgrade path.

6. **Latency target:** End-to-end from "stop recording" to "text inserted" should be under 3 seconds. Foundation Models on-device generation at ~10-20 tokens/sec means a 100-word cleanup takes ~2-4 seconds. Acceptable but worth monitoring.

---

## Future Enhancements (v2+)

- Snippet library (voice shortcuts that expand to full text blocks)
- OpenRouter cloud fallback for older devices
- Multiple language support / auto language detection
- Whisper model fine-tuning with user's voice data (on-device)
- watchOS companion for quick dictation
- Siri Shortcuts integration
- Share extension for cleaning up pasted text
- iPad support with keyboard extension
