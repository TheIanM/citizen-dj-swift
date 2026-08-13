import AVFoundation

/// A custom drum kit loaded from ONE directory (e.g. "UFO"). Samples are classified into
/// instrument categories by filename / parent-directory keywords, then mapped to the pattern
/// instrument codes (k/s/hc…). One sample per served code is chosen at load (randomly), so a
/// kit behaves like a fixed voicing within a render. Honors harmonic isolation: a DrumKit
/// comes from exactly one directory subtree.
public final class DrumKit: SampleSource {

    public let directoryName: String
    public let commonFormat: AVAudioFormat
    /// A `DrumMachine` whose instrument list is the codes this kit serves — used so pattern
    /// expansion only keeps codes the kit can actually play.
    public let servedMachine: DrumMachine
    public let loadedCodes: [String]
    private let buffersByCode: [String: AVAudioPCMBuffer]

    public init(directoryName: String, codes: [String], bundle: Bundle? = nil,
                rng: inout some RandomNumberGenerator) throws {
        let bundle = bundle ?? Bundle.module
        self.directoryName = directoryName

        guard let kitURL = Self.locateKit(directoryName, in: bundle) else {
            throw DrumKitError.directoryNotFound(directoryName)
        }

        // Classify every wav into an instrument category.
        var byCategory: [String: [URL]] = [:]
        for url in Self.collectWavFiles(in: kitURL) {
            if let category = Self.classify(url: url) {
                byCategory[category, default: []].append(url)
            }
        }

        // For each requested code, pick a sample from its category (with fallbacks).
        var format: AVAudioFormat?
        var buffers: [String: AVAudioPCMBuffer] = [:]
        var instruments: [DrumInstrument] = []
        for code in codes {
            let candidates = Self.categories(forCode: code)
            guard let chosen = candidates.lazy.compactMap({ byCategory[$0] }).first?.randomElement(using: &rng) else {
                continue  // kit has no sample for this code → it's simply not served
            }
            guard let file = try? AVAudioFile(forReading: chosen) else { continue }
            let fileFormat = file.processingFormat
            guard let raw = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            do { try file.read(into: raw) } catch { continue }
            if format == nil { format = fileFormat }
            // Normalize to one format so the renderer can place hits without per-hit conversion.
            let buffer = AudioConvert.resample(raw, to: format!)
            buffers[code] = buffer
            instruments.append(DrumInstrument(code: code, filename: chosen.lastPathComponent))
        }

        guard let commonFormat = format, !buffers.isEmpty else {
            throw DrumKitError.noSamplesLoaded(directoryName)
        }
        self.commonFormat = commonFormat
        self.buffersByCode = buffers
        self.loadedCodes = Array(buffers.keys)
        self.servedMachine = DrumMachine(id: directoryName, name: directoryName, instruments: instruments)
    }

    public func buffer(for code: String) -> AVAudioPCMBuffer? { buffersByCode[code] }

    /// Top-level kit directory names available in the bundle.
    public static func availableKitNames(bundle: Bundle? = nil) -> [String] {
        let bundle = bundle ?? Bundle.module
        guard let kitsURL = bundle.url(forResource: "drumkits", withExtension: nil) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: kitsURL.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0 != ".keep" }.sorted()
    }

    // MARK: - private

    private static func locateKit(_ name: String, in bundle: Bundle) -> URL? {
        guard let kitsURL = bundle.url(forResource: "drumkits", withExtension: nil) else { return nil }
        let direct = kitsURL.appendingPathComponent(name)
        var isDir: ObjCBool = false
        return (FileManager.default.fileExists(atPath: direct.path, isDirectory: &isDir) && isDir.boolValue) ? direct : nil
    }

    private static func collectWavFiles(in url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted(by: { $0.path < $1.path })
    }

    /// Instrument category from the filename + parent-directory name (lowercased), first match wins.
    private static func classify(url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        let hay = stem + " " + parent
        let order: [(keyword: String, category: String)] = [
            ("kick", "kick"), ("808", "808"), ("snare", "snare"), ("clap", "clap"),
            ("hihat", "hat"), ("hat", "hat"), ("crash", "crash"), ("ride", "ride"),
            ("tom", "tom"), ("perc", "perc"), ("foley", "foley"), ("fx", "fx"),
            ("snap", "snap"), ("impact", "impact")
        ]
        for (keyword, category) in order where hay.contains(keyword) { return category }
        return nil
    }

    /// Ordered category candidates for a pattern code (primary first, then fallbacks).
    private static func categories(forCode code: String) -> [String] {
        switch code {
        case "k", "ka", "kg":           return ["kick", "808"]
        case "s", "sa", "sb", "sg":     return ["snare"]
        case "hc", "ho", "h", "ha", "hg": return ["hat"]
        case "c", "cg":                 return ["crash"]
        case "y", "ya", "yg", "yl":     return ["ride"]
        case "r", "ra", "rg":           return ["perc", "snare"]   // rim → perc/snare
        case "t", "ta", "tb", "tt", "ttt", "ttta": return ["tom", "perc"]  // toms
        default:                        return []
        }
    }
}

public enum DrumKitError: Error {
    case directoryNotFound(String)
    case noSamplesLoaded(String)
}
