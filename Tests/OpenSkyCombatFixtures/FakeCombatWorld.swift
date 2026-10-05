// A recording fake of the session `CombatLoopRuntime` runs over. Answers are
// stored values and actions are recorded, so a whole fight runs without a
// renderer, window, or game data.

@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyProgressionInterface
import simd

@MainActor
public final class FakeCombatWorld: CombatLoopWorld {
    public var player = MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    public var actors: [CombatActorObservation] = []
    public var hostility: [ReferenceKey: ActorHostility] = [:]
    public var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    public var awareness: [ReferenceKey: CombatAwareness] = [:]
    public var healthFractions: [ReferenceKey: Float] = [:]
    public var weapons: [ReferenceKey: MeleeWeaponProfile] = [:]
    public var styles: [ReferenceKey: CombatStyleTuning] = [:]
    /// What each actor could cast, and what it can pay for.
    public var casting: [ReferenceKey: CombatCastingProfile] = [:]
    /// Whether a begun cast is accepted. False is the world refusing a cast the
    /// machine chose — magicka that fell between the decision and the call —
    /// which the machine has to fall back from rather than stall on.
    public var castingBegins = true
    /// Whether a released cast actually left the hand.
    public var castingReleases = true
    public var transients = CombatTransientCounts.none
    /// Whether a move request finds a path. False is a world with no navmesh
    /// under the point asked for, which the machine has to survive.
    public var movementSucceeds = true

    /// Skill uses the runtime reported, recorded rather than converted.
    /// `SkillAdvancementRuntimeTests` covers the conversion.
    public private(set) var skillUses: [SkillUseEvent] = []

    public init() {}

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    public private(set) var hostilityWrites = 0
    public private(set) var hostilityReads = 0
    public private(set) var damage: [ReferenceKey: Float] = [:]
    public private(set) var raised: [String] = []
    public private(set) var variables: [String: BehaviorVariableValue] = [:]
    public private(set) var clips: [(clip: CombatActorClip, key: ReferenceKey)] = []
    public private(set) var musicChanges: [Bool] = []
    public private(set) var moveRequests: [(key: ReferenceKey, point: SIMD3<Float>)] = []
    public private(set) var stopRequests: [ReferenceKey] = []
    public private(set) var packageResumes: [ReferenceKey] = []
    /// Casts begun, released and dropped, in the order they happened.
    public private(set) var castBegins: [(option: CombatSpellOption, key: ReferenceKey)] = []
    public private(set) var castReleases: [(option: CombatSpellOption, key: ReferenceKey)] = []
    public private(set) var castCancels: [ReferenceKey] = []
    public private(set) var trimRequests = 0
    public private(set) var despawnRequests = 0
    /// True when `recoilMagnitude` was written before `recoilStart` was raised,
    /// which is the write-then-raise order the graph depends on.
    public private(set) var wroteMagnitudeBeforeRecoil = false

    /// Moves one actor to `feet`, which is what a fake mover that actually
    /// walked would have done by the next step.
    public func place(_ key: ReferenceKey, at feet: SIMD3<Float>) {
        guard let index = actors.firstIndex(where: { $0.key == key }) else { return }
        let previous = actors[index]
        actors[index] = CombatActorObservation(
            key: previous.key,
            feet: feet,
            capsule: previous.capsule,
            facing: previous.facing,
            scale: previous.scale,
            isDead: previous.isDead,
            name: previous.name
        )
    }

    /// Marks one actor dead, which is what the death latch does.
    public func kill(_ key: ReferenceKey) {
        guard let index = actors.firstIndex(where: { $0.key == key }) else { return }
        let previous = actors[index]
        actors[index] = CombatActorObservation(
            key: previous.key,
            feet: previous.feet,
            capsule: previous.capsule,
            facing: previous.facing,
            scale: previous.scale,
            isDead: true,
            name: previous.name
        )
    }

    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        styles[key]
    }

    public var combatPlayer: MeleeAttacker {
        player
    }

    public func combatActors() -> [CombatActorObservation] {
        actors
    }

    public func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostilityReads += 1
        return hostility[key] ?? .neutral
    }

    @discardableResult
    public func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        hostilityWrites += 1
        return true
    }

    @discardableResult
    public func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        damage[key, default: 0] += amount
        return true
    }

    public func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        blocks[key]
    }

    public func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        awareness[observer] ?? .unaware
    }

    public func combatHealthFraction(of key: ReferenceKey) -> Float {
        healthFractions[key] ?? 1
    }

    public func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        weapons[key] ?? .unarmed
    }

    public func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        casting[key] ?? .none
    }

    @discardableResult
    public func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        castBegins.append((option: option, key: key))
        return castingBegins
    }

    @discardableResult
    public func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        castReleases.append((option: option, key: key))
        return castingReleases
    }

    public func cancelCombatCast(by key: ReferenceKey) {
        castCancels.append(key)
    }

    @discardableResult
    public func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        moveRequests.append((key: key, point: point))
        return movementSucceeds
    }

    public func stopCombatMovement(of key: ReferenceKey) {
        stopRequests.append(key)
    }

    public func resumeCombatPackage(for key: ReferenceKey) {
        packageResumes.append(key)
    }

    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        if
            name == CombatGraphNames.recoilStart,
            variables[CombatGraphNames.recoilMagnitude] != nil
        {
            wroteMagnitudeBeforeRecoil = true
        }
        raised.append(name)
        return target == nil
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
    }

    @discardableResult
    public func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        clips.append((clip: clip, key: key))
        return true
    }

    public var combatTransients: CombatTransientCounts {
        transients
    }

    @discardableResult
    public func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        trimRequests += 1
        let removed = limits.excess(over: transients)
        transients = CombatTransientCounts(
            liveProjectiles: transients.liveProjectiles - removed.liveProjectiles,
            stuckProjectiles: transients.stuckProjectiles - removed.stuckProjectiles,
            activeRagdolls: transients.activeRagdolls - removed.activeRagdolls,
            awakeBodies: transients.awakeBodies - removed.awakeBodies
        )
        return removed
    }

    public func despawnCombatTransients() {
        despawnRequests += 1
        transients = .none
    }

    public func setCombatMusicActive(_ active: Bool) {
        musicChanges.append(active)
    }
}
