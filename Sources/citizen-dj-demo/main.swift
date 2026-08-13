import Foundation
import CitizenDJ

// Usage:
//   citizen-dj-demo [--bars N] [--bpm N] [--phrase-dir <set>] [--loops N] [--out PATH]
//   citizen-dj-demo --list-sets
//
// Defaults: 16 bars; tempo drifts via rotation unless --bpm or --phrase-dir locks it; output
// ./citizen-dj-loop.wav. Fresh random seed each run → a different loop every time.

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--list-sets") {
    print("Available phrase sets:")
    for name in PhraseBank.availableSetNames() { print("  \(name)") }
    exit(0)
}

var bars = 16
var config = EngineConfig()
var outPath = "citizen-dj-loop.wav"

var idx = 0
while idx < args.count {
    switch args[idx] {
    case "--bars":       idx += 1; if idx < args.count { bars = Int(args[idx]) ?? bars }
    case "--bpm":        idx += 1; if idx < args.count { config.bpmOverride = Double(args[idx]) }
    case "--phrase-dir": idx += 1; if idx < args.count { config.phraseDirectory = args[idx] }
    case "--loops":      idx += 1; if idx < args.count { config.phraseLoopCount = Int(args[idx]) ?? 1 }
    case "--out":        idx += 1; if idx < args.count { outPath = args[idx] }
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
if let bpm = engine.config.bpmOverride {
    print("Tempo: \(String(format: "%.0f", bpm)) bpm (locked)")
} else {
    let bs = engine.playedPatternBpms
    print("Tempo: drifting \(bs.min() ?? 0)–\(bs.max() ?? 0) bpm via rotation")
}
if let pb = engine.phraseBank {
    print("Phrase layer: set='\(pb.directoryName)' (\(pb.loops.count) loops), \(engine.config.phraseLoopCount) layered")
} else {
    print("Phrase layer: none")
}
print("Drum patterns: \(engine.playedPatternIds)")
