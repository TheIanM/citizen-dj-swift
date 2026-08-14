# Adding your own samples

How to bring your own drum kits and melodic phrase loops into this fork's Swift engine
(the `CitizenDJ` package + `citizen-dj-demo` CLI). Read this before dropping files into
`audio/` — the engine has conventions, and it follows them literally.

## TL;DR

1. Drum kit → a new folder under `audio/drumkits/<KitName>/` (nest however you like inside).
2. Phrase set → a new folder under `audio/phrases/<SetName>/` (nest however you like inside).
3. Run `./scripts/sync-resources.sh`, then rebuild.
4. Verify and listen:

```bash
swift run citizen-dj-demo --list-kits
swift run citizen-dj-demo --list-sets
swift run citizen-dj-demo --bars 16 --kit <KitName> --phrase-dir <SetName> --loops 2 --out loop.wav
```

## How audio flows (and why samples aren't in git)

`audio/drumkits/` and `audio/phrases/` are the canonical homes for your samples. The sync
script copies them into the package at `Sources/CitizenDJ/Resources/`, which is what the
engine actually reads at runtime. **Those copies are gitignored** — bulk audio never enters
git history. The repo only ships `data/drum_patterns.json` (the pattern library).

Consequences:

- Run `./scripts/sync-resources.sh` after **any** sample change, then rebuild.
- Everyone who clones supplies their own samples (a fresh checkout builds fine — kit/phrase
  tests just skip — but the engine needs at least one kit synced to make sound).
- The engine has **no built-in kit**. A run must name one (`--kit` / `drumKitDirectory`),
  otherwise you get `noDrumKitConfigured`. The demo defaults `--kit` to the first kit it finds.

## Harmonic isolation (the one rule)

Each run picks **exactly one** kit directory and **exactly one** phrase-set directory. Every
percussion hit comes only from that kit's folder tree; every melodic layer comes only from
that phrase set's folder tree. Nothing mixes across folders within a layer.

So design folders as coherent sonic identities: a kit folder = one drum sound family; a phrase
set folder = one tempo + one key.

## Drum kits

### Where & what

- A folder **directly under** `audio/drumkits/` — the folder name is the kit name you pass
  via `--kit`. (Sets can't be nested inside each other; contents inside can nest freely.)
- `.wav` files only — anything else (mp3, aiff, …) is silently ignored.
- `.DS_Store` is stripped automatically; mixed sample rates are fine (buffers are resampled
  to the kit's common format when loaded).

### How samples are classified

Each wav is classified into **one instrument category**, derived from its lowercased
filename **plus its immediate parent folder name**. The first keyword found wins, in this
priority order:

| # | keyword(s) | category |
|---|-----------|----------|
| 1 | `kick` | kick |
| 2 | `808` | 808 (sub-booms; used as a kick fallback) |
| 3 | `snare` | snare |
| 4 | `clap` | clap |
| 5 | `hihat`, `hat` | hat |
| 6 | `crash` | crash |
| 7 | `ride` | ride |
| 8 | `tom` | tom |
| 9 | `perc` | perc |
| 10 | `foley` | foley |
| 11 | `fx` | fx |
| 12 | `snap` | snap |
| 13 | `impact` | impact |

Two layouts both work:

- instrument in the **filename**: `MyKit_Kick.wav`, `MyKit_Snare 2.wav`
- instrument in the **subfolder**: `Kick_Shots/anything.wav`, `Hat_Shots/01.wav`

Gotchas:

- **Substrings count**: `PhatBass.wav` contains "hat" → classified as a hi-hat. Watch names
  like "phat", "crash course", "impacted"…
- **Priority decides ties**: `ClapHat.wav` → clap (clap is checked before hat).
- Files matching **no** keyword are ignored — that includes fills/loops ("Short Fill",
  "Drum Loop"), which is by design (one-shots only).

### How categories map to the beat patterns

The engine plays the 224 hand-authored 16-step patterns from `data/drum_patterns.json`,
which reference short instrument codes. Each code pulls from kit categories in this order
(first category your kit actually has wins):

| pattern codes | instrument | categories tried, in order |
|---------------|-----------|----------------------------|
| `k` `ka` `kg` | kick | kick → 808 |
| `s` `sa` `sb` `sg` | snare | snare |
| `hc` `ho` `h` `ha` `hg` | hi-hats | hat |
| `c` `cg` | crash | crash |
| `y` `ya` `yg` `yl` | ride | ride |
| `r` `ra` `rg` | rimshot | perc → snare |
| `t` `ta` `tb` `tt` `ttt` `ttta` | toms | tom → perc |

Notes:

- If your kit lacks every category a code tries, that code's hits are simply **silent**
  (e.g., a kit with no crash → crash hits don't fire). That's isolation working, not a bug.
  **Minimum viable kit: kick + snare + hat.** Extra categories (clap, perc, foley, fx,
  snap, impact, ride, crash, tom) make beats fuller.
- You **can't invent new codes** — kits only voice the codes the patterns already use.
- When a kit loads, **one sample per served code is chosen at random** (a "voicing" for that
  run). Multiple variants in a category = variety from run to run.

## Phrase sets

### Where & what

- A folder **directly under** `audio/phrases/` — the folder name is the set name you pass via
  `--phrase-dir`. Contents can nest freely (e.g. `Bounce-loop/MELODY_LOOPS/*.wav`).
- `.wav` only, mixed sample rates fine (loops are resampled into the mix).

### Conventions that matter

- **Put the BPM in the filename** — anything matching `128BPM` or `128 BPM`
  (case-insensitive). The set's tempo comes from the first loop that declares one, and when a
  set is used the engine **locks the drum tempo to it** so the loop and the beat stay in
  sync. No BPM in any filename → no lock, and your loops will drift against the drums.
- **Use whole-bar loop lengths** — loops tile end-to-end, so a loop that is exactly N bars at
  its BPM (e.g. 4 bars @ 128 BPM = 7.5 s) stays on the grid forever. Odd-length loops drift
  off the beat every tile.
- **One key per set** — the engine does **not** parse key. Harmony inside a set is your
  responsibility (this is the isolation rule doing its job: split mixed-key material into
  separate sets).

At render time the engine layers `--loops N` loops from the set (re-)picked at random every
`--phrase-rotate` bars (default 4), tempo-locked unless you pass an explicit `--bpm`.

## Verify

```bash
./scripts/sync-resources.sh                 # stage patterns + your kits/phrases
swift run citizen-dj-demo --list-kits       # your kit should appear
swift run citizen-dj-demo --list-sets       # your phrase set should appear
swift test                                  # kit/phrase tests skip cleanly without samples
swift run citizen-dj-demo --bars 16 --kit UFO --phrase-dir Bounce-loop --loops 2 --out /tmp/loop.wav
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Kit/set missing from `--list-kits` / `--list-sets` | Not a top-level folder under `audio/drumkits/` (or `audio/phrases/`); sync not run; build not refreshed after sync |
| A sample never plays | Not a `.wav`; its name/folder matches no keyword; or its pattern code isn't served (kit lacks the category) |
| Crash / ride / toms are silent | Kit has none — expected; add them or accept the sparser beat |
| A sample plays as the wrong instrument | Substring misclassification ("Phat" → hat) — rename it; remember keyword priority |
| Loop drifts off the beat | Loop isn't a whole-bar length, or filenames carry no BPM so the tempo never locks |
| Two loops in a set clash | Mixed keys inside one set — split them into separate sets |
| `noDrumKitConfigured` | No kit passed and none synced — pass `--kit <name>` |
