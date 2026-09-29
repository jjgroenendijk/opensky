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
import OpenSkyActorsInterface

/// One landed hit as a panel spells it.
nonisolated public struct MeleeHitReadout: Equatable, Sendable {
    /// The target reference, as its `ReferenceKey` description.
    public let target: String
    /// Contact distance along the swing, world units.
    public let distance: Float
    /// WEAP base damage before the block term.
    public let baseDamage: Float
    /// Percentage the block absorbed; zero when unblocked. Converted from the
    /// engine's fraction here, because a percentage is what a reader wants and
    /// a fraction is what the formula works in.
    public let blockedPercent: Float
    /// What actually came off health.
    public let appliedDamage: Float
    /// The SNDR that played, or nil when the chain named none.
    public let sound: String?
    /// Whether the target's graph took the stagger event.
    public let staggered: Bool

    public init(
        target: String,
        distance: Float,
        baseDamage: Float,
        blockedPercent: Float,
        appliedDamage: Float,
        sound: String?,
        staggered: Bool
    ) {
        self.target = target
        self.distance = distance
        self.baseDamage = baseDamage
        self.blockedPercent = blockedPercent
        self.appliedDamage = appliedDamage
        self.sound = sound
        self.staggered = staggered
    }
}

/// One observation of the melee runtime.
nonisolated public struct MeleeCombatSnapshot: Equatable, Sendable {
    /// False when no melee runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    public let isAvailable: Bool
    public let drawState: WeaponDrawState
    public let attackPhase: MeleeAttackPhase
    public let isBlocking: Bool
    public let isStaggering: Bool
    /// The equipped weapon's editor name, or "unarmed".
    public let weaponName: String
    /// WEAP base damage, DNAM reach multiplier and DNAM speed.
    public let weaponDamage: Float
    public let weaponReachMultiplier: Float
    public let weaponSpeed: Float
    /// What each hand is holding, as the graph counts it. These are the two
    /// numbers `iRightHandType` and `iLeftHandType` carry, shown so a wrong
    /// animation set can be traced to the hand it came from (issue #403).
    public let rightHandType: CombatHandType
    public let leftHandType: CombatHandType
    /// The resolved reach in world units, after `fCombatDistance` and scale.
    public let reach: Float
    /// Swings that reached a contact frame, and hits those swings landed.
    public let swingCount: Int
    public let hitCount: Int
    /// The last-hit trace, oldest first.
    public let trace: [MeleeHitReadout]
    /// Every combat GMST with its resolved value and where it came from.
    public let settings: [String]

    /// The reading with no runtime attached.
    public static let unavailable = MeleeCombatSnapshot(
        isAvailable: false,
        drawState: .sheathed,
        attackPhase: .idle,
        isBlocking: false,
        isStaggering: false,
        weaponName: "—",
        weaponDamage: 0,
        weaponReachMultiplier: 0,
        weaponSpeed: 0,
        rightHandType: .handToHand,
        leftHandType: .handToHand,
        reach: 0,
        swingCount: 0,
        hitCount: 0,
        trace: [],
        settings: []
    )

    public init(
        isAvailable: Bool,
        drawState: WeaponDrawState,
        attackPhase: MeleeAttackPhase,
        isBlocking: Bool,
        isStaggering: Bool,
        weaponName: String,
        weaponDamage: Float,
        weaponReachMultiplier: Float,
        weaponSpeed: Float,
        rightHandType: CombatHandType,
        leftHandType: CombatHandType,
        reach: Float,
        swingCount: Int,
        hitCount: Int,
        trace: [MeleeHitReadout],
        settings: [String]
    ) {
        self.isAvailable = isAvailable
        self.drawState = drawState
        self.attackPhase = attackPhase
        self.isBlocking = isBlocking
        self.isStaggering = isStaggering
        self.weaponName = weaponName
        self.weaponDamage = weaponDamage
        self.weaponReachMultiplier = weaponReachMultiplier
        self.weaponSpeed = weaponSpeed
        self.rightHandType = rightHandType
        self.leftHandType = leftHandType
        self.reach = reach
        self.swingCount = swingCount
        self.hitCount = hitCount
        self.trace = trace
        self.settings = settings
    }
}

@MainActor
public protocol MeleeCombatControlProviding: AnyObject {
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
