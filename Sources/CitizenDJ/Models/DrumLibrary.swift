import Foundation

// MARK: - Drum machines

/// One playable instrument within a drum machine, e.g. code `"k"` (kick) → its sample file.
///
/// Decoded from the positional JSON array `[code, filename]` used in `drum_machines.json`
/// (mirrors the JS `_.object(itemHeadings, instrument)` zipping in `drums.js`).
public struct DrumInstrument: Decodable, Equatable {
    public let code: String
    public let filename: String

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        code = try container.decode(String.self)
        filename = try container.decode(String.self)
    }

    /// Direct constructor (synthetic machines / tests).
    public init(code: String, filename: String) {
        self.code = code
        self.filename = filename
    }
}

/// A drum machine (e.g. the Roland TR-808, id `"t808"`) and its code→sample mapping.
public struct DrumMachine: Decodable, Equatable {
    public let id: String
    public let name: String
    public let instruments: [DrumInstrument]

    public init(id: String, name: String, instruments: [DrumInstrument]) {
        self.id = id
        self.name = name
        self.instruments = instruments
    }

    /// Sample file for an instrument code, or nil if this machine doesn't provide that code.
    public func filename(for code: String) -> String? {
        instruments.first { $0.code == code }?.filename
    }
}

/// Top-level container of `drum_machines.json`. The file's `itemHeadings` field is ignored
/// because the instrument arrays are always `[code, filename]`.
public struct DrumLibrary: Decodable {
    public let drums: [DrumMachine]

    /// Find a machine by id (e.g. `"t808"`).
    public func machine(id: String) -> DrumMachine? {
        drums.first { $0.id == id }
    }
}
