# Generation cookbook — commands for quick testing & experiments

Copy-paste commands for the `citizen-dj-demo` CLI. Run everything from the repository root
(the folder containing `Package.swift`). Until `swift-engine` merges to `master`, that means
your branch checkout / worktree.

Optional alias to cut the typing:

```bash
alias dj='swift run citizen-dj-demo'
```

The first `swift run` compiles; after that each render takes a second or two. Every render
prints what it chose (drum patterns, loop blocks, tempo) — that output is your experiment
log, read it.

## Discover what's installed

```bash
dj --list-kits     # drum kits found under audio/drumkits/
dj --list-sets     # phrase sets found under audio/phrases/
```

## The everyday command

```bash
dj --bars 16 --kit UFO --phrase-dir Bounce-loop --loops 2 --out /tmp/loop.wav
open /tmp/loop.wav
```

## Flag reference

| Flag | Default | What it does |
|---|---|---|
| `--bars N` | 16 | Length in bars |
| `--kit NAME` | first bundled kit | Drum-kit folder (under `audio/drumkits/`) |
| `--phrase-dir NAME` | none — drums only | Phrase-set folder (under `audio/phrases/`) |
| `--loops N` | 1 | How many loops from the set layer at once |
| `--phrase-rotate N` | 4 | Re-pick loops every N bars |
| `--bpm N` | see tempo rules below | Lock the tempo |
| `--out PATH` | `./citizen-dj-loop.wav` (in your cwd) | Output WAV |
| `--list-kits` / `--list-sets` | — | Print what's installed and exit |

## How the tempo gets decided (in priority order)

1. `--bpm`, if you pass it
2. else the phrase set's filename BPM (e.g. `128BPM` in the loop names) when `--phrase-dir`
   is given — the beat locks to the loops so they stay in sync
3. else **drift**: each pattern carries its own BPM and rotation drifts within ±6 BPM per
   pattern change

## How long is a render?

`seconds ≈ bars × 240 / bpm`

| bars | @ 90 bpm | @ 128 bpm |
|---|---|---|
| 8 | 21 s | 15 s |
| 16 | 43 s | 30 s |
| 32 | 85 s | 60 s |

Tip: pick `--bars` in multiples of your rotation setting (4 by default) so phrase-loop blocks
land cleanly on bar boundaries instead of getting clipped mid-phrase.

## Recipes

**Quick sketch** (8 bars, drums only, default kit):

```bash
dj --bars 8 --out /tmp/sketch.wav && open /tmp/sketch.wav
```

**Standard beat + melody:**

```bash
dj --bars 16 --kit UFO --phrase-dir Bounce-loop --loops 2 --out /tmp/full.wav
```

**Long-form listen** (~1 minute):

```bash
dj --bars 32 --kit ultimate-pop --phrase-dir SH_SFB2_KIT08_MELODY_LOOPS --loops 2 --out /tmp/long.wav
```

**Audition a kit at a fixed tempo:**

```bash
dj --bars 16 --bpm 110 --kit UFO --out /tmp/ufo110.wav
```

**A/B two kits** (same tempo + length; note each render still randomizes internally — see
[reproducibility](#reproducibility--knobs-not-exposed-as-flags)):

```bash
dj --bars 16 --bpm 120 --kit UFO --out /tmp/a_ufo.wav
dj --bars 16 --bpm 120 --kit ultimate-pop --out /tmp/a_pop.wav
```

**Denser / sparser melody:**

```bash
dj --bars 16 --phrase-dir Bounce-loop --loops 3 --out /tmp/dense.wav
dj --bars 16 --phrase-dir Bounce-loop --loops 1 --out /tmp/sparse.wav
```

**Chop the melody more often** (rotate loops every 2 bars):

```bash
dj --bars 16 --phrase-dir Bounce-loop --phrase-rotate 2 --out /tmp/choppy.wav
```

**Churn a batch of variations and audition them:**

```bash
for i in 1 2 3 4; do
  dj --bars 16 --kit UFO --phrase-dir Bounce-loop --loops 2 --out /tmp/dj_$i.wav
done
open /tmp/dj_*.wav
```

## Dev-loop commands

```bash
./scripts/sync-resources.sh   # after adding/changing ANY sample — then rebuild
swift build                   # compile
swift test                    # full suite (kit/phrase tests skip without samples)
swift package clean           # if the bundled resources ever look stale or wrong
```

## Reproducibility & knobs not exposed as flags

Every run rolls a fresh random seed, so no two renders are identical — great for variety,
annoying for A/B testing. There are also engine knobs that currently exist only in code
(`EngineConfig`), not as CLI flags:

- swing amount (`swingAmount`) and timing humanize (`humanize`)
- drum-pattern rotation length (`barsPerRotation`, default 4)
- rotation BPM tolerance (`bpmTolerance`, default ±6)

Two footguns to remember: unknown flags are **ignored silently** (a typo like `--phrase_dir`
just quietly drops the melody layer), and `--out` defaults to your current working directory.
