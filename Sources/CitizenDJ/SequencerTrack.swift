import Foundation

/// One expanded sequencer row: an instrument code, the sample file (for the active drum
/// machine) to trigger, and a 16-step on/off pattern.
///
/// Produced by `DrumPattern.expanded(machine:)`. `pattern[i] == true` means the sample
/// fires on step `i` (0–15).
public struct SequencerTrack: Equatable {
    public let code: String
    public let filename: String
    public var pattern: [Bool]

    public init(code: String, filename: String, pattern: [Bool] = Array(repeating: false, count: 16)) {
        self.code = code
        self.filename = filename
        self.pattern = pattern
    }
}
