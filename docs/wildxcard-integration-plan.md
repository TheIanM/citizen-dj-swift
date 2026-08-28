# CitizenDJ → WILDxCARD Integration Plan

**Status: EXECUTED 2026-08-28** (game branch `feat/generative-bgm`, commit `723d2f5`,
worktree `Games/.worktrees/generative-bgm/` — not yet pushed/PR'd). Simulator-verified
end-to-end; installed on a physical iPhone 15 Pro Max for by-ear testing. Deviations from
the plan as drafted:

- PR #1 was merged before execution, so the path dep points at the engine's **master
  checkout** (`/Users/devian/Documents/DJswift/citizen-dj-swift`), not the old
  `swift-engine` worktree — and it's an **absolute** path, because the game worktree and
  the game's main checkout sit at different directory depths (a relative path would break
  on merge).
- Resources had to be re-staged in the master checkout (`scripts/sync-resources.sh`) —
  bulk samples are gitignored and don't travel with merges.
- `pause()` was folded into `stop()` (the sequencer has no pause; stop/start is the
  transport reset, so two identical methods would be noise).
- Baseline-build note: `name=iPhone 16 Pro` as a destination spec is ambiguous across
  multiple iOS runtimes — pin the UDID or `OS=` instead.

The rest of this document is the plan as executed, kept for reference.

## Goal

Wire the generative drum engine into WILDxCARD as a second, toggleable soundtrack —
**"Untitled Game Soundtrack"** (a new, independent Settings toggle, default **OFF**).
When ON it plays drums + phrase loops via the live `DrumSequencer`. Independent toggles:
both music toggles ON = layered over the ambient mp3 playlist (for by-ear A/B); either can
be off. The audio session stays exactly as-is (`.ambient` / `.mixWithOthers` owned by
`SoundManager`) — silent-switch and background-pause behavior unchanged, no
`UIBackgroundModes`.

## Decisions already made (don't re-litigate)

