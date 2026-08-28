import AVFoundation

/// A phrase loop placed in a render: its buffer tiled within
/// `[startSeconds, startSeconds + durationSeconds)`. Letting the engine emit multiple
/// placements (one per rotated block) is what gives the phrase layer variety over time.
public struct LoopPlacement {
    public let buffer: AVAudioPCMBuffer
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(buffer: AVAudioPCMBuffer, startSeconds: Double, durationSeconds: Double) {
        self.buffer = buffer
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

/// Renders drum hits (and optionally layered phrase loops) to an audio buffer.
///
/// Drum one-shots are mixed at their scheduled times; phrase loops are tiled within their
/// placement windows. Deterministic and device-free — both the engine's test oracle and the
/// demo's bounce-to-file (the Swift analogue of the JS app's `Tone.Offline`).
public enum OfflineRenderer {

    public static func render(
        hits: [DrumHit],
        source: SampleSource,
        loops: [LoopPlacement] = [],
        durationSeconds: Double? = nil
    ) throws -> AVAudioPCMBuffer {
        let format = source.commonFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        let longestTailFrames = source.loadedCodes.compactMap { source.buffer(for: $0)?.frameLength }.max() ?? 0
        let lastHitEnd = hits.map { $0.time }.max() ?? 0
        let lastLoopEnd = loops.map { $0.startSeconds + $0.durationSeconds }.max() ?? 0
        let totalSeconds = durationSeconds ?? (max(lastHitEnd, lastLoopEnd) + Double(longestTailFrames) / sampleRate)
        let totalFrames = max(1, Int(ceil(totalSeconds * sampleRate)))

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            throw OfflineRendererError.bufferAllocationFailed
        }
        out.frameLength = AVAudioFrameCount(totalFrames)
        for ch in 0..<channelCount {
            memset(out.floatChannelData![ch], 0, MemoryLayout<Float32>.size * totalFrames)
        }

        // Drum one-shots.
        for hit in hits {
            if let src = source.buffer(for: hit.code) {
                place(src, atSeconds: hit.time, into: out, sampleRate: sampleRate, totalFrames: totalFrames)
            }
        }
        // Layered phrase loops, tiled within each placement's window.
        for placement in loops {
            let conv = AudioConvert.resample(placement.buffer, to: format)
            let period = Double(conv.frameLength) / sampleRate
            guard period > 0 else { continue }
            var t = placement.startSeconds
            let end = placement.startSeconds + placement.durationSeconds
            while t < end {
                place(conv, atSeconds: t, into: out, sampleRate: sampleRate, totalFrames: totalFrames)
                t += period
            }
        }
        return out
    }

    /// Write `buffer` to a 16-bit PCM WAV file at `url`.
    public static func writeWav(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    // MARK: - private

    /// Additively mix `src` into `out` starting at `atSeconds` (clamped to bounds). A mono
    /// source is copied into every output channel.
    private static func place(
        _ src: AVAudioPCMBuffer, atSeconds: Double,
        into out: AVAudioPCMBuffer, sampleRate: Double, totalFrames: Int
    ) {
        let srcChannels = Int(src.format.channelCount)
        let srcFrames = Int(src.frameLength)
        let startFrame = Int(atSeconds * sampleRate)
        let first = max(0, startFrame)
        let lastExclusive = min(totalFrames, startFrame + srcFrames)
        guard first < lastExclusive else { return }
        for ch in 0..<Int(out.format.channelCount) {
            let srcCh = min(ch, srcChannels - 1)
            let sp = src.floatChannelData![srcCh]
            let dp = out.floatChannelData![ch]
            for f in first..<lastExclusive {
                dp[f] += sp[f - startFrame]
            }
        }
    }
}

public enum OfflineRendererError: Error {
    case bufferAllocationFailed
}
