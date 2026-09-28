// The three primary actor values and the triple that carries them (issue #194,
// roadmap item 15.3).
//
// Health, magicka and stamina are one type rather than three loose floats
// because every operation in this subsystem touches all three at once: the
// derivation produces a triple, the runtime clamps a triple, the save writes a
// triple, and the HUD reads a triple. Splitting them would put the same three
// lines at every call site and invite one of them to drift.
//
// Only the three *primary* values live here. Skills, resistances and the rest
// of the actor-value table are M18; this type deliberately does not pretend to
// be the general actor-value store those will need.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// One of the three primary actor values.
///
/// Ordered health, magicka, stamina — the Creation Kit's order on the Stats
/// tab, the order the CLAS weight bytes appear in, and the order the derivation
/// resolves rounding ties in. `CaseIterable` iteration is therefore meaningful
/// rather than incidental.
nonisolated enum ActorValueKind: String, CaseIterable, Hashable, Sendable {
    case health
    case magicka
    case stamina
}

/// One value per `ActorValueKind`.
///
/// Values are `Float` because every source is: the RACE DATA starting
/// attributes are floats, damage from a weapon will be, and the HUD meters take
/// a fraction. The derivation rounds to whole numbers where the documented
/// formula does, but the type itself does not force integers — a healing effect
/// that restores 2.5 per second must not quantize away.
nonisolated struct ActorValues: Equatable, Sendable {
    var health: Float
    var magicka: Float
    var stamina: Float

    static let zero = ActorValues(health: 0, magicka: 0, stamina: 0)

    init(health: Float, magicka: Float, stamina: Float) {
        self.health = health
        self.magicka = magicka
        self.stamina = stamina
    }

    /// Every kind set to the same number, which is what a fixture and a
    /// full-restore both want.
    init(repeating value: Float) {
        self.init(health: value, magicka: value, stamina: value)
    }

    subscript(kind: ActorValueKind) -> Float {
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

    /// True when every value is finite, which is the precondition the runtime
    /// enforces before storing anything: one NaN in a maximum would make every
    /// later clamp produce NaN and the HUD meter would go blank rather than
    /// empty.
    var isFinite: Bool {
        health.isFinite && magicka.isFinite && stamina.isFinite
    }

    /// This triple with every value pulled into `0 ... limits`, per kind.
    ///
    /// A non-finite value clamps to 0 rather than propagating: it can only come
    /// from corrupt data or a divide that should not have happened, and a dead
    /// actor is a far more debuggable outcome than a NaN that spreads.
    func clamped(to limits: ActorValues) -> ActorValues {
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
    func fractions(of maximums: ActorValues) -> ActorValues {
        var result = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let maximum = maximums[kind]
            guard maximum.isFinite, maximum > 0, self[kind].isFinite else { continue }
            result[kind] = min(max(0, self[kind] / maximum), 1)
        }
        return result
    }
}
