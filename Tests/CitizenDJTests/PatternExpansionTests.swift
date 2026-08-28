import XCTest
@testable import CitizenDJ

/// Tests for `DrumPattern.expanded(machine:)` — the port of `drums.js loadTrackData`.
/// Uses a synthetic "omnibus" machine (no audio needed) so these logic tests don't depend on
/// any bundled kit.
final class PatternExpansionTests: XCTestCase {

    private func loadPattern(id: String) throws -> DrumPattern {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: url))
        return try XCTUnwrap(lib.patterns.first { $0.id == id }, "pattern \(id) not found")
    }

    /// A machine that serves every code → a dummy file, so expansion keeps all of a pattern's codes.
    private func omnibusMachine(for pattern: DrumPattern) -> DrumMachine {
        let codes = Array(Set(pattern.steps.flatMap { $0 }))
        return DrumMachine(id: "omnibus", name: "omnibus",
                           instruments: codes.map { DrumInstrument(code: $0, filename: "\($0).wav") })
    }

    func testExpandsKnownPattern2kfA1() throws {
        let pattern = try loadPattern(id: "2kfA1")
        let tracks = pattern.expanded(machine: omnibusMachine(for: pattern))

        XCTAssertNotNil(tracks["k"])
        XCTAssertNotNil(tracks["y"])
        XCTAssertNotNil(tracks["sa"])
        // Kick hits on steps 0, 3, 8, 11.
        XCTAssertEqual(tracks["k"]?.pattern,
                       [true, false, false, true,  false, false, false, false,
                        true, false, false, true,  false, false, false, false])
        // Ride hits on steps 0, 6, 8, 14.
        XCTAssertEqual(tracks["y"]?.pattern,
                       [true, false, false, false, false, false, true, false,
                        true, false, false, false, false, false, true, false])
        XCTAssertTrue(tracks.values.allSatisfy { $0.pattern.count == 16 })
    }

    func testSkipsCodesTheMachineLacks() {
        let machine = DrumMachine(id: "test", name: "Test", instruments: [
            DrumInstrument(code: "k", filename: "kick.wav")
        ])
        let pattern = DrumPattern(
            id: "t", name: "t", bpm: 100,
            steps: [["k", "zzz"], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []])
        let tracks = pattern.expanded(machine: machine)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertNotNil(tracks["k"])
        XCTAssertNil(tracks["zzz"], "codes the machine lacks must be skipped")
        XCTAssertEqual(tracks["k"]?.pattern[0], true)
    }
}