| Question | Decision |
|---|---|
| Package reference | **Local path dep** into `…/DJswift/.worktrees/swift-engine`. PR #1 stays open until the sound is approved by ear. |
| UX | **Additional independent toggle** labeled "Untitled Game Soundtrack" (user's own wording). |
| Toggle default | **Off** — zero behavior change until flipped. |

## State snapshot (as of planning)

- Engine: branch `swift-engine`, worktree `/Users/devian/Documents/DJswift/.worktrees/swift-engine`,
  PR #1 open, 33 tests green. `DrumSequencer` is session-agnostic by design.
- Staged resources in the package: kits `SH_SFB2_KIT08_ONE_SHOTS`, `UFO`, `ultimate-pop`;
  phrase sets `Bounce-loop`, `SH_SFB2_KIT08_MELODY_LOOPS`.
- Game: `/Users/devian/Documents/Games/WILDxCARD`, repo clean on `feat/dev-trailer-mode`.
  SwiftUI, iOS 17.6 (also macOS 14.6 / visionOS 2.6 destinations), Swift 5 mode with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. **Zero existing SPM deps** — CitizenDJ is
  the first. File-system-synchronized groups ⇒ new Swift files need NO pbxproj edits, but
  package references DO (careful pbxproj edit required).
- Key game files:
  - `WILDxCARD/views/RootView.swift` — scenePhase handlers (~lines 563–598):
    `.background` → `BGMManager.shared.pause()`, `.active` → `start()`; `.onAppear` →
    `syncAudioManagers()` + BGM start; `syncAudioManagers()` (~line 612) pushes the
    preferences snapshot into the audio singletons.
  - `WILDxCARD/Settings/BGMManager.swift` — the manager shape to mirror (singleton,
    `preferences` cached, idempotent start/stop/pause, BGM volume 0.05).
  - `WILDxCARD/Settings/UserPreferences.swift` — `bgmEnabled` pattern: `var … = true` +
    `decodeIfPresent(…) ?? true` (~lines 14–17, 41–44).
  - `WILDxCARD/views/SettingsView.swift` — "Background Music" `Toggle` with `.onChange`
    calling `BGMManager.shared.stop()/start()` (~line 211).
  - `WILDxCARD/Settings/SoundManager.swift` — owns the `.ambient` session + observes
    `AVAudioSession.interruptionNotification` (the interruption pattern to copy).
- Engine API for the host: `CitizenDJEngine(config:)` (SystemRandomNumberGenerator
  convenience), `EngineConfig.drumKitDirectory` (REQUIRED) / `.phraseDirectory`, then
  `DrumSequencer(engine:)`, `sequencer.volume`, `try sequencer.start()`, `sequencer.stop()`.
  `sequencer.start()` internally calls `beginRun()` and rebuilds player nodes, so
  stop/start cycles are cheap after the first sample load.

## Steps (each with verification)

1. **Worktree setup** — `git -C /Users/devian/Documents/Games/WILDxCARD worktree add
   ../.worktrees/generative-bgm -b feat/generative-bgm origin/master`. The game's main
   checkout stays untouched.
   Verify: `git worktree list` shows it; baseline build passes (`xcodebuild -scheme
   WILDxCARD -destination 'platform=iOS Simulator,name=<available iPhone>' build` — per the
   game's AGENTS.md; check which iPhone simulators exist first).

2. **Add CitizenDJ as a local path package dep (pbxproj edit)** — hand-edit
   `WILDxCARD.xcodeproj/project.pbxproj` in the game worktree using Xcode's standard
   generated shape: `XCLocalSwiftPackageReference` with `relativePath =
   ../../../DJswift/.worktrees/swift-engine` (relative from the game worktree), an
   `XCSwiftPackageProductDependency` for product `CitizenDJ`, wired into the app target's
   `packageProductDependencies` array + Frameworks build phase.
   Verify: `xcodebuild -resolvePackageDependencies -scheme WILDxCARD` resolves; full build
   succeeds.

3. **New `WILDxCARD/Settings/GenerativeBGMManager.swift`** (auto-synced into the target —
   no pbxproj edit for the file). Singleton mirroring `BGMManager`:
   - `var preferences: UserPreferences?` (synced from RootView).
   - Idempotent `start()/stop()/pause()`, gated on `preferences?.untitledSoundtrackEnabled`.
   - Engine + sequencer constructed ONCE, off-main (`Task.detached` — kit/phrase loading is
     file IO); retained for the app lifetime; scenePhase restarts reuse them.
   - Tunable constants at top: kit `SH_SFB2_KIT08_ONE_SHOTS` + phrases
     `SH_SFB2_KIT08_MELODY_LOOPS` (same pack — harmonic isolation, tempo-locked),
     `phraseLoopCount`, volume ≈ 0.2 (ambient BGM sits at 0.05; drums need presence — tune
     by ear). Alternatives if the pairing isn't right: `UFO`, `ultimate-pop`, `Bounce-loop`.
   - Does NOT touch the audio session. Observes `AVAudioSession.interruptionNotification`
     (stop on `.began`, restart on `.ended` if enabled) — same pattern as SoundManager.
   - `#if DEBUG` prints prefixed `[GenerativeBGM]` for verification.
   Verify: builds; logs show construction happened off-main.

4. **Preferences + Settings UI** —
   - `UserPreferences.swift`: `var untitledSoundtrackEnabled: Bool = false` +
     `decodeIfPresent(Bool.self, …) ?? false` (follow the `bgmEnabled` pattern).
   - `SettingsView.swift`: `Toggle("Untitled Game Soundtrack", isOn:
     $preferences.untitledSoundtrackEnabled)` next to "Background Music", `.onChange` →
     `GenerativeBGMManager.shared.stop()/start()` (mirror the bgmEnabled toggle's
     onChange). No cross-manager coupling — toggles are independent.
   Verify: build; toggle appears in Settings; persists across relaunch (PreferencesManager).

5. **RootView wiring (surgical, mirrors the BGMManager lines already there)** —
   - `syncAudioManagers()`: add `GenerativeBGMManager.shared.preferences = prefs`.
   - scenePhase `.background`: add `GenerativeBGMManager.shared.pause()`;
     `.active`: add `GenerativeBGMManager.shared.start()`.
   - `.onAppear`: add `GenerativeBGMManager.shared.start()` next to BGM start.
   Verify: build.

6. **End-to-end in the simulator** (ios-simulator MCP tools) —
   - Fresh launch with toggle OFF ⇒ zero behavior change (ambient BGM only, no
     `[GenerativeBGM]` start).
   - Flip "Untitled Game Soundtrack" ON ⇒ logs show engine built + sequencer started.
   - Background/foreground the app ⇒ stop/resume logs.
   - Flip OFF ⇒ sequencer stops.
   - Audible quality/mix check is the user's; report log + screenshot evidence.

7. **Notes** — update `task-list.md` (engine worktree) with integration status after the
   spike lands.

## Caveats

- **visionOS/mac destinations**: `Package.swift` declares `.iOS(.v16)`/`.macOS(.v13)` only;
  SwiftPM falls back to defaults for undeclared platforms. If a visionOS build complains,
  add `.visionOS(...)` to `Package.swift` then. iOS simulator is the spike's verification
  target.
- **Path dep fragility**: the engine worktree must stay at
  `/Users/devian/Documents/DJswift/.worktrees/swift-engine` while the game references it;
  moving/deleting it breaks the game project until re-pointed. Local-machine-only.
- **Known engine limitation**: one player node per instrument ⇒ very fast same-instrument
  retriggers can clip tails. Listen for it.
- **Interruptions**: scenePhase covers backgrounding; the interruption observer covers
  calls/Siri. If an edge case still leaves the engine silent, `DrumSequencer.stop()` then
  `start()` is the full reset.
- Build/test command per the game's AGENTS.md: trust `xcodebuild`, not single-file editor
  diagnostics.
