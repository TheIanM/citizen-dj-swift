import XCTest
@testable import CitizenDJ

/// Decoding tests for the drum-pattern manifest. (drum_machines.json / the 808 were removed.)
final class DecodingTests: XCTestCase {
    private func jsonURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "data"),
                      "\(name).json missing from bundle")
    }

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
