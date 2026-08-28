import AVFoundation

/// One decoded phrase loop from a phrase set.
public struct PhraseLoop: Equatable {
    public let name: String            // filename without extension
    public let buffer: AVAudioPCMBuffer
    public let bpm: Double?            // parsed from the filename (e.g. "128BPM"), if present
}

/// Loads every wav loop from ONE phrase directory (recursively), so a bank always represents
/// a single directory subtree — the "harmonic isolation" rule. Loops in a set share a tempo
/// (encoded in their filenames), so layering within a set stays in sync and in key.
public final class PhraseBank {

    public let directoryName: String
    public let loops: [PhraseLoop]
    /// The set's tempo, from the first loop whose filename declares one.
    public let bpm: Double?

    public init(directoryName: String, bundle: Bundle? = nil) throws {
        let bundle = bundle ?? Bundle.module
        self.directoryName = directoryName

        guard let setURL = Self.locateSet(directoryName, in: bundle) else {
            throw PhraseBankError.directoryNotFound(directoryName)
        }

        var loaded: [PhraseLoop] = []
        var setBpm: Double?
        for url in Self.collectWavFiles(in: setURL) {
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            do { try file.read(into: buffer) } catch { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            let bpm = Self.parseBpm(from: stem)
            loaded.append(PhraseLoop(name: stem, buffer: buffer, bpm: bpm))
            if setBpm == nil { setBpm = bpm }
        }
        guard !loaded.isEmpty else { throw PhraseBankError.noLoadsLoaded(directoryName) }

        self.loops = loaded
        self.bpm = setBpm
    }

    /// Top-level phrase-set directory names available in the bundle (e.g. ["Bounce-loop", …]).
    public static func availableSetNames(bundle: Bundle? = nil) -> [String] {
        let bundle = bundle ?? Bundle.module
        guard let phrasesURL = bundle.url(forResource: "phrases", withExtension: nil) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: phrasesURL.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0 != ".keep" }.sorted()
    }

    // MARK: - private

    private static func locateSet(_ name: String, in bundle: Bundle) -> URL? {
        guard let phrasesURL = bundle.url(forResource: "phrases", withExtension: nil) else { return nil }
        let direct = phrasesURL.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return direct
    }

    private static func collectWavFiles(in url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted(by: { $0.path < $1.path })
    }

    /// Parse "128BPM" / "128 BPM" → 128.
    private static func parseBpm(from stem: String) -> Double? {
        guard let range = stem.range(of: #"(\d+)\s*BPM"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Double(stem[range].filter { $0.isNumber })
    }
}

public enum PhraseBankError: Error {
    case directoryNotFound(String)
    case noLoadsLoaded(String)
}
