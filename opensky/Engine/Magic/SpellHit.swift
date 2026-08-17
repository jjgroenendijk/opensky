// A spell landing on somebody other than its caster (issue #471, roadmap item
// 19.8): the payload a delivery carries, the actors it reaches, and the
// resistance-scaled magnitudes it applies.
//
// Split from the delivery mechanisms on purpose. A projectile, a target-actor
// cast and a concentration beam differ entirely in how they *find* an actor and
// not at all in what happens once they have one, so the finding lives in
// `ProjectileRuntime` and `CasterRuntime` and the applying lives here — one
// implementation, one place the resistance formula is read.
//
// ## What scales, and by how much
//
// Only **hostile** effects. UESP states the rule over damage rather than over
// every effect: "Magic Resistance decreases the damage of any offensive spell by
// the displayed percentage" (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>),
// and the MGEF Hostile flag is the record's own word for "offensive". A restore
// or a fortify is handed to the effect runtime unscaled.
//
// The multiplier itself is item 19.5's `magicDamageMultiplier`, unchanged and
// uncopied: Resist Magic first, then the MGEF's own resistance actor value,
// multiplicatively. A **weakness** is the same formula with a negative
// resistance — UESP's Weakness to Fire is worded "Target is <mag>% weaker to
// fire damage" (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>) and is
// authored as a detrimental Value Modifier on Resist Fire, so -30 points reads
// as a fraction of -0.3 and a multiplier of 1.3.
//
// The SPEL flag xEdit names "Ignore Resistance" skips the whole step, which is
// why the payload carries it rather than the resolver assuming every spell is
// resistible.
//
// ## Where the area radius comes from, and what is uncertain about it
//
// EFIT's area is authored in **feet**, which is measured rather than assumed:
// the resolved game-setting table names the effect item's area unit outright
// (`sMagicEffectItemFeet`), and vanilla `Fireball` carries an EFIT area of 15
// against UESP's description of the same spell as "a fiery explosion for 40
// points of damage in a 15 foot radius" (<https://en.uesp.net/wiki/Skyrim:Fireball>,
// probed 2026-08-16 with `openskycli record Fireball`).
//
// **How many world units a foot is, is not settled by any source this session
// could reach.** `MagicAreaSettings.documentedDefaults` carries 128/6 units per
// foot, derived from this engine's own `PlayerCapsule.standard` height of 128
// units for an adult human, and it is a setting rather than a constant so the
// number can be corrected without touching the rule. The uncertainty is
// recorded in docs/engine/magic.md rather than hidden.
//
// Documented in docs/engine/magic.md.

import Foundation
import simd

/// What a spell carries with it once it has left the caster.
///
/// Resolved at cast time and never re-derived: a projectile in the air must
/// apply the spell that was cast, not whatever the caster has readied by the
/// time it lands — the same rule `LiveProjectile` already follows for a bow's
/// damage.
nonisolated struct SpellPayload: Equatable, Sendable {
    /// The SPEL or SCRL that was cast, which is what the applied effects are
    /// sourced to.
    let spell: ReferenceKey
    /// The plugin every EFID in `entries` is relative to.
    let sourcePlugin: String
    /// Who cast it, so an applied effect names its caster.
    let caster: ReferenceKey
    /// The effect list as authored. Magnitudes here are pre-resistance.
    let entries: [MagicItemEffect]
    /// Whether any entry's MGEF carries the Hostile flag, resolved at cast time.
    /// What decides whether a landed spell provokes its target.
    let isHostile: Bool
    /// SPEL's "Ignore Resistance" flag: true skips the resistance step entirely.
    let ignoresResistance: Bool
    /// The PROJ the MGEF names, for an aimed delivery. Nil for every delivery
    /// that launches nothing.
    let projectile: FormID?
    /// FULL name or editor ID, for the readout. Never empty.
    let name: String

    var source: ActiveEffectSource {
        ActiveEffectSource(kind: .spell, record: spell)
    }
}

