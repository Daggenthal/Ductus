/// Exponentially weighted moving average with startup bias correction.
///
/// A plain EWMA seeded at zero (or at the first sample) is skewed for the
/// first few samples. Dividing by the accumulated weight fixes that, so the
/// value is meaningful from the first sample and recent samples matter most.
public struct EWMA: Sendable, Equatable, Codable {
    /// Weight of each new sample, in (0, 1]. Higher reacts faster.
    public let alpha: Double
    public private(set) var count = 0
    private var raw = 0.0
    private var weight = 0.0

    public init(alpha: Double) {
        precondition(alpha > 0 && alpha <= 1, "EWMA alpha must be in (0, 1]")
        self.alpha = alpha
    }

    /// Current average, or `nil` if no samples yet.
    public var value: Double? { count == 0 ? nil : raw / weight }

    public mutating func add(_ sample: Double) {
        raw = (1 - alpha) * raw + alpha * sample
        weight = (1 - alpha) * weight + alpha
        count += 1
    }
}
