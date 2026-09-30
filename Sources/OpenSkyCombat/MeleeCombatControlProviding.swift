// Main-app melee inspection seam: draw state, attack phase, the last-hit trace,
// and the melee keys as controls. One snapshot value, so the readout comes from
// a single engine observation. AppKit-free.

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
    /// What the weapon's enchantment did, or nil when it carries none.
    public let enchantment: String?

    public init(
        target: String,
        distance: Float,
        baseDamage: Float,
        blockedPercent: Float,
        appliedDamage: Float,
        sound: String?,
        staggered: Bool,
        enchantment: String? = nil
    ) {
        self.target = target
        self.distance = distance
        self.baseDamage = baseDamage
        self.blockedPercent = blockedPercent
        self.appliedDamage = appliedDamage
        self.sound = sound
        self.staggered = staggered
        self.enchantment = enchantment
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
    /// What each hand holds, as the graph counts it: `iRightHandType` and
    /// `iLeftHandType`, so a wrong animation set can be traced to its hand.
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

    /// Whether the weapon is out. Setting it raises the draw or sheath event, as the
    /// R key does. Block is not offered here: it is a held modifier, so the readout
    /// shows it live.
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
