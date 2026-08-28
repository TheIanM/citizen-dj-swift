# Task List — CitizenDJ Swift Engine

Goal: native Swift drum-loop generator (Swift Package) producing evolving, non-repetitive
loops on-device. BGM engine for the iOS game WILDxCARD. PR #1 MERGED to master
(2026-08-28); README CLI docs PR #2 open.

## Shipped (all committed & pushed)
- Core: kit/phrase decoding, expansion, TimingModel, OfflineRenderer (+WAV), conductor
  (BPM-tolerant rotation), demo CLI, 808 removed — engine requires a custom kit.
- Phrase layering (dir-isolated, tempo-lock, resampling) + loop rotation per block.
- DrumKit classifier (filename/subdir keywords → category → pattern codes).
- Reproducible generation: SeededRNG public, `--seed` (printed each run), sorted codes +
  aligned kit RNG draws (cross-launch + cross-kit determinism). 33 tests green.
- Docs: docs/adding-samples.md, docs/generation-cookbook.md.
- **Real-time `DrumSequencer`**: AVAudioEngine + per-code player nodes + loop players +
  look-ahead scheduler (~20ms ticks, ~250ms ahead). Generation unified behind
  `CitizenDJEngine.planNextBar()`/`BarPlan` (offline + live share one source of truth;
  equivalence-tested). Demo `--live <sec>` plays real time. NOTE: player timelines are
  bootstrapped with a tiny silence buffer — playerTime(forNodeTime:) is nil until a node
  has played something. Live tap-recording (`--record`) was attempted and produced empty
  files; dropped for now — recordings come from offline `--out` (reliable).

## WILDxCARD integration (2026-08-28) — SPIKE LANDED LOCALLY
- Game branch `feat/generative-bgm` (worktree `Games/.worktrees/generative-bgm/`), commit
  `723d2f5` — NOT yet pushed/PR'd. Plan doc: `docs/wildxcard-integration-plan.md`.
- Shipped: CitizenDJ as local path dep (first SPM dep in the game; pbxproj hand-edit),
  `GenerativeBGMManager` (engine+sequencer built once off-main, ~0.15s; interruption
  observer; shares the game's existing `.ambient` session), `untitledSoundtrackEnabled`
  pref (default off) + "Untitled Game Soundtrack" Settings toggle, RootView scenePhase
  wiring. Independent toggles: both ON = layered over the ambient playlist.
- Simulator-verified: default-off cold launch is a no-op; pref-on cold launch starts
  playback; background → stop, foreground → start; ambient BGM path unaffected. Also
  installed on a physical iPhone 15 Pro Max (dev-signed) for by-ear testing.
- Remaining: by-ear tuning (volume now 0.2, kit SH_SFB2_KIT08_ONE_SHOTS + melody loops,
  `--loops` at 1 — alternatives UFO/ultimate-pop/Bounce-loop), push + PR, and switching
  the path dep to a git dep before anything ships (local-machine-only as-is).

## Remaining ideas
- Onset detection (Accelerate/vDSP) as build-time slicer for richer section variety.
- Loop-selection refinement (complementary-part picking) / kit mapping tuning by ear.
- Investigate live installTap empty-buffer mystery if in-game capture is ever needed.
- /save-session notes at session wrap.

## Key conventions
- Harmonic isolation: one kit dir + one phrase dir per run.
- Bulk sample audio is gitignored; run `scripts/sync-resources.sh` after any sample change.
- Seeds: printed every run; reproducible for same kit+config; `--no-humanize` for exact
  cross-kit A/B. Seed sequences are not stable across engine versions.
