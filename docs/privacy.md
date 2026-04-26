# WhispIt Privacy Policy

_Last updated: 2026-04-26_

WhispIt is a voice dictation iOS app. This policy explains exactly what
WhispIt does with your data — which, to anticipate the answer: as little
as possible, and never off the device.

## What WhispIt processes

- **Audio from your microphone.** When you tap the mic button on the
  WhispIt keyboard, the main app records audio and runs it through an
  on-device speech recognition model (WhisperKit) to produce a
  transcript.
- **Transcripts.** The transcript is then run through Apple's on-device
  Foundation Models framework to remove filler words, fix grammar, and
  add punctuation.
- **A personal vocabulary.** WhispIt keeps a list of proper nouns and
  jargon you frequently dictate (or that you add manually in Settings)
  to improve transcription accuracy. This list lives only on your
  device.
- **A silence-timeout preference.** Stored locally.

## Where your data goes

It doesn't. Everything above happens on your iPhone. WhispIt has no
backend, no analytics, no telemetry, no crash reporting service. No
audio, no transcripts, and no dictionary entries ever leave the device.

WhispIt does not collect, transmit, or sell any personal information.

## The persistent red microphone indicator

While the WhispIt keyboard is enabled, the main app keeps a silent
audio session active in the background. This is a technical
requirement: iOS keyboard extensions cannot wake their containing app,
so WhispIt keeps the main app alive by playing inaudible silence. iOS
shows the red microphone indicator in the status bar whenever any app
holds an active microphone session, which is why you'll see it
continuously while WhispIt is enabled.

The red indicator does **not** mean WhispIt is recording or listening.
WhispIt only captures audio while you are actively dictating — i.e.
between when you tap the mic button on the keyboard and when you stop
recording (manually or via the silence-timeout).

## Permissions WhispIt asks for

- **Microphone**, so it can hear what you say. Required.
- **Allow Full Access** on the keyboard extension. iOS requires this
  flag to allow the keyboard and main app to share data through an App
  Group container — which is how the keyboard hands audio to the main
  app and gets back cleaned text. WhispIt does not use Full Access for
  any other purpose.

## Children's data

WhispIt is not directed at children under 13 and does not knowingly
collect any data from anyone — children included.

## Third-party components

WhispIt links the open-source [WhisperKit](https://github.com/argmaxinc/WhisperKit)
Swift package and Apple's Foundation Models framework. Both run
entirely on-device. WhispIt does not link any analytics, advertising,
or tracking SDK.

## Changes to this policy

If we change anything material, we will update the "Last updated" date
and note the change in this document. Because there is no backend, the
update will reach you via the next app version on the App Store.

## Contact

Open an issue at <https://github.com/timbroder/WhispIt/issues> if
anything in this document is unclear.
