import XCTest
import AVFoundation
@testable import CitizenDJ

/// Tests for the offline renderer — the deterministic oracle for audio output. Uses a bundled
/// kit as the sample source (skipped when no kits are present).
final class OfflineRendererTests: XCTestCase {

    private var kit: DrumKit!

    override func setUpWithError() throws {
        try XCTSkipUnless(!DrumKit.availableKitNames().isEmpty, "no drum kits bundled")
        var rng = SeededRNG(seed: 1)
        let name = DrumKit.availableKitNames().first ?? "UFO"
        kit = try DrumKit(directoryName: name,
                          codes: ["k", "s", "sa", "hc", "ho", "h", "y", "c", "r", "t", "tt", "ttt"],
                          rng: &rng)
    }

    private func loadPattern(id: String) throws -> DrumPattern {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "drum_patterns", withExtension: "json", subdirectory: "data"))
        let lib = try JSONDecoder().decode(PatternLibrary.self, from: Data(contentsOf: url))
        return try XCTUnwrap(lib.patterns.first { $0.id == id })
    }

    func testRendersNonSilentBufferOfCorrectLength() throws {
        let tracks = try loadPattern(id: "2kfA1").expanded(machine: kit.servedMachine)
        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 117, humanize: false, rng: &rng)
        let oneBar = TimingModel.barDuration(bpm: 117)
        let buf = try OfflineRenderer.render(hits: hits, source: kit, durationSeconds: oneBar)

        XCTAssertEqual(Int(buf.frameLength), Int(ceil(oneBar * kit.commonFormat.sampleRate)))
        XCTAssertTrue(containsAudio(buf), "rendered buffer should be non-silent")
    }

    func testHitIsPlacedAtItsScheduledFrame() throws {
        let sampleRate = kit.commonFormat.sampleRate
        let hitTime = 0.1
        let buf = try OfflineRenderer.render(hits: [DrumHit(code: "k", step: 0, time: hitTime)],
                                             source: kit, durationSeconds: 1.0)
        let start = Int(hitTime * sampleRate)
        let kick = try XCTUnwrap(kit.buffer(for: "k"))
        let kickFrames = Int(kick.frameLength)
        let ch0 = buf.floatChannelData![0]

        let preMax = (0..<start).map { abs(ch0[$0]) }.max() ?? 0
        XCTAssertEqual(preMax, 0.0, "buffer must be silent before the scheduled hit")
        let hitMax = (start..<min(Int(buf.frameLength), start + kickFrames)).map { abs(ch0[$0]) }.max() ?? 0
        XCTAssertGreaterThan(hitMax, 0.0, "kick must produce energy at its scheduled frame")
    }

    func testWriteWavProducesNonEmptyFile() throws {
        let tracks = try loadPattern(id: "2kfA1").expanded(machine: kit.servedMachine)
        var rng = SeededRNG(seed: 1)
        let hits = TimingModel.schedule(tracks: tracks, bpm: 117, humanize: false, rng: &rng)
        let buf = try OfflineRenderer.render(hits: hits, source: kit, durationSeconds: 2.0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("citizendj_test_\(UUID().uuidString).wav")
        try OfflineRenderer.writeWav(buf, to: url)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 44, "WAV file should be larger than its 44-byte header")
        try? FileManager.default.removeItem(at: url)
    }

    private func containsAudio(_ buf: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buf.frameLength)
        let channels = Int(buf.format.channelCount)
        for ch in 0..<channels {
            let p = buf.floatChannelData![ch]
            if (0..<frames).contains(where: { p[$0] != 0 }) { return true }
        }
        return false
    }
}
