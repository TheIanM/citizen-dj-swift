import Foundation

// MARK: - Drum machine / kit

/// One playable instrument within a drum kit, e.g. code `"k"` (kick) → its sample file.
public struct DrumInstrument: Equatable {
    public let code: String
    public let filename: String

    public init(code: String, filename: String) {
        self.code = code
        self.filename = filename
    }
}

/// A drum kit and its code→sample mapping. Built by `DrumKit` from a sample directory; used
/// to expand patterns (filtering to the codes a kit can play).
public struct DrumMachine: Equatable {
    public let id: String
    public let name: String
    public let instruments: [DrumInstrument]

    public init(id: String, name: String, instruments: [DrumInstrument]) {
        self.id = id
        self.name = name
        self.instruments = instruments
    }

    /// Sample file for an instrument code, or nil if this kit doesn't provide that code.
    public func filename(for code: String) -> String? {
        instruments.first { $0.code == code }?.filename
    }
}
