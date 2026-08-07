// Main-app melee inspection seam (issue #195, roadmap item 15.4, scope point
// 8): weapon-drawn state, attack phase, and the last-hit trace, plus the three
// new key bindings as controls rather than as unadvertised keystrokes.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `ActorValueControlSnapshot` is one: the readout has to be a pure
// function of a single engine observation, not of several taken microseconds
// apart while a swing is resolving between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One landed hit as a panel spells it.
nonisolated struct MeleeHitReadout: Equatable, Sendable {
    /// The target reference, as its `ReferenceKey` description.
    let target: String
    /// Contact distance along the swing, world units.
    let distance: Float
    /// WEAP base damage before the block term.
    let baseDamage: Float
    /// Percentage the block absorbed; zero when unblocked. Converted from the
    /// engine's fraction here, because a percentage is what a reader wants and
    /// a fraction is what the formula works in.
    let blockedPercent: Float
    /// What actually came off health.
    let appliedDamage: Float
    /// The SNDR that played, or nil when the chain named none.
    let sound: String?
    /// Whether the target's graph took the stagger event.
    let staggered: Bool
}

/// One observation of the melee runtime.
nonisolated struct MeleeCombatSnapshot: Equatable, Sendable {
    /// False when no melee runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    let isAvailable: Bool
    let drawState: WeaponDrawState
    let attackPhase: MeleeAttackPhase
    let isBlocking: Bool
    let isStaggering: Bool
    /// The equipped weapon's editor name, or "unarmed".
    let weaponName: String
    /// WEAP base damage, DNAM reach multiplier and DNAM speed.
    let weaponDamage: Float
    let weaponReachMultiplier: Float
    let weaponSpeed: Float
    /// The resolved reach in world units, after `fCombatDistance` and scale.
    let reach: Float
    /// Swings that reached a contact frame, and hits those swings landed.
    let swingCount: Int
    let hitCount: Int
    /// The last-hit trace, oldest first.
    let trace: [MeleeHitReadout]
    /// Every combat GMST with its resolved value and where it came from.
    let settings: [String]

    /// The reading with no runtime attached.
    static let unavailable = MeleeCombatSnapshot(
        isAvailable: false,
        drawState: .sheathed,
        attackPhase: .idle,
        isBlocking: false,
        isStaggering: false,
        weaponName: "—",
        weaponDamage: 0,
        weaponReachMultiplier: 0,
        weaponSpeed: 0,
        reach: 0,
        swingCount: 0,
        hitCount: 0,
        trace: [],
        settings: []
    )
}

@MainActor
protocol MeleeCombatControlProviding: AnyObject {
    var meleeCombatSnapshot: MeleeCombatSnapshot { get }

    /// Whether the weapon is out. Setting it raises the census-named draw or
    /// sheath event, exactly as the R key does — a control the panel offers
    /// and a key the player presses must be indistinguishable downstream.
    ///
    /// Block is deliberately not offered the same way. It is a held modifier
    /// with nothing to latch, and a checkbox that asserted it for a single
    /// frame would read as broken; it is reported live in the readout instead,
    /// on the same terms `LocomotionBindingsSection` reports run and sprint.
    var isWeaponDrawn: Bool { get set }

    /// Requests exactly one swing, the same latch the left mouse button sets.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func requestMeleeAttack() -> String

    /// Empties the last-hit trace and both counts, without disturbing anything
    /// the player can feel.
    func clearMeleeTrace()
}
