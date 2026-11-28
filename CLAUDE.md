# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

`WhispIt.xcodeproj` is generated from `project.yml` (and gitignored). Regenerate after adding/removing files:

```bash
xcodegen generate
```

Tests (scheme `WhispItApp`, pick any iOS 26+ simulator):

```bash
# Unit tests: hermetic, fast, run in CI
xcodebuild test -project WhispIt.xcodeproj -scheme WhispItApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:WhispItTests

# UI tests (XCUITest), run in CI
xcodebuild test -project WhispIt.xcodeproj -scheme WhispItApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:WhispItUITests

# Integration tests: local only. Download a WhisperKit model and need Apple Intelligence enabled on the Mac.
xcodebuild test -project WhispIt.xcodeproj -scheme WhispItApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:WhispItIntegrationTests
```

- Tests that reproduce a known, unfixed bug are wrapped in `withKnownIssue("<ID>: …")`. A fix PR removes the wrapper.
- Speech fixtures live in `WhispItIntegrationTests/Fixtures`; regenerate them with `Scripts/make-audio-fixtures.sh`.
- Integration tests default to `openai_whisper-base.en`. To run them against the shipping model, prefix the command with `TEST_RUNNER_WHISPIT_INTEGRATION_MODEL=openai_whisper-large-v3-v20240930_turbo_632MB`.
- Debug-only launch arguments (see `WhispItApp/Services/Debug/DebugOverrides.swift`): `-WhispItAudioFixture <name>` feeds a WAV from `<App Group>/Fixtures/` instead of the mic, `-WhispItModelVariant openai_whisper-tiny` downloads a small model, and `-WhispItResetState` wipes onboarding and dictionary state.
- Pipeline logs (no transcript text) use the subsystem `com.whispit.app`: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.whispit.app"'`.

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_
