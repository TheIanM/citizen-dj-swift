import AVFoundation

/// Renders drum hits to an audio buffer by additively mixing the sample bank's one-shots at
/// their scheduled times.
///
/// Deterministic and device-free, this is both the engine's test oracle and a standalone
/// "bounce a loop to a file" feature — the Swift analogue of the JS app's `Tone.Offline` /
/// `Sequencer.downloadCurrentPattern`.
public enum OfflineRenderer {

    /// Mix `hits` (absolute times, in seconds) into a single buffer using `bank`'s format.
    ///
    /// - Parameter durationSeconds: output length; if nil, it's derived from the latest hit
    ///   plus the longest sample's tail so nothing gets clipped.
    public static func render(
        hits: [DrumHit],
        bank: SampleBank,
        durationSeconds: Double? = nil
    ) throws -> AVAudioPCMBuffer {
        let format = bank.commonFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        let longestTailFrames = bank.loadedCodes.compactMap { bank.buffer(for: $0)?.frameLength }.max() ?? 0
        let lastHitEnd = hits.map { $0.time }.max() ?? 0
        let totalSeconds = durationSeconds ?? (lastHitEnd + Double(longestTailFrames) / sampleRate)
        let totalFrames = max(1, Int(ceil(totalSeconds * sampleRate)))

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            throw OfflineRendererError.bufferAllocationFailed
        }
        out.frameLength = AVAudioFrameCount(totalFrames)

        // Start from silence.
        for ch in 0..<channelCount {
            memset(out.floatChannelData![ch], 0, MemoryLayout<Float32>.size * totalFrames)
        }

        // Add each hit's one-shot at its scheduled frame.
        for hit in hits {
            guard let src = bank.buffer(for: hit.code) else { continue }
            let srcChannels = Int(src.format.channelCount)
            let srcFrames = Int(src.frameLength)
            let start = Int(hit.time * sampleRate)
            let first = max(0, start)
            let lastExclusive = min(totalFrames, start + srcFrames)
            for ch in 0..<channelCount {
                // mono one-shot is copied into every output channel
                let srcCh = min(ch, srcChannels - 1)
                let srcPtr = src.floatChannelData![srcCh]
                let dstPtr = out.floatChannelData![ch]
                for f in first..<lastExclusive {
                    dstPtr[f] += srcPtr[f - start]
                }
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
}

public enum OfflineRendererError: Error {
    case bufferAllocationFailed
}
