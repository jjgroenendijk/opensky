// A spell landing on somebody other than its caster: the payload, the actors it
// reaches, and the resistance-scaled magnitudes. Only hostile effects scale, by
// `magicDamageMultiplier` (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>);
// "Ignore Resistance" skips the step. EFIT area is in feet; the units per foot
// in `MagicAreaSettings` are uncertain. See docs/engine/spell-delivery.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

/// What a spell carries with it once it has left the caster.
///
/// Resolved at cast time and never re-derived: a projectile in the air must
/// apply the spell that was cast, not whatever the caster has readied by the
/// time it lands — the same rule `LiveProjectile` already follows for a bow's
/// damage.
nonisolated public struct SpellPayload: Equatable, Sendable {
    /// The SPEL or SCRL that was cast, which is what the applied effects are
    /// sourced to.
    public let spell: ReferenceKey
    /// The plugin every EFID in `entries` is relative to.
    public let sourcePlugin: String
    /// Who cast it, so an applied effect names its caster.
    public let caster: ReferenceKey
    /// The effect list as authored. Magnitudes here are pre-resistance.
    public let entries: [MagicItemEffect]
    /// Whether any entry's MGEF carries the Hostile flag, resolved at cast time.
    /// What decides whether a landed spell provokes its target.
    public let isHostile: Bool
    /// SPEL's "Ignore Resistance" flag: true skips the resistance step entirely.
    public let ignoresResistance: Bool
    /// The PROJ the MGEF names, for an aimed delivery. Nil for every delivery
    /// that launches nothing.
    public let projectile: FormID?
    /// FULL name or editor ID, for the readout. Never empty.
    public let name: String

    public var source: ActiveEffectSource {
        ActiveEffectSource(kind: .spell, record: spell)
    }
}

/// One actor a landed spell reached, and how far from the impact point it was.
nonisolated public struct SpellHitTarget: Equatable, Sendable {
    public let key: ReferenceKey
    /// Distance from the impact point to the actor's capsule, world units.
    /// Zero for the actor a projectile struck directly.
    public let distance: Float
    /// Whether this actor is the one the delivery named, as opposed to a
    /// bystander an area caught. A direct target receives every entry; a
    /// bystander receives only the entries whose area reaches it.
    public let isDirect: Bool

    public init(key: ReferenceKey, distance: Float = 0, isDirect: Bool = true) {
        self.key = key
        self.distance = distance.isFinite ? max(0, distance) : 0
        self.isDirect = isDirect
    }
}

/// One landed spell, as the world seam receives it.
nonisolated public struct SpellHit: Equatable, Sendable {
    public let payload: SpellPayload
    /// Every actor it reached, direct target first.
    public let targets: [SpellHitTarget]

    public init(payload: SpellPayload, targets: [SpellHitTarget]) {
        self.payload = payload
        self.targets = targets
    }
}

/// How one entry's magnitude was moved by the target's resistances, so a test
/// and the sidebar panel can assert the adjustment rather than infer it from a
/// health bar.
nonisolated public struct SpellMagnitudeAdjustment: Equatable, Sendable {
    public let target: ReferenceKey
    /// Its display name, for the readout.
    public let name: String
    /// MGEF DATA "Resistance Actor Value", or nil where the record names none.
    public let resistance: Int32?
    public let baseMagnitude: Float
    /// What the base magnitude was multiplied by. 1 when nothing resisted,
    /// 0 for immunity, above 1 for a weakness.
    public let multiplier: Float

    public var adjustedMagnitude: Float {
        baseMagnitude * multiplier
    }

    /// One line, the shape the readout joins with newlines.
    public var line: String {
        String(
            format: "%@ on %@: %.1f x %.3f = %.1f",
            name, target.description, baseMagnitude, multiplier, adjustedMagnitude
        )
    }

    public init(
        target: ReferenceKey,
        name: String,
        resistance: Int32?,
        baseMagnitude: Float,
        multiplier: Float
    ) {
        self.target = target
        self.name = name
        self.resistance = resistance
        self.baseMagnitude = baseMagnitude
        self.multiplier = multiplier
    }
}

