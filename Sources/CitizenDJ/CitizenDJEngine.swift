import AVFoundation

/// Tunable behavior for `CitizenDJEngine`.
public struct EngineConfig {
    /// Rotate the drum pattern every this many bars (≥1).
    public var barsPerRotation: Int = 4
    /// When rotating, prefer patterns whose BPM is within this much of the current/locked tempo.
    /// Widened automatically if no candidates match.
    public var bpmTolerance: Double = 6.0
    /// Swing amount ∈ [-0.5, 0.5] (see `TimingModel`).
    public var swingAmount: Double = 0.5
    /// Per-hit timing humanize on/off (see `TimingModel`).
    public var humanize: Bool = true
    /// When set, render every bar at this tempo instead of each pattern's own BPM.
    public var bpmOverride: Double? = nil
    /// Phrase set to layer over the drums (a directory under phrases/). nil = drums only.
    public var phraseDirectory: String? = nil
    /// How many loops from the set to layer at once.
    public var phraseLoopCount: Int = 1
    /// How often (in bars) to rotate the phrase loops for variety.
    public var phraseRotationBars: Int = 4
    /// REQUIRED: drum-kit directory (under drumkits/) to source percussion from. There is no
    /// bundled default kit — every run must name one.
    public var drumKitDirectory: String? = nil

    public init() {}
}

/// The conductor: picks/rotates drum patterns and layers phrase loops, so output keeps
/// evolving. Generic over the RNG so a live run uses `SystemRandomNumberGenerator` (fresh
/// each launch) while tests/renderings pass a seeded RNG for reproducibility.
public final class CitizenDJEngine<RNG: RandomNumberGenerator> {

    /// The percussion source — always a custom `DrumKit` (one directory subtree, harmonically
    /// isolated). The engine has no built-in kit.
    public let source: DrumKit
    public let patterns: [DrumPattern]
    public let patternKey: [String: String]
    public let phraseBank: PhraseBank?

    public var config: EngineConfig
    public private(set) var currentPattern: DrumPattern
    public private(set) var playedPatternIds: [String] = []
    public private(set) var playedPatternBpms: [Int] = []
    /// Phrase-loop names used per rotation block of the most recent `render(bars:)`.
    public private(set) var playedLoopBlocks: [[String]] = []

    private var rng: RNG

