import Foundation
import AVFoundation
import CitizenDJ

// Usage:
//   citizen-dj-demo [--bars N] [--bpm N] [--bpm-tolerance X] [--kit <name>] [--phrase-dir <set>]
//                   [--loops N] [--phrase-rotate <bars>] [--rotate <bars>] [--swing X]
//                   [--no-humanize] [--seed N] [--out PATH]
//                   [--live <seconds>]   (play in real time instead of bouncing a file)
//   citizen-dj-demo --list-kits | --list-sets
//
// A drum kit is required (defaults to the first bundled kit). Every run rolls a random seed
// and PRINTS it — pass it back via --seed to reproduce that exact render. Recordings come
// from the offline bounce (--out); --live is for listening (and mirrors the in-game path).

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--list-kits") {
    print("Available drum kits: \(DrumKit.availableKitNames())")
    exit(0)
}
if args.contains("--list-sets") {
    print("Available phrase sets: \(PhraseBank.availableSetNames())")
    exit(0)
}

var bars = 16
var config = EngineConfig()
var outPath = "citizen-dj-loop.wav"
var seed: UInt64?
var liveSeconds: Double?

var idx = 0
while idx < args.count {
    switch args[idx] {
    case "--bars":           idx += 1; if idx < args.count { bars = Int(args[idx]) ?? bars }
    case "--bpm":            idx += 1; if idx < args.count { config.bpmOverride = Double(args[idx]) }
    case "--bpm-tolerance":  idx += 1; if idx < args.count { config.bpmTolerance = Double(args[idx]) ?? config.bpmTolerance }
    case "--kit":            idx += 1; if idx < args.count { config.drumKitDirectory = args[idx] }
    case "--phrase-dir":     idx += 1; if idx < args.count { config.phraseDirectory = args[idx] }
    case "--loops":          idx += 1; if idx < args.count { config.phraseLoopCount = Int(args[idx]) ?? 1 }
    case "--phrase-rotate":  idx += 1; if idx < args.count { config.phraseRotationBars = Int(args[idx]) ?? 4 }
    case "--rotate":         idx += 1; if idx < args.count { config.barsPerRotation = Int(args[idx]) ?? 4 }
    case "--swing":          idx += 1; if idx < args.count { config.swingAmount = Double(args[idx]) ?? config.swingAmount }
    case "--no-humanize":    config.humanize = false
    case "--seed":           idx += 1; if idx < args.count { seed = UInt64(args[idx]) }
    case "--live":           idx += 1; if idx < args.count { liveSeconds = Double(args[idx]) ?? 30 }
    case "--out":            idx += 1; if idx < args.count { outPath = args[idx] }
    default: break
    }
    idx += 1
}

// A kit is required — default to the first bundled kit if none was specified.
if config.drumKitDirectory == nil {
    let kits = DrumKit.availableKitNames()
    guard let first = kits.first else {
        FileHandle.standardError.write("No drum kit configured and none bundled. Pass --kit <name>.\n".data(using: .utf8)!)
        exit(1)
    }
    config.drumKitDirectory = first
}

// Roll (or take) the seed, then generate deterministically from it. Printing the seed every
// run means any render can be reproduced after the fact.
let effectiveSeed = seed ?? UInt64.random(in: .min ... .max)
let engine = try CitizenDJEngine(rng: SeededRNG(seed: effectiveSeed), config: config)

if let liveSeconds {
    // Real-time playback through AVAudioEngine — the path a game embeds.
    let sequencer = try DrumSequencer(engine: engine)
    try sequencer.start()
    print("Playing LIVE for \(String(format: "%.0f", liveSeconds))s — kit '\(engine.source.directoryName)'" +
          (engine.phraseBank.map { ", phrase '\($0.directoryName)'" } ?? "") +
          "… (seed \(effectiveSeed); re-render offline with --out to capture)")
    Thread.sleep(forTimeInterval: liveSeconds)
    sequencer.stop()
    exit(0)
}

let buffer = try engine.render(bars: bars)
let url = URL(fileURLWithPath: outPath)
try OfflineRenderer.writeWav(buffer, to: url)

let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
print("Rendered \(bars) bars (\(String(format: "%.1f", seconds))s) → \(url.path)")
if seed == nil {
    print("Seed: \(effectiveSeed) (random — re-run with --seed \(effectiveSeed) to reproduce)")
} else {
    print("Seed: \(effectiveSeed) (locked)")
}
print("Drums: kit '\(engine.source.directoryName)'")
if let bpm = engine.config.bpmOverride {
    print("Tempo: \(String(format: "%.0f", bpm)) bpm (locked)")
} else {
    let bs = engine.playedPatternBpms
    print("Tempo: drifting \(bs.min() ?? 0)–\(bs.max() ?? 0) bpm")
}
if let pb = engine.phraseBank {
    print("Phrase: set='\(pb.directoryName)', \(engine.config.phraseLoopCount) layered, rotate every \(engine.config.phraseRotationBars) bars")
    print("  loop blocks: \(engine.playedLoopBlocks)")
} else {
    print("Phrase: none")
}
print("Drum patterns: \(engine.playedPatternIds)")
