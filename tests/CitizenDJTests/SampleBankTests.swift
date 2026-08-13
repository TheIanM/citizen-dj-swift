import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests that the TR-808 samples decode into in-memory buffers the engine can trigger.
final class SampleBankTests: XCTestCase {

    func testLoadsAll808Samples() throws {
        let bank = try SampleBank(machine: try Self.load808())

        XCTAssertEqual(bank.loadedCodes.count, 27, "all 27 TR-808 instruments should load")
        for code in ["k", "s", "sa", "hc", "ho", "y", "c", "r"] {
            XCTAssertNotNil(bank.buffer(for: code), "missing buffer for code \(code)")
        }
        // A buffer should actually contain audio.
        let kick = try XCTUnwrap(bank.buffer(for: "k"))
        XCTAssertGreaterThan(kick.frameLength, 0)
    }

    func testAll808BuffersShareCommonFormat() throws {
        let bank = try SampleBank(machine: try Self.load808())

        let kick = try XCTUnwrap(bank.buffer(for: "k"))
        let ride = try XCTUnwrap(bank.buffer(for: "y"))
        XCTAssertEqual(kick.format.sampleRate, ride.format.sampleRate)
        XCTAssertEqual(kick.format.channelCount, ride.format.channelCount)
        XCTAssertEqual(kick.format.sampleRate, bank.commonFormat.sampleRate)
        XCTAssertEqual(kick.format.channelCount, bank.commonFormat.channelCount)
    }

    /// Every instrument code that pattern 2kfA1 uses must resolve to a loaded buffer — the
    /// sequencer will assume this holds for whatever pattern it's handed.
    func testEveryCodeUsedByPattern2kfA1HasABuffer() throws {
        let bank = try SampleBank(machine: try Self.load808())
        let patterns = try Self.loadPatterns()
        let pattern = try XCTUnwrap(patterns.patterns.first { $0.id == "2kfA1" })

        let codes = Set(pattern.steps.flatMap { $0 })
        for code in codes {
            XCTAssertNotNil(bank.buffer(for: code),
                            "pattern 2kfA1 uses '\(code)' but the 808 bank has no buffer")
        }
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
