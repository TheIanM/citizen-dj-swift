import AVFoundation

/// Tunable behavior for `CitizenDJEngine`.
public struct EngineConfig {
    /// Rotate to a new pattern every this many bars (≥1).
    public var barsPerRotation: Int = 4
    /// When rotating, prefer patterns whose BPM is within this much of the current one so the
    /// tempo drifts gently instead of jumping. Widened automatically if no candidates match.
    public var bpmTolerance: Double = 6.0
    /// Swing amount ∈ [-0.5, 0.5] (see `TimingModel`).
    public var swingAmount: Double = 0.5
    /// Per-hit timing humanize on/off (see `TimingModel`).
    public var humanize: Bool = true
    /// When set, render every bar at this tempo instead of each pattern's own BPM. Patterns
    /// still rotate for content variety, and rotation stays within `bpmTolerance` of this
    /// tempo. nil = use each pattern's native BPM (tempo drifts as patterns rotate).
    public var bpmOverride: Double? = nil
    /// Phrase set to layer over the drums (a directory name under phrases/, e.g. "Bounce-loop").
    /// nil = drums only. When set, the drum tempo locks to the set's BPM so loops stay in sync.
    public var phraseDirectory: String? = nil
    /// How many loops from the set to layer simultaneously.
    public var phraseLoopCount: Int = 1

    public init() {}
}

/// The conductor: picks patterns and rotates them over time so the loop never repeats
/// indefinitely — the core of the "new BGM each run" behavior.
///
/// It's generic over the RNG so a live run uses `SystemRandomNumberGenerator` (fresh every
/// launch) while tests/renderings can pass a seeded RNG for reproducibility.
public final class CitizenDJEngine<RNG: RandomNumberGenerator> {

    public let machine: DrumMachine
    public let bank: SampleBank
    public let patterns: [DrumPattern]
    public let patternKey: [String: String]
    /// The loaded phrase loop set, if `config.phraseDirectory` was set; otherwise nil.
    public let phraseBank: PhraseBank?

    public var config: EngineConfig
    public private(set) var currentPattern: DrumPattern
    /// Pattern id used on each bar of the most recent `schedule(bars:)` call (for tests / introspection).
    /// Note: pattern ids in the data are NOT unique, so use `playedPatternBpms` when you need
    /// to reason about the actual pattern, not just its id.
    public private(set) var playedPatternIds: [String] = []
    /// BPM of the pattern used on each bar of the most recent `schedule(bars:)` call.
    public private(set) var playedPatternBpms: [Int] = []

    private var rng: RNG

    /// Load the TR-808 + all patterns from `bundle` (defaults to the package bundle) and choose
    /// a starting pattern. Pass `startPatternIndex` for a deterministic start; otherwise it's random.
    public init(
        rng: RNG,
        config: EngineConfig = EngineConfig(),
        bundle: Bundle? = nil,
        startPatternIndex: Int? = nil
    ) throws {
        let b = bundle ?? Bundle.module

        guard let machinesURL = b.url(forResource: "drum_machines", withExtension: "json", subdirectory: "data") else {
            throw CitizenDJEngineError.dataNotFound("drum_machines.json")
        }
        let library = try JSONDecoder().decode(DrumLibrary.self, from: Data(contentsOf: machinesURL))
        guard let patternsURL = b.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data") else {
            throw CitizenDJEngineError.dataNotFound("drum_patterns.json")
        }
        let patternLibrary = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: patternsURL))
        guard let machine = library.machine(id: "t808") else {
            throw CitizenDJEngineError.machineNotFound("t808")
        }

        // Optional phrase layer: load ONE directory's loops (harmonic isolation), and if the
        // set declares a tempo, lock the drum tempo to it so loops and drums stay in sync.
        var cfg = config
        let phraseBank: PhraseBank?
        if let dir = cfg.phraseDirectory {
            let pb = try PhraseBank(directoryName: dir, bundle: b)
            if cfg.bpmOverride == nil, let bpm = pb.bpm { cfg.bpmOverride = bpm }
            phraseBank = pb
        } else {
            phraseBank = nil
        }

        self.machine = machine
        self.bank = try SampleBank(machine: machine, bundle: b)
        self.patterns = patternLibrary.patterns
        self.patternKey = patternLibrary.patternKey
        self.config = cfg
        self.phraseBank = phraseBank

        var r = rng
        if let idx = startPatternIndex {
            self.currentPattern = patternLibrary.patterns[idx]
        } else {
            self.currentPattern = patternLibrary.patterns.randomElement(using: &r) ?? patternLibrary.patterns[0]
        }
        self.rng = r
    }

    /// Pick the next pattern: a random one within `bpmTolerance` of the current BPM (excluding
    /// the current pattern), widening the tolerance if the pool is empty. Always changes the
    /// pattern id when more than one exists.
    public func pickNextPattern() -> DrumPattern {
        // Anchor rotation to the override tempo when set, so chosen patterns groove naturally
        // at the locked tempo; otherwise drift relative to the current pattern's BPM.
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

    /// Absolute-time hit schedule for `barCount` bars, rotating the pattern every
    /// `barsPerRotation` bars on the downbeat. Bars are sequenced back-to-back, so a BPM
    /// change between rotations just changes the following bar's length.
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

            // Locked tempo overrides each pattern's native BPM; the step content still comes
            // from the (rotating) pattern, so variety is preserved at a steady tempo.
            let bpm = config.bpmOverride ?? Double(currentPattern.bpm)
            let tracks = currentPattern.expanded(machine: machine)
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

    /// Render `barCount` bars straight to an audio buffer (convenience over `OfflineRenderer`).
    public func render(bars barCount: Int) throws -> AVAudioPCMBuffer {
        let hits = schedule(bars: barCount)

        // Layer N loops from the active phrase set (random selection → variety run to run).
        let loopBuffers: [AVAudioPCMBuffer]
        if let pb = phraseBank, !pb.loops.isEmpty {
            let count = max(1, min(config.phraseLoopCount, pb.loops.count))
            loopBuffers = pb.loops.shuffled(using: &rng).prefix(count).map(\.buffer)
        } else {
            loopBuffers = []
        }
        return try OfflineRenderer.render(hits: hits, bank: bank, loopBuffers: loopBuffers)
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
    case machineNotFound(String)
}
