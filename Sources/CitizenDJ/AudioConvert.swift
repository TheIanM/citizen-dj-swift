import AVFoundation

/// Small audio helpers shared across the engine.
enum AudioConvert {
    /// Resample `input` to `format` so a differently-rated source (e.g. a 44.1k loop into a 48k
    /// drum output, or a mixed-rate kit) mixes at the correct speed/pitch. Returns the input
    /// unchanged when sample rate and channel count already match.
    static func resample(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
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
