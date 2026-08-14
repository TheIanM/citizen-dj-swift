import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests for the conductor. The engine requires a kit, so these all skip when no kit is bundled.
final class CitizenDJEngineTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(DrumKit.availableKitNames().contains("UFO"), "UFO kit not bundled")
    }

    private func config(kit: String = "UFO") -> EngineConfig {
        var c = EngineConfig()
        c.drumKitDirectory = kit
        return c
    }

    func testEngineLoadsAllData() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config(), startPatternIndex: 0)
        XCTAssertEqual(engine.patterns.count, 224)
        XCTAssertFalse(engine.patternKey.isEmpty)
        XCTAssertTrue(engine.source.loadedCodes.contains("k"), "UFO should serve kick")
    }

    func testScheduleCoversRequestedBarCount() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config(), startPatternIndex: 0)
        let hits = engine.schedule(bars: 4)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(engine.playedPatternIds.count, 4)
        XCTAssertGreaterThan(hits.map(\.time).max() ?? 0, 5.0)
    }

    func testRotationChangesPatternEveryNBars() throws {
        var c = config(); c.barsPerRotation = 2
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 3), config: c, startPatternIndex: 0)
        _ = engine.schedule(bars: 6)
        let ids = engine.playedPatternIds
        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(ids[0], ids[1]); XCTAssertEqual(ids[2], ids[3]); XCTAssertEqual(ids[4], ids[5])
        XCTAssertNotEqual(ids[0], ids[2]); XCTAssertNotEqual(ids[2], ids[4])
    }

    func testRotationRespectsBPMTolerance() throws {
        var c = config(); c.barsPerRotation = 1; c.bpmTolerance = 0.0
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 9), config: c, startPatternIndex: 0)
        _ = engine.schedule(bars: 5)
        let bpms = engine.playedPatternBpms
        let first = bpms.first!
        XCTAssertTrue(bpms.allSatisfy { $0 == first }, "rotation should stay within tolerance: \(bpms)")
        XCTAssertEqual(first, 117)
    }

    func testRenderProducesNonSilentBuffer() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: config(), startPatternIndex: 0)
        let buffer = try engine.render(bars: 4)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertTrue(containsAudio(buffer))
    }

    func testBPMOverrideFixesTempo() throws {
        var c = config(); c.bpmOverride = 100; c.humanize = false
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: c, startPatternIndex: 0)
        let hits = engine.schedule(bars: 1)
        let stepDur = TimingModel.stepInterval(bpm: 100)
        let swing = TimingModel.swingOffset(swingAmount: 0.5, feelBase: TimingModel.feelBase(bpm: 100))
        let firstKick = try XCTUnwrap(hits.first { $0.code == "k" })
        XCTAssertEqual(firstKick.time, 0.0, accuracy: 1e-9)
        let kick3 = try XCTUnwrap(hits.first { $0.code == "k" && $0.step == 3 })
        XCTAssertEqual(kick3.time, 3 * stepDur + swing, accuracy: 1e-9)
    }

    func testPhraseLayerLocksTempoAndRenders() throws {
        try XCTSkipUnless(PhraseBank.availableSetNames().contains("Bounce-loop"), "Bounce-loop not bundled")
        var c = config(); c.phraseDirectory = "Bounce-loop"
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), config: c, startPatternIndex: 0)
        XCTAssertEqual(engine.config.bpmOverride, 128, "tempo should lock to the phrase set's BPM")
        XCTAssertNotNil(engine.phraseBank)
        let buffer = try engine.render(bars: 8)
        XCTAssertTrue(containsAudio(buffer))
        XCTAssertGreaterThan(Double(buffer.frameLength) / buffer.format.sampleRate, 14.0)
    }

    func testNoKitConfiguredThrows() throws {
        XCTAssertThrowsError(try CitizenDJEngine(rng: SeededRNG(seed: 1), config: EngineConfig())) { error in
            guard case CitizenDJEngineError.noDrumKitConfigured = error else {
                XCTFail("expected noDrumKitConfigured, got \(error)")
                return
            }
        }
    }

    func testPhraseLoopsRotateAcrossBlocks() throws {
        try XCTSkipUnless(PhraseBank.availableSetNames().contains("Bounce-loop"), "Bounce-loop not bundled")
        var c = config(); c.phraseDirectory = "Bounce-loop"; c.phraseLoopCount = 1; c.phraseRotationBars = 4
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 7), config: c, startPatternIndex: 0)
        _ = try engine.render(bars: 16)
        XCTAssertEqual(engine.playedLoopBlocks.count, 4, "16 bars / 4-bar blocks = 4 rotation blocks")
        XCTAssertGreaterThan(Set(engine.playedLoopBlocks.flatMap { $0 }).count, 1, "loops should rotate")
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
