import XCTest
@testable import CitizenDJ

/// Decoding tests for the two drum-data JSON manifests. Uses the resources bundled into
/// the package (`Bundle.module`) — the same files the engine will decode at runtime.
final class DecodingTests: XCTestCase {
    private var bundle: Bundle { Bundle.module }

    private func jsonURL(_ name: String) throws -> URL {
        try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "data"),
                      "\(name).json missing from bundle")
    }

    // MARK: drum_machines.json

    func testDecodesAllMachinesAnd808Mapping() throws {
        let lib = try JSONDecoder().decode(DrumLibrary.self, from: Data(contentsOf: jsonURL("drum_machines")))

        XCTAssertEqual(lib.drums.count, 8)

        let t808 = try XCTUnwrap(lib.machine(id: "t808"), "t808 machine missing")
        XCTAssertEqual(t808.name, "Roland TR-808")
        XCTAssertEqual(t808.instruments.count, 27)
        // Spot-check known code → file mappings for the 808.
        XCTAssertEqual(try XCTUnwrap(t808.filename(for: "k")), "Roland_Tr-808_full__36kick.mp3")
        XCTAssertEqual(try XCTUnwrap(t808.filename(for: "sa")), "Roland_Tr-808_full__40snare_sa.mp3")
        XCTAssertEqual(try XCTUnwrap(t808.filename(for: "hc")), "Roland_Tr-808_full__42hat_closed.mp3")
    }

    // MARK: drum_patterns.json

    func testDecodesAllPatternsAndKey() throws {
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: jsonURL("drum_patterns")))

        XCTAssertEqual(lib.patterns.count, 224)
        XCTAssertEqual(lib.patternKey.count, 27)
        XCTAssertEqual(lib.patternKey["k"], "kick")

        let first = lib.patterns[0]
        XCTAssertEqual(first.id, "2kfA1")
        XCTAssertEqual(first.name, "2000s funk pattern A [1]")
        XCTAssertEqual(first.bpm, 117)
        XCTAssertEqual(first.steps[0], ["k", "y"])
    }

    func testEveryPatternHas16Steps() throws {
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: jsonURL("drum_patterns")))
        let bad = lib.patterns.filter { $0.steps.count != 16 }
        XCTAssertTrue(bad.isEmpty, "patterns without exactly 16 steps: \(bad.map(\.id))")
    }
}
