import Foundation
import CitizenDJ

// Usage:
//   citizen-dj-demo [--bars N] [--bpm N] [--kit <name>] [--phrase-dir <set>] [--loops N] [--phrase-rotate <bars>] [--out PATH]
//   citizen-dj-demo --list-sets
//   citizen-dj-demo --list-kits
//
// Defaults: 16 bars; 808 drums; tempo drifts via rotation unless --bpm / --phrase-dir lock it;
// output ./citizen-dj-loop.wav. Fresh random seed each run → a different loop every time.

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--list-sets") {
    print("Available phrase sets: \(PhraseBank.availableSetNames())")
    exit(0)
}
if args.contains("--list-kits") {
    print("Available drum kits: \(DrumKit.availableKitNames())")
    exit(0)
}

var bars = 16
var config = EngineConfig()
var outPath = "citizen-dj-loop.wav"

var idx = 0
while idx < args.count {
    switch args[idx] {
    case "--bars":           idx += 1; if idx < args.count { bars = Int(args[idx]) ?? bars }
    case "--bpm":            idx += 1; if idx < args.count { config.bpmOverride = Double(args[idx]) }
    case "--kit":            idx += 1; if idx < args.count { config.drumKitDirectory = args[idx] }
    case "--phrase-dir":     idx += 1; if idx < args.count { config.phraseDirectory = args[idx] }
    case "--loops":          idx += 1; if idx < args.count { config.phraseLoopCount = Int(args[idx]) ?? 1 }
    case "--phrase-rotate":  idx += 1; if idx < args.count { config.phraseRotationBars = Int(args[idx]) ?? 4 }
    case "--out":            idx += 1; if idx < args.count { outPath = args[idx] }
    default: break
    }
    idx += 1
}

let engine = try CitizenDJEngine(config: config)
let buffer = try engine.render(bars: bars)
let url = URL(fileURLWithPath: outPath)
try OfflineRenderer.writeWav(buffer, to: url)

let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
print("Rendered \(bars) bars (\(String(format: "%.1f", seconds))s) → \(url.path)")
print("Drums: \(config.drumKitDirectory.map { "kit '\($0)'" } ?? "808")")
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
