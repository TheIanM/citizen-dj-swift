import Foundation

/// A small deterministic RNG (linear congruential generator). Not cryptographic — its job is
/// **reproducibility**: the same seed always produces the same generation sequence, so a
/// render (or a game level's BGM) can be replayed exactly. The demo prints its seed on every
/// run and accepts it back via `--seed`.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = (seed == 0) ? 1 : seed  // 0 would lock the LCG at a fixed point
    }

    public mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
