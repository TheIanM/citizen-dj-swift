import Foundation

/// A scheduled drum hit: the instrument code, the step (0–15) it falls on, and the absolute
/// trigger time in seconds from the start of the bar (swing + humanize already applied).
public struct DrumHit: Equatable {
    public let code: String
    public let step: Int
    public let time: Double
}

/// Pure timing math ported from the original JS engine (`sequencer.js` + `track.js`).
///
/// Two distinct quantities (which the JS keeps separate):
/// - the **step grid** — steps are true 16th notes (Tone.js's `"16n"` at `bpm`), so a step
///   every `60/bpm/4` seconds and a bar every `240/bpm`;
/// - the **feel magnitude** — the JS's `secondsPerSubd = 60/bpm/16`, used only to scale swing
///   and humanize. That makes the original's feel gentler than a literal fraction of a 16th;
///   we preserve it for fidelity (and it's adjustable).
///
/// Deterministic given a seeded RNG, so the offline renderer, the real-time scheduler, and
/// the tests all agree on "which sample fires when." Free of any AVFoundation types, which is
/// what makes the timing verifiable without an audio device.
public enum TimingModel {

    /// Seconds per 16th-note step — the grid steps are placed on (4 sixteenths per beat).
    public static func stepInterval(bpm: Double) -> Double {
        60.0 / bpm / 4.0
    }

    /// Seconds per bar (16 steps) at `bpm`.
    public static func barDuration(bpm: Double) -> Double {
        16.0 * stepInterval(bpm: bpm)
    }

    /// Magnitude base for swing & humanize, matching the original app's `secondsPerSubd`
    /// (`60/bpm/16`). See the type docs for why this differs from `stepInterval`.
    public static func feelBase(bpm: Double) -> Double {
        60.0 / bpm / 16.0
    }

    /// Swing offset (seconds) for `swingAmount` ∈ [-0.5, 0.5]. Port: `swing = feelBase * swingAmount`.
    public static func swingOffset(swingAmount: Double, feelBase: Double) -> Double {
        feelBase * swingAmount
    }

    /// Build the per-bar hit schedule for `tracks`.
    ///
    /// Steps are spaced on the true 16th-note grid; swing is added to odd steps only (matching
    /// `onStep`'s `if (col % 2 < 1) swing = 0`); humanize adds a per-hit
    /// `0 ... 0.1 * feelBase` jitter (matching `track.js play`). Tracks are iterated sorted by
    /// code, so RNG consumption — and therefore the schedule — is deterministic for a given seed.
    public static func schedule(
        tracks: [String: SequencerTrack],
        bpm: Double,
        swingAmount: Double = 0.5,
        humanize: Bool = true,
        rng: inout some RandomNumberGenerator
    ) -> [DrumHit] {
        let stepDur = stepInterval(bpm: bpm)
        let feel = feelBase(bpm: bpm)
        let swing = swingOffset(swingAmount: swingAmount, feelBase: feel)
        let humanizeAmount = 0.1 * feel

        var hits: [DrumHit] = []
        for track in tracks.values.sorted(by: { $0.code < $1.code }) {
            for stepIndex in 0..<track.pattern.count where track.pattern[stepIndex] {
                var time = Double(stepIndex) * stepDur
                if stepIndex % 2 == 1 { time += swing }
                if humanize { time += Double.random(in: 0...humanizeAmount, using: &rng) }
                hits.append(DrumHit(code: track.code, step: stepIndex, time: time))
            }
        }
        return hits
    }
}