/// One actor a landed spell reached, and how far from the impact point it was.
nonisolated struct SpellHitTarget: Equatable, Sendable {
    let key: ReferenceKey
    /// Distance from the impact point to the actor's capsule, world units.
    /// Zero for the actor a projectile struck directly.
    let distance: Float
    /// Whether this actor is the one the delivery named, as opposed to a
    /// bystander an area caught. A direct target receives every entry; a
    /// bystander receives only the entries whose area reaches it.
    let isDirect: Bool

    init(key: ReferenceKey, distance: Float = 0, isDirect: Bool = true) {
        self.key = key
        self.distance = distance.isFinite ? max(0, distance) : 0
        self.isDirect = isDirect
    }
}

/// One landed spell, as the world seam receives it.
nonisolated struct SpellHit: Equatable, Sendable {
    let payload: SpellPayload
    /// Where it landed, world space. The caster's own position for a delivery
    /// that never travelled.
    let position: SIMD3<Float>
    /// Every actor it reached, direct target first.
    let targets: [SpellHitTarget]
}

/// How one entry's magnitude was moved by the target's resistances, so a test
/// and the sidebar panel can assert the adjustment rather than infer it from a
/// health bar.
nonisolated struct SpellMagnitudeAdjustment: Equatable, Sendable {
    let target: ReferenceKey
    /// The MGEF the entry names.
    let effect: FormID
    /// Its display name, for the readout.
    let name: String
    /// MGEF DATA "Resistance Actor Value", or nil where the record names none.
    let resistance: Int32?
    let baseMagnitude: Float
    /// What the base magnitude was multiplied by. 1 when nothing resisted,
    /// 0 for immunity, above 1 for a weakness.
    let multiplier: Float

    var adjustedMagnitude: Float {
        baseMagnitude * multiplier
    }

    /// One line, the shape the readout joins with newlines.
    var line: String {
        String(
            format: "%@ on %@: %.1f x %.3f = %.1f",
            name, target.description, baseMagnitude, multiplier, adjustedMagnitude
        )
    }
}

/// What applying one landed spell did.
nonisolated struct SpellHitReport: Equatable, Sendable {
    /// Actors the spell was actually applied to.
    private(set) var targetCount = 0
    /// Timed effects stored across every target.
    private(set) var storedCount = 0
    /// Effect entries handed to the effect runtime, before it decided what it
    /// could carry out.
    private(set) var entryCount = 0
    /// Every hostile entry's resistance adjustment, in application order.
    private(set) var adjustments: [SpellMagnitudeAdjustment] = []

    static let none = SpellHitReport()

    var didApply: Bool {
        targetCount > 0
    }

    mutating func note(target adjustments: [SpellMagnitudeAdjustment], entries: Int, stored: Int) {
        targetCount += 1
        entryCount += entries
        storedCount += stored
        self.adjustments += adjustments
    }
}

/// The area conversion, as a setting rather than a constant. See the file
/// comment for why the number is uncertain and what would settle it.
nonisolated struct MagicAreaSettings: Equatable, Sendable {
    /// World units one authored area unit spans. EFIT's area is in feet.
    var worldUnitsPerAreaUnit: Float

    static let documentedDefaults = MagicAreaSettings(
        worldUnitsPerAreaUnit: PlayerCapsule.standard.height / 6
    )

    /// The radius an EFIT area covers, world units. Zero for a point effect.
    func radius(ofArea area: UInt32) -> Float {
        max(0, Float(area) * max(0, worldUnitsPerAreaUnit))
    }
}

