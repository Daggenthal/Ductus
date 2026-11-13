/// Small, fast, seedable generator (SplitMix64). Used so tests and the demo
/// are repeatable. The app can use `SystemRandomNumberGenerator` instead.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Sequence {
    /// Picks an element with probability proportional to `weight`.
    /// Negative weights count as zero. If every weight is zero, picks uniformly.
    func weightedRandomElement<G: RandomNumberGenerator>(
        using rng: inout G,
        weight: (Element) -> Double
    ) -> Element? {
        let items = map { ($0, Swift.max(0, weight($0))) }
        let total = items.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return items.randomElement(using: &rng)?.0 }

        var remaining = Double.random(in: 0..<total, using: &rng)
        var lastPositive: Element?
        for (element, w) in items where w > 0 {
            if remaining < w { return element }
            remaining -= w
            lastPositive = element
        }
        return lastPositive  // floating point leftovers
    }
}
