import XCTest
@testable import CitizenDJ

/// Tests for the pure timing math (16th-note grid, swing on odd steps, humanize bounds).
final class TimingModelTests: XCTestCase {

    func testStepIntervalAndFeelBase() {
        XCTAssertEqual(TimingModel.stepInterval(bpm: 120), 60.0 / 120.0 / 4.0, accuracy: 1e-12)
        XCTAssertEqual(TimingModel.barDuration(bpm: 120), 2.0, accuracy: 1e-12)  // 4 beats @ 120
        XCTAssertEqual(TimingModel.feelBase(bpm: 120), 60.0 / 120.0 / 16.0, accuracy: 1e-12)
    }

    func testSwingAppliedToOddStepsOnly() {
        let stepDur = TimingModel.stepInterval(bpm: 120)
        let swing = TimingModel.swingOffset(swingAmount: 0.5, feelBase: TimingModel.feelBase(bpm: 120))
        let tracks = ["x": SequencerTrack(code: "x", filename: "f",
            pattern: [true, true, true, true, false, false, false, false,
                      false, false, false, false, false, false, false, false])]
        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 120, swingAmount: 0.5, humanize: false, rng: &rng)
        let time = { (step: Int) in hits.first { $0.step == step }!.time }

        XCTAssertEqual(time(0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(time(1), stepDur + swing, accuracy: 1e-12)
        XCTAssertEqual(time(2), 2 * stepDur, accuracy: 1e-12)
        XCTAssertEqual(time(3), 3 * stepDur + swing, accuracy: 1e-12)
    }

    func testHumanizeStaysWithinFeelBound() {
        let stepDur = TimingModel.stepInterval(bpm: 100)
        let maxJitter = 0.1 * TimingModel.feelBase(bpm: 100)
        let tracks = ["x": SequencerTrack(code: "x", filename: "f", pattern: Array(repeating: true, count: 16))]
        var rng = SeededRNG(seed: 42)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 100, swingAmount: 0.0, humanize: true, rng: &rng)

        for hit in hits {
            let base = Double(hit.step) * stepDur
            XCTAssertGreaterThanOrEqual(hit.time, base, "hit before its base time at step \(hit.step)")
            XCTAssertLessThanOrEqual(hit.time, base + maxJitter, "humanize exceeded bound at step \(hit.step)")
        }
        XCTAssertEqual(hits.count, 16)
    }

    func testScheduleIsDeterministicForAGivenSeed() {
        let tracks = ["x": SequencerTrack(code: "x", filename: "f",
            pattern: [true, false, true, false, true, false, true, false,
                      true, false, true, false, true, false, true, false])]
        var rng1 = SeededRNG(seed: 7)
        var rng2 = SeededRNG(seed: 7)
        let a = TimingModel.schedule(tracks: tracks, bpm: 110, rng: &rng1)
        let b = TimingModel.schedule(tracks: tracks, bpm: 110, rng: &rng2)
        XCTAssertEqual(a, b, "same seed must yield the same schedule")
    }

    /// End-to-end timing check on a real pattern via a synthetic omnibus machine (no kit needed).
    func testKnownPattern2kfA1KickTimes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: url))
        let pattern = try XCTUnwrap(lib.patterns.first { $0.id == "2kfA1" })
        let codes = Array(Set(pattern.steps.flatMap { $0 }))
        let machine = DrumMachine(id: "m", name: "m",
                                  instruments: codes.map { DrumInstrument(code: $0, filename: "\($0).wav") })

        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: pattern.expanded(machine: machine), bpm: 117, humanize: false, rng: &rng)
        let kick = hits.filter { $0.code == "k" }.sorted(by: { $0.step < $1.step })

        let stepDur = TimingModel.stepInterval(bpm: 117)
        let swing = TimingModel.swingOffset(swingAmount: 0.5, feelBase: TimingModel.feelBase(bpm: 117))
        XCTAssertEqual(kick.map(\.step), [0, 3, 8, 11])
        let expected = [0.0, 3 * stepDur + swing, 8 * stepDur, 11 * stepDur + swing]
        for (hit, want) in zip(kick, expected) {
            XCTAssertEqual(hit.time, want, accuracy: 1e-9)
        }
    }
}

/// Minimal deterministic RNG (LCG) so humanized schedules are reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = (seed == 0) ? 1 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