/// What applying one landed spell did.
nonisolated public struct SpellHitReport: Equatable, Sendable {
    /// Actors the spell was actually applied to.
    public private(set) var targetCount = 0
    /// Timed effects stored across every target.
    public private(set) var storedCount = 0
    /// Effect entries handed to the effect runtime, before it decided what it
    /// could carry out.
    public private(set) var entryCount = 0
    /// Every hostile entry's resistance adjustment, in application order.
    public private(set) var adjustments: [SpellMagnitudeAdjustment] = []

    public static let none = SpellHitReport()

    public var didApply: Bool {
        targetCount > 0
    }

    public mutating func note(
        target adjustments: [SpellMagnitudeAdjustment],
        entries: Int,
        stored: Int
    ) {
        targetCount += 1
        entryCount += entries
        storedCount += stored
        self.adjustments += adjustments
    }

    public init(
        targetCount: Int = 0,
        storedCount: Int = 0,
        entryCount: Int = 0,
        adjustments: [SpellMagnitudeAdjustment] = []
    ) {
        self.targetCount = targetCount
        self.storedCount = storedCount
        self.entryCount = entryCount
        self.adjustments = adjustments
    }
}

/// The area conversion, as a setting rather than a constant. See the file
/// comment for why the number is uncertain and what would settle it.
nonisolated public struct MagicAreaSettings: Equatable, Sendable {
    /// World units one authored area unit spans. EFIT's area is in feet.
    public var worldUnitsPerAreaUnit: Float

    public static let documentedDefaults = MagicAreaSettings(
        worldUnitsPerAreaUnit: PlayerCapsule.standard.height / 6
    )

    /// The radius an EFIT area covers, world units. Zero for a point effect.
    public func radius(ofArea area: UInt32) -> Float {
        max(0, Float(area) * max(0, worldUnitsPerAreaUnit))
    }
}

/// Who a landed spell reaches.
///
/// Pure functions over values — no world, no clock — so the area rule is a
/// plain arithmetic assertion in a test rather than something only a running
/// session can show.
nonisolated public enum SpellHitTargeting: Sendable {
    /// The widest radius any entry of `payload` covers, world units. Zero when
    /// every entry is a point effect.
    public static func widestRadius(
        of payload: SpellPayload,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> Float {
        widestRadius(of: payload.entries, settings: settings)
    }

    public static func widestRadius(
        of entries: [MagicItemEffect],
        settings: MagicAreaSettings = .documentedDefaults
    ) -> Float {
        entries.map { settings.radius(ofArea: $0.area) }.max() ?? 0
    }

    /// Every actor `payload` reaches when it lands at `position`. The struck actor
    /// comes first and gets every entry. Bystanders are measured to their capsule.
    /// - Parameter excluding: the caster, matched on key; its own spell never
    ///   catches it.
    public static func targets(
        of payload: SpellPayload,
        at position: SIMD3<Float>,
        struck: ReferenceKey?,
        candidates: [MeleeTarget],
        excluding shooter: ReferenceKey?,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [SpellHitTarget] {
        targets(
            of: payload.entries,
            at: position,
            struck: struck,
            candidates: candidates,
            excluding: shooter,
            settings: settings
        )
    }

    /// The same rule for an entry list without a payload, such as a weapon's
    /// contact enchantment.
    public static func targets(
        of entries: [MagicItemEffect],
        at position: SIMD3<Float>,
        struck: ReferenceKey?,
        candidates: @autoclosure () -> [MeleeTarget],
        excluding shooter: ReferenceKey?,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [SpellHitTarget] {
        var targets: [SpellHitTarget] = []
        if let struck, struck != shooter {
            targets.append(SpellHitTarget(key: struck, distance: 0, isDirect: true))
        }
        let radius = widestRadius(of: entries, settings: settings)
        guard radius > 0 else { return targets }
        let bystanders = candidates()
            .filter { $0.key != shooter && $0.key != struck }
            .map { (key: $0.key, distance: distance(from: position, to: $0)) }
            .filter { $0.distance <= radius }
            // By distance, then by key, so two actors at the same remove are
            // always applied to in the same order — the tie-break rule the
            // impact query and the interaction raycaster both follow.
            .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
        targets += bystanders.map {
            SpellHitTarget(key: $0.key, distance: $0.distance, isDirect: false)
        }
        return targets
    }

    /// Distance from `position` to `target`'s capsule surface, never negative.
    public static func distance(from position: SIMD3<Float>, to target: MeleeTarget) -> Float {
        let segment = target.segment
        let axis = segment.second - segment.first
        let lengthSquared = simd_length_squared(axis)
        let closest: SIMD3<Float> = if lengthSquared > Float.ulpOfOne {
            segment.first + axis * min(max(
                simd_dot(position - segment.first, axis) / lengthSquared, 0
            ), 1)
        } else {
            segment.first
        }
        return max(0, simd_distance(position, closest) - max(0, target.capsule.radius))
    }
}
