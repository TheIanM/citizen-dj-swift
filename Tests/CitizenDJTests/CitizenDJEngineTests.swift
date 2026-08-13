import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests for the conductor — pattern rotation that keeps the loop evolving.
final class CitizenDJEngineTests: XCTestCase {

    func testEngineLoadsAllData() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), startPatternIndex: 0)
        XCTAssertEqual(engine.patterns.count, 224)
        XCTAssertEqual(engine.source.loadedCodes.count, 27)
        XCTAssertFalse(engine.patternKey.isEmpty)
        XCTAssertEqual(engine.currentPattern.id, "2kfA1")  // startPatternIndex 0
    }

    func testScheduleCoversRequestedBarCount() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), startPatternIndex: 0)
        let hits = engine.schedule(bars: 4)

        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(engine.playedPatternIds.count, 4)
        // hits should span roughly 4 bars (~8s at 117 bpm).
        let total = hits.map(\.time).max() ?? 0
        XCTAssertGreaterThan(total, 5.0)
    }

    /// With barsPerRotation = 2, the pattern must hold for 2 bars then change on the downbeat.
    func testRotationChangesPatternEveryNBars() throws {
        var config = EngineConfig()
        config.barsPerRotation = 2
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 3), config: config, startPatternIndex: 0)
        _ = engine.schedule(bars: 6)

        let ids = engine.playedPatternIds
        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(ids[0], ids[1], "bars 0–1 share a pattern")
        XCTAssertEqual(ids[2], ids[3], "bars 2–3 share a pattern")
        XCTAssertEqual(ids[4], ids[5], "bars 4–5 share a pattern")
        XCTAssertNotEqual(ids[0], ids[2], "pattern must change at bar 2")
        XCTAssertNotEqual(ids[2], ids[4], "pattern must change at bar 4")
    }

    /// With bpmTolerance = 0, every rotated pattern must share the starting BPM (the 117-group
    /// has several members, so the pool is never empty).
    func testRotationRespectsBPMTolerance() throws {
        var config = EngineConfig()
        config.barsPerRotation = 1
        config.bpmTolerance = 0.0
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 9), config: config, startPatternIndex: 0)
        _ = engine.schedule(bars: 5)

        // (drum_patterns.json has non-unique ids, so we read bpms directly from the engine
        // rather than reconstructing them from ids.)
        let playedBpms = engine.playedPatternBpms
        XCTAssertEqual(playedBpms.count, 5)
        let first = playedBpms.first!
        XCTAssertTrue(playedBpms.allSatisfy { $0 == first },
                      "all rotated patterns should share the starting BPM (\(first)); got \(playedBpms)")
        XCTAssertEqual(first, 117)
    }

    func testRenderProducesNonSilentBuffer() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), startPatternIndex: 0)
        let buffer = try engine.render(bars: 4)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertTrue(containsAudio(buffer))
    }

    /// A BPM override fixes the tempo (steps spaced at the override's 16th-note grid), while
    /// patterns still rotate for content variety.
    func testBPMOverrideFixesTempo() throws {
        var config = EngineConfig()
        config.bpmOverride = 100
        config.humanize = false
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config, startPatternIndex: 0)
        let hits = engine.schedule(bars: 1)

        let stepDur = TimingModel.stepInterval(bpm: 100)
        let swing = TimingModel.swingOffset(swingAmount: 0.5, feelBase: TimingModel.feelBase(bpm: 100))

        // 2kfA1 kick hits steps 0 and 3; with override=100 these must use the 100-bpm grid, not 117.
        let firstKick = try XCTUnwrap(hits.first { $0.code == "k" })
        XCTAssertEqual(firstKick.time, 0.0, accuracy: 1e-9)
        let kick3 = try XCTUnwrap(hits.first { $0.code == "k" && $0.step == 3 })
        XCTAssertEqual(kick3.time, 3 * stepDur + swing, accuracy: 1e-9)
    }

    /// With a phrase directory configured, the engine locks tempo to the set's BPM and layers
    /// its loops under the drums.
    func testPhraseLayerLocksTempoAndRenders() throws {
        try XCTSkipUnless(PhraseBank.availableSetNames().contains("Bounce-loop"), "phrase sets not bundled")

        var config = EngineConfig()
        config.phraseDirectory = "Bounce-loop"
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config, startPatternIndex: 0)

        XCTAssertEqual(engine.config.bpmOverride, 128, "tempo should lock to the phrase set's BPM")
        XCTAssertNotNil(engine.phraseBank)

        let buffer = try engine.render(bars: 8)
        XCTAssertTrue(containsAudio(buffer))
        // 8 bars at 128 bpm ≈ 15s, so the buffer should be on the order of 15s.
        let secs = Double(buffer.frameLength) / buffer.format.sampleRate
        XCTAssertGreaterThan(secs, 14.0)
    }

    /// A custom drum kit (UFO) becomes the percussion source; core codes get served and the
    /// kit's served machine filters pattern expansion (drums come only from that kit directory).
    func testCustomKitServesCoreCodesAndRenders() throws {
        try XCTSkipUnless(DrumKit.availableKitNames().contains("UFO"), "drum kits not bundled")
        var config = EngineConfig()
        config.drumKitDirectory = "UFO"
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config, startPatternIndex: 0)

        XCTAssertTrue(engine.source is DrumKit)
        // UFO has Kick/Snare/Hat/Perc/808 — those core codes should be served.
        XCTAssertTrue(engine.source.loadedCodes.contains("k"), "kick code should be served by UFO")
        let buffer = try engine.render(bars: 4)
        XCTAssertTrue(containsAudio(buffer))
    }

    /// Phrase loops rotate across blocks (variety over time), recorded in playedLoopBlocks.
    func testPhraseLoopsRotateAcrossBlocks() throws {
        try XCTSkipUnless(PhraseBank.availableSetNames().contains("Bounce-loop"), "phrase sets not bundled")
        var config = EngineConfig()
        config.phraseDirectory = "Bounce-loop"
        config.phraseLoopCount = 1
        config.phraseRotationBars = 4
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 7), config: config, startPatternIndex: 0)

        _ = try engine.render(bars: 16)
        XCTAssertEqual(engine.playedLoopBlocks.count, 4, "16 bars / 4-bar blocks = 4 rotation blocks")
        let names = Set(engine.playedLoopBlocks.flatMap { $0 })
        XCTAssertGreaterThan(names.count, 1, "loops should rotate to more than one choice")
    }

    // MARK: helpers

    private func containsAudio(_ buf: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buf.frameLength)
        let channels = Int(buf.format.channelCount)
        for ch in 0..<channels {
            let p = buf.floatChannelData![ch]
            if (0..<frames).contains(where: { p[$0] != 0 }) { return true }
        }
        return false
    }
}
