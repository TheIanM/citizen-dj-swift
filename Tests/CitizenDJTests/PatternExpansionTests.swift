import XCTest
@testable import CitizenDJ

/// Tests for `DrumPattern.expanded(machine:)` — the port of `drums.js loadTrackData`.
final class PatternExpansionTests: XCTestCase {
    private var t808: DrumMachine!

    override func setUpWithError() throws {
        t808 = try Self.load808()
    }

    func testExpandsKnownPattern2kfA1() throws {
        let patterns = try Self.loadPatterns()
        let p = try XCTUnwrap(patterns.patterns.first { $0.id == "2kfA1" })
        let tracks = p.expanded(machine: t808)

        // 2kfA1 references k, y, sa, sb, s — all present on the 808.
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

        // Every produced row is exactly 16 steps.
        XCTAssertTrue(tracks.values.allSatisfy { $0.pattern.count == 16 })
    }

    func testSkipsCodesTheMachineLacks() {
        // Machine with only a kick; pattern asks for kick plus an unknown code "zzz".
        let machine = DrumMachine(id: "test", name: "Test", instruments: [
            DrumInstrument(code: "k", filename: "kick.mp3")
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

    // MARK: helpers

    private static func load808() throws -> DrumMachine {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_machines", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(DrumLibrary.self, from: Data(contentsOf: url))
        return try XCTUnwrap(lib.machine(id: "t808"))
    }

    private static func loadPatterns() throws -> PatternLibrary {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data"))
        return try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: url))
    }
}