    public init(
        rng: RNG,
        config: EngineConfig = EngineConfig(),
        bundle: Bundle? = nil,
        startPatternIndex: Int? = nil
    ) throws {
        let b = bundle ?? Bundle.module

        guard let patternsURL = b.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data") else {
            throw CitizenDJEngineError.dataNotFound("drum_patterns.json")
        }
        let patternLibrary = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: patternsURL))
        self.patterns = patternLibrary.patterns
        self.patternKey = patternLibrary.patternKey

        var cfg = config
        var r = rng

        // Percussion always comes from a custom kit (one directory). No 808 fallback.
        guard let kitDir = cfg.drumKitDirectory else {
            throw CitizenDJEngineError.noDrumKitConfigured
        }
        let kit = try DrumKit(directoryName: kitDir,
                              codes: Array(patternLibrary.patternKey.keys),
                              bundle: b, rng: &r)
        self.source = kit

        // Phrase layer + tempo lock.
        let phraseBank: PhraseBank?
        if let dir = cfg.phraseDirectory {
            let pb = try PhraseBank(directoryName: dir, bundle: b)
            if cfg.bpmOverride == nil, let bpm = pb.bpm { cfg.bpmOverride = bpm }
            phraseBank = pb
        } else {
            phraseBank = nil
        }
        self.phraseBank = phraseBank
        self.config = cfg

        if let idx = startPatternIndex {
            self.currentPattern = patternLibrary.patterns[idx]
        } else {
            self.currentPattern = patternLibrary.patterns.randomElement(using: &r) ?? patternLibrary.patterns[0]
        }
        self.rng = r
    }

    /// Pick the next drum pattern: a random one within `bpmTolerance` of the current/locked
    /// tempo (excluding the current pattern), widening the tolerance if the pool is empty.
    public func pickNextPattern() -> DrumPattern {
        let target = config.bpmOverride ?? Double(currentPattern.bpm)
        var tolerance = config.bpmTolerance
        var candidates = patterns.filter {
            abs(Double($0.bpm) - target) <= tolerance && $0.id != currentPattern.id
        }
        while candidates.isEmpty && tolerance < 300 {
            tolerance *= 2
            candidates = patterns.filter {
                abs(Double($0.bpm) - target) <= tolerance && $0.id != currentPattern.id
            }
        }
        return candidates.randomElement(using: &rng) ?? currentPattern
    }

    /// Absolute-time drum-hit schedule for `barCount` bars, rotating the pattern every
    /// `barsPerRotation` bars on the downbeat. Expansion is filtered to the codes the kit serves.
    public func schedule(bars barCount: Int) -> [DrumHit] {
        let period = max(1, config.barsPerRotation)
        playedPatternIds.removeAll()
        playedPatternBpms.removeAll()

        var all: [DrumHit] = []
        var barStart = 0.0
        for bar in 0..<barCount {
            if bar > 0 && bar % period == 0 {
                currentPattern = pickNextPattern()
            }
            playedPatternIds.append(currentPattern.id)
            playedPatternBpms.append(currentPattern.bpm)

            let bpm = config.bpmOverride ?? Double(currentPattern.bpm)
            let tracks = currentPattern.expanded(machine: source.servedMachine)
            let hits = TimingModel.schedule(
                tracks: tracks, bpm: bpm,
                swingAmount: config.swingAmount, humanize: config.humanize,
                rng: &rng
            )
            for hit in hits {
                all.append(DrumHit(code: hit.code, step: hit.step, time: barStart + hit.time))
            }
            barStart += TimingModel.barDuration(bpm: bpm)
        }
        return all
    }

    /// Render `barCount` bars to an audio buffer: drums + rotated phrase loops.
    public func render(bars barCount: Int) throws -> AVAudioPCMBuffer {
        let hits = schedule(bars: barCount)
        let bpm = config.bpmOverride ?? Double(currentPattern.bpm)
        let loops = buildLoopPlacements(barCount: barCount, barDuration: TimingModel.barDuration(bpm: bpm))
        return try OfflineRenderer.render(hits: hits, source: source, loops: loops)
    }

    /// Phrase-loop placements, rotating the loop choice every `phraseRotationBars` bars.
    private func buildLoopPlacements(barCount: Int, barDuration: Double) -> [LoopPlacement] {
        playedLoopBlocks.removeAll()
        guard let pb = phraseBank, !pb.loops.isEmpty else { return [] }
        let blockBars = max(1, config.phraseRotationBars)
        let count = max(1, min(config.phraseLoopCount, pb.loops.count))

        var placements: [LoopPlacement] = []
        var bar = 0
        while bar < barCount {
            let thisBlock = min(blockBars, barCount - bar)
            let chosen = pb.loops.shuffled(using: &rng).prefix(count)
            playedLoopBlocks.append(Array(chosen.map(\.name)))
            let startSeconds = Double(bar) * barDuration
            let durationSeconds = Double(thisBlock) * barDuration
            for loop in chosen {
                placements.append(LoopPlacement(buffer: loop.buffer, startSeconds: startSeconds, durationSeconds: durationSeconds))
            }
            bar += thisBlock
        }
        return placements
    }
}

extension CitizenDJEngine where RNG == SystemRandomNumberGenerator {
    /// Convenience initializer for live use: random start pattern, fresh RNG each launch.
    public convenience init(
        config: EngineConfig = EngineConfig(),
        bundle: Bundle? = nil,
        startPatternIndex: Int? = nil
    ) throws {
        try self.init(rng: SystemRandomNumberGenerator(),
                      config: config, bundle: bundle, startPatternIndex: startPatternIndex)
    }
}

public enum CitizenDJEngineError: Error {
    case dataNotFound(String)
    case noDrumKitConfigured
}
