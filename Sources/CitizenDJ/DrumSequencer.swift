import AVFoundation
import Foundation

/// Plays a `CitizenDJEngine` live through `AVAudioEngine` — the real-time counterpart to the
/// offline renderer, and the piece a game (WILDxCARD) embeds for procedural BGM.
///
/// - Drums trigger as one-shots on one `AVAudioPlayerNode` per instrument code.
/// - Phrase loops play on dedicated per-slot player nodes, scheduled at rotation-block starts.
/// - A look-ahead scheduler (a `DispatchSourceTimer` on a private serial queue, ~20 ms ticks)
///   asks the engine for the next `BarPlan` and schedules audio ~250 ms ahead of the
///   speaker, so main-thread/UI jitter can never cause late hits.
///
/// Threading: `CitizenDJEngine` is not thread-safe; this class drives it exclusively from its
/// scheduler queue. `AVAudioSession` configuration (category, mixing with SFX, background
/// behavior) is the host app's job — this stays session-agnostic.
///
/// Known limitation: each instrument has a single player node (single voice), so a very fast
/// re-trigger of the same instrument can clip the previous hit's tail. Fine for drums; the
/// offline renderer remains the reference for exact mixes.
/// Sequencer tuning constants (static stored properties aren't allowed in generic types).
private enum SequencerTuning {
    /// How far ahead of "now" audio is scheduled.
    static let lookAheadSeconds: Double = 0.25
    /// Scheduler tick interval.
    static let tickInterval: TimeInterval = 0.02
    /// Lead-in before bar 0, so the first scheduled events aren't in the past.
    static let startLeadSeconds: Double = 0.1
}

public final class DrumSequencer<RNG: RandomNumberGenerator> {

    private let cdj: CitizenDJEngine<RNG>
    private let audio = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var drumPlayers: [String: AVAudioPlayerNode] = [:]
    private var loopPlayers: [AVAudioPlayerNode] = []
    private let queue = DispatchQueue(label: "citizendj.sequencer")
    private var timer: DispatchSourceTimer?

    // Transport, on the player nodes' timeline (sample positions).
    private var rate: Double = 0
    private var zeroFrame: AVAudioFramePosition?
    private var scheduledThrough: Double = 0   // run-seconds already scheduled
    private var runBarStart: Double = 0        // run-time start of the next unplanned bar
    private var loopCache: [ObjectIdentifier: AVAudioPCMBuffer] = [:]

    public private(set) var isPlaying = false

    /// The underlying `AVAudioEngine` — exposed for host-app integration
    /// (inspection, routing, custom processing).
    public var audioEngine: AVAudioEngine { audio }

    public init(engine: CitizenDJEngine<RNG>) {
        self.cdj = engine
    }

    deinit { stop() }

    /// Master output volume (0…1). Safe to set from any thread.
    public var volume: Float {
        get { mixer.volume }
        set { mixer.volume = newValue }
    }