/// Who a landed spell reaches.
///
/// Pure functions over values — no world, no clock — so the area rule is a
/// plain arithmetic assertion in a test rather than something only a running
/// session can show.
nonisolated enum SpellHitTargeting {
    /// The widest radius any entry of `payload` covers, world units. Zero when
    /// every entry is a point effect.
    static func widestRadius(
        of payload: SpellPayload,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> Float {
        payload.entries.map { settings.radius(ofArea: $0.area) }.max() ?? 0
    }

    /// Every actor `payload` reaches when it lands at `position`.
    ///
    /// The struck actor comes first and is direct, so it receives every entry
    /// including the point ones. Everybody else is a bystander at their own
    /// distance, measured to the **capsule** rather than to the feet, so a
    /// blast at head height catches somebody standing beside it.
    ///
    /// - Parameter excluding: the caster, which its own spell never catches.
    ///   Matched on key for the reason a shot never hits its own shooter: the
    ///   caster is often the nearest actor to a spell that detonated close by.
    static func targets(
        of payload: SpellPayload,
        at position: SIMD3<Float>,
        struck: ReferenceKey?,
        candidates: [MeleeTarget],
        excluding shooter: ReferenceKey?,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [SpellHitTarget] {
        var targets: [SpellHitTarget] = []
        if let struck, struck != shooter {
            targets.append(SpellHitTarget(key: struck, distance: 0, isDirect: true))
        }
        let radius = widestRadius(of: payload, settings: settings)
        guard radius > 0 else { return targets }
        let bystanders = candidates
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
    static func distance(from position: SIMD3<Float>, to target: MeleeTarget) -> Float {
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

/// Applying one landed spell to the actors it reached.
///
/// A free function over an `inout ActiveEffectRuntime` rather than a type of its
/// own, for the reason the consumption path is one: the effect runtime is a
/// value over a shared store whose tally advances as it works, and a copy held
/// here would grow a tally the panel never sees.
@MainActor
enum SpellHitApplication {
    /// Applies `hit` to every actor it reached, scaling hostile magnitudes by
    /// that actor's own resistances.
    ///
    /// - Parameter holders: the actor-value holder for each target key. A key
    ///   with no holder is an actor that stopped being resident between the
    ///   impact and this call, and is skipped rather than guessed at.
    @discardableResult
    static func apply(
        _ hit: SpellHit,
        holders: [ReferenceKey: ActorValueHolder],
        using runtime: inout ActiveEffectRuntime,
        settings: MagicAreaSettings = .documentedDefaults,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> SpellHitReport {
        var report = SpellHitReport()
        for target in hit.targets {
            guard let holder = holders[target.key] else { continue }
            let reaching = entries(of: hit.payload, reaching: target, settings: settings)
            guard !reaching.isEmpty else { continue }
            let scaled = scale(
                reaching,
                of: hit.payload,
                on: holder,
                using: runtime,
                resistances: resistances
            )
            let stored = runtime.apply(
                scaled.entries,
                fromPlugin: hit.payload.sourcePlugin,
                source: hit.payload.source,
                caster: hit.payload.caster,
                on: holder
            )
            report.note(
                target: scaled.adjustments,
                entries: scaled.entries.count,
                stored: stored.count
            )
        }
        return report
    }

    /// The entries of `payload` that reach `target`.
    ///
    /// A direct target receives the whole list. A bystander receives only the
    /// entries whose authored area covers the distance between them, so one
    /// spell can damage everything in a blast while staggering only what it
    /// actually struck — which is the shape vanilla `Fireball` is authored in.
    static func entries(
        of payload: SpellPayload,
        reaching target: SpellHitTarget,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [MagicItemEffect] {
        guard !target.isDirect else { return payload.entries }
        return payload.entries.filter { entry in
            entry.area > 0 && target.distance <= settings.radius(ofArea: entry.area)
        }
    }

    /// Scales every hostile entry by `holder`'s resistances, reporting what it
    /// moved.
    static func scale(
        _ entries: [MagicItemEffect],
        of payload: SpellPayload,
        on holder: ActorValueHolder,
        using runtime: ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> (entries: [MagicItemEffect], adjustments: [SpellMagnitudeAdjustment]) {
        guard !payload.ignoresResistance else { return (entries, []) }
        var scaled: [MagicItemEffect] = []
        var adjustments: [SpellMagnitudeAdjustment] = []
        for entry in entries {
            guard
                let resolved = runtime.effects.resolve(entry, fromPlugin: payload.sourcePlugin),
                let data = resolved.effect.data,
                data.flags.contains(.hostile)
            else {
                scaled.append(entry)
                continue
            }
            let element = ActorValueIdentity.isVanilla(index: data.resistanceActorValue)
                ? data.resistanceActorValue
                : nil
            let multiplier = runtime.values.magicDamageMultiplier(
                element: element, on: holder, settings: resistances
            )
            adjustments.append(SpellMagnitudeAdjustment(
                target: holder.key,
                effect: entry.effect,
                name: resolved.displayName,
                resistance: element,
                baseMagnitude: entry.magnitude,
                multiplier: multiplier
            ))
            scaled.append(entry.scalingMagnitude(by: multiplier))
        }
        return (scaled, adjustments)
    }
}
