// The three primary actor values and the triple that carries them. One type,
// because every operation touches all three: derivation, clamping, save, and
// HUD. Other actor values live elsewhere. See docs/engine/actor-values.md.

import Foundation

/// One of the three primary actor values.
///
/// Ordered health, magicka, stamina — the Creation Kit's order on the Stats
/// tab, the order the CLAS weight bytes appear in, and the order the derivation
/// resolves rounding ties in. `CaseIterable` iteration is therefore meaningful
/// rather than incidental.
nonisolated public enum ActorValueKind: String, CaseIterable, Hashable, Sendable {
    case health
    case magicka
    case stamina
}

/// One value per `ActorValueKind`. `Float`, because every source is: RACE DATA,
/// damage, and the HUD fraction. A regeneration of 2.5 per second must not be
/// rounded away.
nonisolated public struct ActorValues: Equatable, Sendable {
    public var health: Float
    public var magicka: Float
    public var stamina: Float

    public static let zero = ActorValues(health: 0, magicka: 0, stamina: 0)

    public init(health: Float, magicka: Float, stamina: Float) {
        self.health = health
        self.magicka = magicka
        self.stamina = stamina
    }

    /// Every kind set to the same number, which is what a fixture and a
    /// full-restore both want.
    public init(repeating value: Float) {
        self.init(health: value, magicka: value, stamina: value)
    }

    public subscript(kind: ActorValueKind) -> Float {
        get {
            switch kind {
            case .health: health
            case .magicka: magicka
            case .stamina: stamina
            }
        }
        set {
            switch kind {
            case .health: health = newValue
            case .magicka: magicka = newValue
            case .stamina: stamina = newValue
            }
        }
    }

    /// This triple with every value pulled into `0 ... limits`, per kind.
    ///
    /// A non-finite value clamps to 0 rather than propagating: it can only come
    /// from corrupt data or a divide that should not have happened, and a dead
    /// actor is a far more debuggable outcome than a NaN that spreads.
    public func clamped(to limits: ActorValues) -> ActorValues {
        var result = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let limit = limits[kind].isFinite ? max(0, limits[kind]) : 0
            let value = self[kind].isFinite ? self[kind] : 0
            result[kind] = min(max(0, value), limit)
        }
        return result
    }

    /// Each value as a fraction of the matching maximum, which is the shape the
    /// HUD meters take. A zero or negative maximum reads as empty rather than
    /// dividing.
    public func fractions(of maximums: ActorValues) -> ActorValues {
        var result = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let maximum = maximums[kind]
            guard maximum.isFinite, maximum > 0, self[kind].isFinite else { continue }
            result[kind] = min(max(0, self[kind] / maximum), 1)
        }
        return result
    }
}
