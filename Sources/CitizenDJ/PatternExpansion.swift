import Foundation

extension DrumPattern {
    /// Expand this pattern's per-step instrument lists into per-instrument 16-step rows,
    /// resolving each code to its sample file via `machine`.
    ///
    /// Codes the machine doesn't provide are silently skipped — matching `drums.js`, where
    /// `instrumentToTrack` returns `false` for instruments the selected machine lacks.
    /// (Port of `Drums.prototype.loadTrackData`.)
    ///
    /// - Returns: tracks keyed by instrument code.
    public func expanded(machine: DrumMachine) -> [String: SequencerTrack] {
        var tracks: [String: SequencerTrack] = [:]
        for (step, codes) in steps.enumerated() {
            for code in codes {
                guard let file = machine.filename(for: code) else { continue }
                var track = tracks[code] ?? SequencerTrack(code: code, filename: file)
                track.pattern[step] = true
                tracks[code] = track
            }
        }
        return tracks
    }
}
