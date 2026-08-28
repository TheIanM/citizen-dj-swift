import XCTest
@testable import CitizenDJ

/// Tests for the phrase set loader. Skipped automatically when no phrase sets are bundled.
final class PhraseBankTests: XCTestCase {

    private func requirePhrases() throws {
        try XCTSkipUnless(!PhraseBank.availableSetNames().isEmpty, "no phrase sets bundled")
    }

    func testListsAvailableSets() throws {
        try requirePhrases()
        let sets = PhraseBank.availableSetNames()
        XCTAssertTrue(sets.contains("Bounce-loop"))
        XCTAssertTrue(sets.contains("SH_SFB2_KIT08_MELODY_LOOPS"))
    }

    func testLoadsBounceLoopSet() throws {
        try requirePhrases()
        let bank = try PhraseBank(directoryName: "Bounce-loop")
        XCTAssertGreaterThan(bank.loops.count, 5)
        XCTAssertEqual(bank.bpm, 128)
        XCTAssertTrue(bank.loops.allSatisfy { $0.buffer.frameLength > 0 })
    }

    func testParsesBpmForSHSet() throws {
        try requirePhrases()
        let bank = try PhraseBank(directoryName: "SH_SFB2_KIT08_MELODY_LOOPS")
        XCTAssertEqual(bank.bpm, 126)
    }
}
