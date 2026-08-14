import XCTest
@testable import CitizenDJ

/// Smoke tests that confirm the package wires together (toolchain, module, bundled manifest).
final class CitizenDJTests: XCTestCase {

    func testModuleLoads() {
        XCTAssertEqual(CitizenDJ.version, "0.1.0")
    }

    /// The pattern manifest is the one data resource the engine always needs.
    func testPatternManifestIsBundled() throws {
        let url = Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data")
        XCTAssertNotNil(url, "drum_patterns.json must be bundled")
    }
}
