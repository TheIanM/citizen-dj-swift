import Foundation

// MARK: - Drum patterns

/// A single 16-step drum pattern. `steps[i]` is the list of instrument codes triggered on
/// step `i` (0–15); an empty list means that step is silent.
///
/// Decoded from the positional JSON array `[id, name, bpm, steps]` used in
/// `drum_patterns.json` (mirrors `_.object(itemHeadings, pattern)` in `drums.js`).
public struct DrumPattern: Decodable, Equatable {
    public let id: String
    public let name: String
    public let bpm: Int
    public let steps: [[String]]

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        name = try container.decode(String.self)
        bpm = try container.decode(Int.self)
        steps = try container.decode([[String]].self)
    }

    /// Direct constructor (synthetic patterns / tests).
    public init(id: String, name: String, bpm: Int, steps: [[String]]) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.steps = steps
    }
}

/// Top-level container of `drum_patterns.json`: the pattern list plus `patternKey`, which
/// maps short instrument codes to human-readable names (e.g. `"k"` → `"kick"`).
public struct PatternLibrary: Decodable {
    public let patterns: [DrumPattern]
    public let patternKey: [String: String]
}
