import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests for the offline renderer — the deterministic oracle for audio output.
final class OfflineRendererTests: XCTestCase {

    func testRendersNonSilentBufferOfCorrectLength() throws {
        let bank = try SampleBank(machine: try Self.load808())
        let tracks = try Self.loadPattern(id: "2kfA1").expanded(machine: try Self.load808())
        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 117, humanize: false, rng: &rng)

        let oneBar = TimingModel.barDuration(bpm: 117)
        let buf = try OfflineRenderer.render(hits: hits, bank: bank, durationSeconds: oneBar)

        XCTAssertEqual(Int(buf.frameLength), Int(ceil(oneBar * bank.commonFormat.sampleRate)))
        XCTAssertTrue(containsAudio(buf), "rendered buffer should be non-silent")
    }

    /// A single hit must land exactly at its scheduled frame: silence before, energy during.
    func testHitIsPlacedAtItsScheduledFrame() throws {
        let bank = try SampleBank(machine: try Self.load808())
        let sampleRate = bank.commonFormat.sampleRate
        let hitTime = 0.1
        let buf = try OfflineRenderer.render(hits: [DrumHit(code: "k", step: 0, time: hitTime)],
                                             bank: bank, durationSeconds: 1.0)

        let start = Int(hitTime * sampleRate)
        let kick = try XCTUnwrap(bank.buffer(for: "k"))
        let kickFrames = Int(kick.frameLength)
        let ch0 = buf.floatChannelData![0]

        let preMax = (0..<start).map { abs(ch0[$0]) }.max() ?? 0
        XCTAssertEqual(preMax, 0.0, "buffer must be silent before the scheduled hit")

        let hitWindow = start..<min(Int(buf.frameLength), start + kickFrames)
        let hitMax = hitWindow.map { abs(ch0[$0]) }.max() ?? 0
        XCTAssertGreaterThan(hitMax, 0.0, "kick must produce energy at its scheduled frame")
    }

    func testWriteWavProducesNonEmptyFile() throws {
        let bank = try SampleBank(machine: try Self.load808())
        let tracks = try Self.loadPattern(id: "2kfA1").expanded(machine: try Self.load808())
        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 117, humanize: false, rng: &rng)
        let buf = try OfflineRenderer.render(hits: hits, bank: bank, durationSeconds: 2.0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("citizendj_test_\(UUID().uuidString).wav")
        try OfflineRenderer.writeWav(buf, to: url)

        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 44, "WAV file should be larger than its 44-byte header")
        try? FileManager.default.removeItem(at: url)
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

    private static func load808() throws -> DrumMachine {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_machines", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(DrumLibrary.self, from: Data(contentsOf: url))
        return try XCTUnwrap(lib.machine(id: "t808"))
    }

    private static func loadPattern(id: String) throws -> DrumPattern {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: url))
        return try XCTUnwrap(lib.patterns.first { $0.id == id }, "pattern \(id) not found")
    }
}
