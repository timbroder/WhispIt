# WhispIt — Real-Device QA Checklist

What the simulator can't prove. Run this on an **iPhone 15 Pro or newer with Apple Intelligence on**, using the TestFlight build from the QA pass (or a Release build from Xcode). Mark each row ✅ / ❌ and add notes. File anything that fails in beads.

**Build under test:** `0.1.0 (___)`  ·  **Device / iOS:** ________  ·  **Tester / date:** ________

## 1. Install and onboarding

| # | Step | Expected | Result |
|---|---|---|---|
| 1.1 | Fresh install, open WhispIt | Welcome screen. | |
| 1.2 | Get Started → Allow Microphone | System prompt appears; allowing advances to the model step. | |
| 1.3 | Download Model on Wi-Fi | Progress bar moves; the size matches the copy ("about 1.5 GB"). Note the actual download time: ____ | |
| 1.4 | Lock the phone mid-download for 30 s, then unlock | The download continues or recovers with Retry (no crash, no stuck spinner). | |
| 1.5 | Apple Intelligence step | Shows "available". If not, the message is understandable (not a raw enum name). | |
| 1.6 | Follow the onboarding keyboard step: Open Settings → Keyboards → turn on WhispIt → Allow Full Access | Open Settings lands on WhispIt's page; the trust prompt text is clear. | |
| 1.7 | "I've Added the Keyboard" | Home shows **Ready** within about 30 s. | |

## 2. Core dictation (repeat in Notes, Messages, Mail, Safari address bar)

| # | Step | Expected | Result |
|---|---|---|---|
| 2.1 | Switch to the WhispIt keyboard (globe) | QWERTY plus mic button; correct in light and dark mode. | |
| 2.2 | Tap mic | Light haptic; button turns red and pulses; banner says "Listening…" within 1 s. | |
| 2.3 | **First dictation after launching WhispIt.** Say: *"Um, so basically we should ship the build on Friday."* then tap mic | Medium haptic → spinner "Cleaning up…" → text inserted **without fillers** → success haptic and green check. (The simulator's guardrail rejects the first cleanup per process, WhispIt-enu; confirm a device doesn't.) | |
| 2.4 | Measure stop → text with a stopwatch, 5 runs | Spec target **< 3 s**. Times: ____ | |
| 2.5 | Speak, then stay silent | Recording auto-stops after the configured timeout (default 2 s) and inserts text. | |
| 2.6 | Change the timeout to 5 s, pause 3 s mid-sentence | The recording continues through the pause. | |
| 2.7 | Tap mic and say nothing | "No speech detected"; **nothing** inserted (watch for "Thank you." / "you" / "[BLANK_AUDIO]"). | |
| 2.7b | Whisper a short reply ("yes", "okay thanks") quietly, from arm's length | Text is inserted. A 1–3 word transcript is discarded only if the recording never crossed the speech threshold, so very soft speech is the edge case to watch. | |
| 2.7c | Say "meet at three, no wait, four" | Only "four" survives cleanup. | |
| 2.8 | Dictate 60 s continuously | Completes; text is complete; the phone doesn't get hot; no timeout message. | |
| 2.9 | Dictate a name (e.g. a colleague's) 3 times | After the third time it appears in Settings → Dictionary as Automatic; later dictations spell it right. | |
| 2.10 | Add a manual dictionary word, then dictate it | Spelled as entered. | |
| 2.11 | Type with keys: shift, double-tap caps lock, backspace, space, return | All behave like the system keyboard (note any missing behaviors). | |

## 3. Background and lifecycle (the riskiest area)

| # | Step | Expected | Result |
|---|---|---|---|
| 3.1 | Open WhispIt once, go Home, use the keyboard in Notes for 10 min | Dictation works the whole time. | |
| 3.2 | Leave the phone locked for **30 min**, unlock, dictate | Works, or the keyboard says "Open the WhispIt app…" within about 3 s (no silent failure). | |
| 3.3 | Force-quit WhispIt from the app switcher, then tap the mic in Notes | Within about 3 s: "Open the WhispIt app to turn on dictation." | |
| 3.4 | Reboot the phone and try dictation before opening WhispIt | Same message as 3.3. | |
| 3.5 | Open WhispIt after 3.3 / 3.4 and return to Notes | Dictation works again without re-onboarding. | |
| 3.6 | Status bar while idle | The orange mic indicator shows while WhispIt is alive (expected and explained in onboarding); confirm the copy matches. | |

## 4. Interruptions and audio routes

| # | Step | Expected | Result |
|---|---|---|---|
| 4.1 | Start dictation, receive a phone call (have someone call) | Recording stops; keyboard shows "Recording interrupted". | |
| 4.2 | After the call ends, dictate again **without opening WhispIt** | Works (H3: the keep-alive session must restart). | |
| 4.3 | Start dictation, invoke Siri | Same as 4.1 / 4.2. | |
| 4.4 | Dictate with AirPods connected | Uses the AirPods mic; text is correct. | |
| 4.5 | Start dictation, remove AirPods / unplug headphones | Recording stops cleanly with a message. | |
| 4.6 | Play music in Apple Music, then dictate | Music keeps playing or ducks; dictation works; music isn't permanently stopped. | |
| 4.7 | Silent switch on | Dictation works; haptics still fire. | |

## 5. Settings and permissions

| # | Step | Expected | Result |
|---|---|---|---|
| 5.1 | Turn off Allow Full Access, then tap mic | Immediately: "Turn on Allow Full Access in Settings → Apps → WhispIt → Keyboards to dictate." | |
| 5.1b | Turn Full Access back on, return to the same app **without** switching keyboards, tap mic | Dictation works (no stale "turn on Full Access" message). | |
| 5.2 | Revoke the microphone in Settings → Privacy, open WhispIt | The app does not crash (the keep-alive starts a play-and-record session at launch); dictation reports a clear error. | |
| 5.2b | Fresh install, tap **Don't Allow** on the mic prompt | Onboarding shows "Open Settings"; after enabling the mic there and returning, it advances. | |
| 5.3 | Turn off Apple Intelligence, dictate | Raw transcript inserted (no cleanup); no error. | |
| 5.4 | Low Power Mode on, dictate | Works; note latency: ____ | |

## 6. Performance (Xcode → Debug Navigator, or Instruments)

| # | Measure | Target | Result |
|---|---|---|---|
| 6.1 | Keyboard extension memory while recording | < 50 MB (jetsam limit is about 60–70 MB) | |
| 6.2 | Main app memory, peak during finalize | Note it; must not be jetsammed in the background | |
| 6.3 | Battery drain over 1 h idle with WhispIt alive | Note % per hour | |
| 6.4 | Thermal state after 10 back-to-back dictations | Not "serious" | |

## 7. Privacy

| # | Step | Expected | Result |
|---|---|---|---|
| 7.1 | Airplane mode after model download, dictate | Works fully offline. | |
| 7.2 | Settings → Privacy → App Privacy Report | No network activity from WhispIt other than the model download host. | |
