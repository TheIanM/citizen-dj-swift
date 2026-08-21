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
| `--bpm-tolerance X` | 6 | Rotation picks patterns within ±X BPM of the current/locked tempo (0 = exact-BPM matches only; bigger = wilder tempo jumps when drifting) |
| `--seed N` | random (printed each run) | Reproduce an exact render — the run's seed is always printed |
| `--rotate N` | 4 | Rotate the drum pattern every N bars |
| `--swing X` | 0.5 | Swing amount (roughly -0.5…0.5) |
| `--no-humanize` | jitter on | Disable per-hit timing humanize |
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

**A/B two kits properly** — same seed ⇒ same pattern & loop choices, only the kit differs.
Add `--no-humanize` for exact alignment: the jitter consumes one random draw per hit, and
kits trigger different numbers of hits.

```bash
dj --bars 16 --seed 42 --bpm 120 --no-humanize --kit UFO --out /tmp/a_ufo.wav
dj --bars 16 --seed 42 --bpm 120 --no-humanize --kit ultimate-pop --out /tmp/a_pop.wav
```

**Reproduce a render** — every run prints its seed; pass it back to get that exact render
again (same kit & settings):

```bash
dj --bars 16 --kit UFO --phrase-dir Bounce-loop --out /tmp/loop.wav   # note the printed seed
dj --bars 16 --seed <printed-seed> --kit UFO --phrase-dir Bounce-loop --out /tmp/again.wav
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

## Live playback (the in-game path)

The same generator can play in REAL TIME — `AVAudioEngine` with a look-ahead scheduler —
through your speakers instead of bouncing a file. This is the mode a game embeds
(`DrumSequencer` in the library):

```bash
dj --live 30 --kit UFO --phrase-dir Bounce-loop --loops 2
dj --live 15 --seed 9 --bpm 110 --kit ultimate-pop
```

`--live <seconds>` plays for that long and exits. For a recording, use the offline bounce
(`--out`) — it's the reliable capture path; live mode is for listening. Live and offline make
identical generation choices from the same seed (both consume the engine bar-by-bar). iOS
note: the host app configures `AVAudioSession` — the library stays session-agnostic.

## Dev-loop commands

```bash
./scripts/sync-resources.sh   # after adding/changing ANY sample — then rebuild
swift build                   # compile
swift test                    # full suite (kit/phrase tests skip without samples)
swift package clean           # if the bundled resources ever look stale or wrong
```

## Reproducibility & footguns

Every run rolls a random seed and **prints it** — pass it back with `--seed` to reproduce
that exact render (same kit & settings). The same seed across *different* kits gives the same
pattern/loop choices, but byte-exact cross-kit alignment needs `--no-humanize` (the jitter
consumes one random draw per hit, and kits trigger different numbers of hits).

Every engine knob is now exposed as a CLI flag; anything else lives in `EngineConfig`.

Two footguns to remember: unknown flags are **ignored silently** (a typo like `--phrase_dir`
just quietly drops the melody layer), and `--out` defaults to your current working directory.
