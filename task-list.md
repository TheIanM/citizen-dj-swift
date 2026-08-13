# Task List — CitizenDJ Swift Engine

Goal: native Swift drum-loop generator (Swift Package) producing evolving, non-repetitive
drum loops on-device from Citizen DJ's existing drum samples. Eventual BGM engine for the
iOS game WILDxCARD. Working on branch `swift-engine` in worktree
`<repo-parent>/.worktrees/swift-engine/`.

## Scope (updated after kickoff)
- **Drum machine: Roland TR-808 ONLY** (id `t808`, 27 one-shot mp3s). Not all 8 machines.
- Variation = **pattern rotation + timing humanization** only. Machine rotation dropped
  (only one machine). Micro-mutation remains an optional later toggle.
- Out of MVP: LOC melodic samples, recording, share-by-URL, UI, gameplay-reactive music.

## Progress
- [x] **Chunk 1** — Worktree + `swift-engine` branch; `Package.swift` + `CitizenDJ`
      library/test scaffolded. ✅ `swift build` + `swift test` green.
- [x] **Chunk 2** — Bundled ONLY the 27 TR-808 mp3s + 2 jsons into `Resources/` via
      `scripts/sync-resources.sh`. ✅ `Bundle.module` locates them (under `audio/` + `data/`).
- [x] **Chunk 3** — Codable models + custom positional decoders. ✅ 8 machines, 224 patterns,
      patternKey=27, all patterns 16 steps; verified code→file mappings.
- [x] **Chunk 4** — `DrumPattern.expanded(machine:)` (port of `drums.js loadTrackData`).
      ✅ known-pattern rows + graceful skip of unknown codes verified.
- [x] **Chunk 5** — `SampleBank`: decodes all 27 808 one-shots into `AVAudioPCMBuffer`,
      shared `commonFormat`. ✅ every code 2kfA1 uses resolves to a buffer.
- [x] **Chunk 6** — `TimingModel` (pure swing/humanize math from `sequencer.js`/`track.js`).
      ✅ Fixed a grid-vs-feel bug: steps are true 16th-notes (`60/bpm/4`); swing/humanize use
      the original's gentler `feelBase` (`60/bpm/16`). **23 tests passing total.**
- [x] **Chunk 7** — `OfflineRenderer`: additively mixes bank buffers per a `TimingModel`
      schedule into an `AVAudioPCMBuffer` (+ `writeWav`). ✅ correct length, non-silent, hits
      land at exact frames, valid WAV output.
- [x] **Chunk 8** — `CitizenDJEngine` conductor: BPM-tolerant rotation every `barsPerRotation`
      bars + `citizen-dj-demo` CLI. ✅ rotation cadence, BPM tolerance, render verified.
      **Audible milestone:** `swift run citizen-dj-demo 32 /tmp/loop.wav` renders an evolving
      ~86s loop (8 patterns, BPM drifting 81→98 within ±6 per rotation). **23 tests passing.**
      - Data quirk found: `drum_patterns.json` has non-unique ids; the engine never keys by id
        into a Dictionary, so it's unaffected (tests read `playedPatternBpms` instead).
- [ ] **Chunk 9** — `DrumSequencer`: real-time `AVAudioEngine` + per-code `AVAudioPlayerNode`
      + look-ahead scheduler for LIVE in-game playback (vs. the pre-rendered demo). The hardest
      part; validated against the offline renderer + manual listening.
- [ ] **Chunk 10 (optional)** — micro-mutation toggle (per-bar step flips) for richer variation.
- [ ] **Chunk 11** — README section + `/save-session` notes.

## Decisions / notes
- **Resource bundling**: copy 808 mp3s + jsons into `Sources/CitizenDJ/Resources/` via
  `scripts/sync-resources.sh` (chosen over SPM root-target `exclude` for cleanliness).
  Decided to commit the staged copies so the package is self-contained/distributable for
  WILDxCARD; the sync script is the maintenance tool to re-sync if canonical assets change.
  Canonical sources: `audio/drum_machines/Roland_Tr-808_full__*.mp3`, `data/*.json`.
- **808 codes**: c, cg, h, ho, hc, k, ka, kg, r, ra, rg, s, sa, sb, sg, t, ta, tb, tt, ttt,
  ttta, y, ya, yg, yl, ha, hg (27).
- Deployment floors (adjustable): iOS 16, macOS 13.
