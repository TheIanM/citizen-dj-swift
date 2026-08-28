import AVFoundation

/// A percussion sample source keyed by instrument code — what the renderer and engine use to
/// trigger hits. Agnostic to whether samples come from the bundled 808 (`SampleBank`) or a
/// custom kit directory (`DrumKit`).
public protocol SampleSource {
    var commonFormat: AVAudioFormat { get }
    var loadedCodes: [String] { get }
    func buffer(for code: String) -> AVAudioPCMBuffer?
}
