# Task List — CitizenDJ Swift Engine

Goal: native Swift drum-loop generator (Swift Package) producing evolving, non-repetitive
loops on-device. BGM engine for the iOS game WILDxCARD. Branch `swift-engine` (worktree
`<repo-parent>/.worktrees/swift-engine/`), PR #1 open on the fork.

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
