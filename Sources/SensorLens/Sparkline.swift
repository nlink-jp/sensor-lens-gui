import Foundation

/// The arithmetic behind a sparkline, kept out of the view so it can be tested.
enum Sparkline {
    /// Which way the series went over its window.
    enum Trend {
        case rising, falling, steady

        var symbol: String {
            switch self {
            case .rising: return "arrow.up.right"
            case .falling: return "arrow.down.right"
            case .steady: return "arrow.right"
            }
        }

        var help: String {
            switch self {
            case .rising: return "Higher than six hours ago"
            case .falling: return "Lower than six hours ago"
            case .steady: return "About the same as six hours ago"
            }
        }
    }

    /// The y-range to draw in.
    ///
    /// Scaled to the data rather than anchored at zero: a room that moved
    /// between 26 and 28 degrees should *look* like it moved, not like a flat
    /// line pinned near the top of a 0–30 axis. The padding keeps a genuinely
    /// flat series as a line through the middle instead of one along an edge.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 0.5)
        return (lo - pad)...(hi + pad)
    }

    /// Direction from the first sample to the last.
    ///
    /// The threshold is a fraction of the *drawn* range, not a fixed epsilon.
    /// That means the arrow describes the shape the user is looking at: the
    /// sparkline is autoscaled, so a monotonic climb is drawn as a clearly
    /// rising line however small it is in absolute terms, and an arrow reading
    /// "steady" beside it would contradict the picture. It also means no
    /// per-metric table of "what counts as a change" to keep up to date.
    ///
    /// Sensor wobble still reads as steady, because `domain` floors its padding:
    /// a series jittering by 0.1 is drawn against a range of at least 1.
    ///
    /// Too few points is no answer rather than "steady" — claiming a six-hour
    /// direction from two samples would be making it up.
    static func trend(_ values: [Double], minimumSamples: Int = 3) -> Trend? {
        guard values.count >= minimumSamples,
              let first = values.first, let last = values.last else { return nil }

        let range = domain(values)
        let threshold = max((range.upperBound - range.lowerBound) * 0.1, 0.01)

        if last - first > threshold { return .rising }
        if first - last > threshold { return .falling }
        return .steady
    }
}
