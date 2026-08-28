import XCTest
@testable import CitizenDJ

/// Tests for the custom drum-kit loader/classifier. Skipped when no kits are bundled.
final class DrumKitTests: XCTestCase {

    private func requireKits() throws {
        try XCTSkipUnless(!DrumKit.availableKitNames().isEmpty, "no drum kits bundled")
    }

    func testListsAvailableKits() throws {
        try requireKits()
        let kits = DrumKit.availableKitNames()
        XCTAssertTrue(kits.contains("UFO"))
    }

    /// UFO has Kick/Snare/Hat/Perc/808 subdirs → those core codes should be served.
    func testUFOServesCoreCodes() throws {
        try requireKits()
        var rng = SeededRNG(seed: 1)
        let kit = try DrumKit(directoryName: "UFO",
                              codes: ["k", "s", "sa", "hc", "ho", "c", "y", "t", "r"],
                              rng: &rng)
        XCTAssertTrue(kit.loadedCodes.contains("k"))
        XCTAssertTrue(kit.loadedCodes.contains("s"))
        XCTAssertTrue(kit.loadedCodes.contains("hc"))
        XCTAssertNil(kit.buffer(for: "zzz"))
        // served machine only reports codes that resolved to a sample.
        XCTAssertFalse(kit.servedMachine.instruments.isEmpty)
    }

    /// Kits are dir-isolated: a nonexistent kit throws.
    func testMissingKitThrows() throws {
        try requireKits()
        var rng = SeededRNG(seed: 1)
        XCTAssertThrowsError(try DrumKit(directoryName: "DoesNotExist", codes: ["k"], rng: &rng))
    }
}
