import Foundation

/// Entry-point namespace for the Citizen DJ native drum-loop generator.
///
/// This library is a Swift port of the JavaScript engine in the original Citizen DJ
/// web app (`js/lib/drums.js`, `sequencer.js`, `track.js`). It does not synthesize
/// sound — it selects a hand-authored 16-step pattern + a drum machine, and triggers
/// the bundled one-shot drum samples on a native `AVAudioEngine` step sequencer.
public enum CitizenDJ {
    /// Library version (semver-ish).
    public static let version = "0.1.0"
}
