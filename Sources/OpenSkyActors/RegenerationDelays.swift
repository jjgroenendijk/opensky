// Who fights and who casts during a regeneration step, and the pause each value
// keeps after it was damaged. See docs/engine/actor-value-store.md, "Regeneration".

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// What one holder is doing while it regenerates.
nonisolated public struct RegenerationSituation: Equatable, Sendable {
    public var isInCombat: Bool
    public var isCasting: Bool

    public static let calm = Self(isInCombat: false, isCasting: false)

    public init(isInCombat: Bool, isCasting: Bool) {
        self.isInCombat = isInCombat
        self.isCasting = isCasting
    }
}

/// Seconds left before each damaged value regenerates again. Not saved: a load
/// starts every value regenerating at once.
@MainActor
final class RegenerationDelays {
    private var remaining: [ReferenceKey: ActorValues] = [:]

    func pause(_ kind: ActorValueKind, of key: ReferenceKey, for seconds: Float) {
        guard seconds.isFinite, seconds > 0 else { return }
        var values = remaining[key] ?? .zero
        values[kind] = max(values[kind], seconds)
        remaining[key] = values
    }

    func isPaused(_ kind: ActorValueKind, of key: ReferenceKey) -> Bool {
        (remaining[key]?[kind] ?? 0) > 0
    }

    func advance(_ key: ReferenceKey, by seconds: Float) {
        guard var values = remaining[key] else { return }
        // A small slack, so thirty 1/60 s steps end a 0.5 s pause despite rounding.
        for kind in ActorValueKind.allCases {
            let left = values[kind] - seconds
            values[kind] = left > 1e-4 ? left : 0
        }
        remaining[key] = values == .zero ? nil : values
    }
}