    public func start() throws {
        try queue.sync {
            guard !isPlaying else { return }

            let format = cdj.source.commonFormat
            rate = format.sampleRate

            audio.attach(mixer)
            audio.connect(mixer, to: audio.mainMixerNode, format: format)
            for code in cdj.source.loadedCodes.sorted() {
                let player = AVAudioPlayerNode()
                audio.attach(player)
                audio.connect(player, to: mixer, format: format)
                drumPlayers[code] = player
            }
            for _ in 0..<max(1, cdj.config.phraseLoopCount) {
                let player = AVAudioPlayerNode()
                audio.attach(player)
                audio.connect(player, to: mixer, format: format)
                loopPlayers.append(player)
            }

            cdj.beginRun()
            scheduledThrough = 0
            runBarStart = 0
            loopCache.removeAll()

            audio.prepare()
            try audio.start()
            (drumPlayers.values + loopPlayers).forEach { $0.play() }

            // Bootstrap the players' timelines: playerTime(forNodeTime:) returns nil until a
            // node has actually started playing a buffer, so feed each one a tiny inaudible
            // buffer "now" — after this the transport zero can be captured on a later tick.
            if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256) {
                silence.frameLength = 256
                for ch in 0..<Int(format.channelCount) {
                    memset(silence.floatChannelData![ch], 0, MemoryLayout<Float32>.size * 256)
                }
                (drumPlayers.values + loopPlayers).forEach { $0.scheduleBuffer(silence, at: nil) }
            }
            isPlaying = true

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: SequencerTuning.tickInterval)
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    public func stop() {
        queue.sync {
            guard isPlaying else { return }
            timer?.cancel()
            timer = nil
            (drumPlayers.values + loopPlayers).forEach { $0.stop() }
            audio.stop()
            audio.reset()
            drumPlayers.values.forEach(audio.detach)
            drumPlayers.removeAll()
            loopPlayers.forEach(audio.detach)
            loopPlayers.removeAll()
            audio.detach(mixer)
            isPlaying = false
        }
    }

    // MARK: - private

    private func tick() {
        guard isPlaying else { return }
        if zeroFrame == nil { captureZero() }
        guard let zero = zeroFrame else { return }
        guard let nowRunSeconds = currentRunSeconds(zero: zero) else { return }

        while scheduledThrough < nowRunSeconds + SequencerTuning.lookAheadSeconds {
            let plan = cdj.planNextBar()
            let barNode = zero + AVAudioFramePosition(runBarStart * rate)

            for hit in plan.hits {
                guard let player = drumPlayers[hit.code],
                      let buffer = cdj.source.buffer(for: hit.code) else { continue }
                player.scheduleBuffer(buffer, at: nodeTime(barNode + AVAudioFramePosition(hit.time * rate)))
            }
            for (slot, placement) in plan.loopPlacements.enumerated() {
                guard slot < loopPlayers.count else { continue }
                let buffer = convertedLoop(placement.buffer)
                let period = Double(buffer.frameLength) / rate
                guard period > 0 else { continue }
                var t = placement.startSeconds
                while t < placement.startSeconds + placement.durationSeconds {
                    loopPlayers[slot].scheduleBuffer(buffer, at: nodeTime(barNode + AVAudioFramePosition(t * rate)))
                    t += period
                }
            }
            runBarStart += plan.barDuration
            scheduledThrough = runBarStart
        }
    }

    /// Capture the transport zero (node frame of bar 0) once the players are rendering.
    private func captureZero() {
        guard let ref = referencePlayer(),
              let last = ref.lastRenderTime, last.isSampleTimeValid,
              let node = ref.playerTime(forNodeTime: last) else { return }
        rate = node.sampleRate
        zeroFrame = node.sampleTime + AVAudioFramePosition(SequencerTuning.startLeadSeconds * node.sampleRate)
    }

    /// Current position in run-seconds, or nil if the render clock can't be queried yet.
    private func currentRunSeconds(zero: AVAudioFramePosition) -> Double? {
        guard let ref = referencePlayer(),
              let last = ref.lastRenderTime, last.isSampleTimeValid,
              let node = ref.playerTime(forNodeTime: last) else { return nil }
        return Double(node.sampleTime - zero) / node.sampleRate
    }

    private func referencePlayer() -> AVAudioPlayerNode? {
        drumPlayers.values.sorted { $0.debugDescription < $1.debugDescription }.first ?? loopPlayers.first
    }

    private func nodeTime(_ frame: AVAudioFramePosition) -> AVAudioTime {
        AVAudioTime(sampleTime: frame, atRate: rate)
    }

    /// Loops are cached in the output format so each is resampled at most once per run.
    private func convertedLoop(_ raw: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let key = ObjectIdentifier(raw)
        if let cached = loopCache[key] { return cached }
        let converted = AudioConvert.resample(raw, to: cdj.source.commonFormat)
        loopCache[key] = converted
        return converted
    }
}
