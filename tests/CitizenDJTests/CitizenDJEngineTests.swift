import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests for the conductor — pattern rotation that keeps the loop evolving.
final class CitizenDJEngineTests: XCTestCase {

    func testEngineLoadsAllData() throws {
        let engine = try CitizenDJEngine(rng: SeededRNG(seed: 1), startPatternIndex: 0)
        XCTAssertEqual(engine.patterns.count, 224)
        XCTAssertEqual(engine.bank.loadedCodes.count, 27)
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
