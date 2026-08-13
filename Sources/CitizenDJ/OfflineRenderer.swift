import AVFoundation

/// Renders drum hits (and optionally layered phrase loops) to an audio buffer.
///
/// Drum one-shots are mixed at their scheduled times; phrase loops are tiled end-to-end
/// (they're bar-aligned at the set's BPM). Deterministic and device-free, this is both the
/// engine's test oracle and the demo's bounce-to-file — the Swift analogue of the JS app's
/// `Tone.Offline` / `Sequencer.downloadCurrentPattern`.
public enum OfflineRenderer {

    /// Mix `hits` from `bank`, optionally layering `loopBuffers` (each tiled every loop length),
    /// into a single buffer using `bank`'s format.
    ///
    /// - Parameter durationSeconds: output length; if nil, derived from the last hit + the
    ///   longest drum sample's tail so nothing clips.
    public static func render(
        hits: [DrumHit],
        bank: SampleBank,
        loopBuffers: [AVAudioPCMBuffer] = [],
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
        for ch in 0..<channelCount {
            memset(out.floatChannelData![ch], 0, MemoryLayout<Float32>.size * totalFrames)
        }

        // Drum one-shots.
        for hit in hits {
            if let src = bank.buffer(for: hit.code) {
                place(src, atSeconds: hit.time, into: out, sampleRate: sampleRate, totalFrames: totalFrames)
            }
        }

        // Layered phrase loops, tiled end-to-end.
        for loop in loopBuffers {
            let conv = converted(loop, to: format)   // resample e.g. 44.1k loop → 48k output
            let period = Double(conv.frameLength) / sampleRate
            guard period > 0 else { continue }
            var t = 0.0
            while t < totalSeconds {
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

    /// Resample `input` to `format` so a differently-rated source (e.g. a 44.1k loop into a
    /// 48k drum output) mixes at the correct speed/pitch. Returns the input unchanged when the
    /// sample rate and channel count already match.
    private static func converted(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
        if input.format.sampleRate == format.sampleRate && input.format.channelCount == format.channelCount {
            return input
        }
        guard let converter = AVAudioConverter(from: input.format, to: format) else { return input }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return input }

        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        converter.convert(to: out, error: nil, withInputFrom: inputBlock)
        return out
    }
}

public enum OfflineRendererError: Error {
    case bufferAllocationFailed
}
