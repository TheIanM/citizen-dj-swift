import Foundation
import CitizenDJ

// Usage: citizen-dj-demo [bars] [outputPath]
// Uses a fresh random generator each run, so every launch produces a different loop.
let bars = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 16 : 16
let outPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "citizen-dj-loop.wav"

let engine = try CitizenDJEngine()
let buffer = try engine.render(bars: bars)

let url = URL(fileURLWithPath: outPath)
try OfflineRenderer.writeWav(buffer, to: url)

let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
print("Rendered \(bars) bars (\(String(format: "%.1f", seconds))s) → \(url.path)")
print("Patterns rotated (\(engine.playedPatternIds.count) bars, every \(engine.config.barsPerRotation)):")
print("  ids : \(engine.playedPatternIds)")
print("  bpms: \(engine.playedPatternBpms)  (range \(engine.playedPatternBpms.min() ?? 0)–\(engine.playedPatternBpms.max() ?? 0))")
