// The session `CombatLoopRuntime` runs over, as a recording fake (issues #374
// and #424).
//
// Moved out of `CombatLoopRuntimeTests` when 16.7 widened the seam: the fake now
// answers awareness, health, movement and package resumption as well, and both
// the unit suite and the real-data suite want to hand the runtime a world with
// nothing but stored values in it.
//
// Every answer is a plain stored value and every action is recorded rather than
// performed, which is what lets a whole fight — approach, attack, block, flee,
// search and give-up — run with no renderer, no window and no game data.

@testable import opensky
import simd

@MainActor
final class FakeCombatWorld: CombatLoopWorld {
    var player = MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    var actors: [CombatActorObservation] = []
    var hostility: [ReferenceKey: ActorHostility] = [:]
    var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    var awareness: [ReferenceKey: CombatAwareness] = [:]
    var healthFractions: [ReferenceKey: Float] = [:]
    var weapons: [ReferenceKey: MeleeWeaponProfile] = [:]
    /// What each actor could cast, and what it can pay for (issue #473).
    var casting: [ReferenceKey: CombatCastingProfile] = [:]
    /// Whether a begun cast is accepted. False is the world refusing a cast the
    /// machine chose — magicka that fell between the decision and the call —
    /// which the machine has to fall back from rather than stall on.
    var castingBegins = true
    /// Whether a released cast actually left the hand.
    var castingReleases = true
    var transients = CombatTransientCounts.none
    /// Whether a move request finds a path. False is a world with no navmesh
    /// under the point asked for, which the machine has to survive.
    var movementSucceeds = true

    /// Skill uses the runtime reported (issue #498), recorded rather than
    /// converted: what a combat suite needs is that the exchange reached
    /// progression with the right amounts, and `SkillAdvancementRuntimeTests`
    /// asks what converting one does.
    private(set) var skillUses: [SkillUseEvent] = []

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    private(set) var hostilityWrites = 0
    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var raised: [String] = []
    private(set) var variables: [String: BehaviorVariableValue] = [:]
    private(set) var clips: [(clip: CombatActorClip, key: ReferenceKey)] = []
    private(set) var musicChanges: [Bool] = []
    private(set) var moveRequests: [(key: ReferenceKey, point: SIMD3<Float>)] = []
    private(set) var stopRequests: [ReferenceKey] = []
    private(set) var packageResumes: [ReferenceKey] = []
    /// Casts begun, released and dropped, in the order they happened.
    private(set) var castBegins: [(option: CombatSpellOption, key: ReferenceKey)] = []
    private(set) var castReleases: [(option: CombatSpellOption, key: ReferenceKey)] = []
    private(set) var castCancels: [ReferenceKey] = []
    private(set) var trimRequests = 0
    private(set) var despawnRequests = 0
    /// True when `recoilMagnitude` was written before `recoilStart` was raised,
    /// which is the write-then-raise order the graph depends on.
    private(set) var wroteMagnitudeBeforeRecoil = false

    /// Moves one actor to `feet`, which is what a fake mover that actually
    /// walked would have done by the next step.
    func place(_ key: ReferenceKey, at feet: SIMD3<Float>) {
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
    func kill(_ key: ReferenceKey) {
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

    var combatPlayer: MeleeAttacker {
        player
    }

    func combatActors() -> [CombatActorObservation] {
        actors
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        hostilityWrites += 1
        return true
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        damage[key, default: 0] += amount
        return true
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        blocks[key]
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        awareness[observer] ?? .unaware
    }

    func combatHealthFraction(of key: ReferenceKey) -> Float {
        healthFractions[key] ?? 1
    }

    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        weapons[key] ?? .unarmed
    }

    func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        casting[key] ?? .none
    }

    @discardableResult
    func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        castBegins.append((option: option, key: key))
        return castingBegins
    }

    @discardableResult
    func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        castReleases.append((option: option, key: key))
        return castingReleases
    }

    func cancelCombatCast(by key: ReferenceKey) {
        castCancels.append(key)
    }

    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        moveRequests.append((key: key, point: point))
        return movementSucceeds
    }

    func stopCombatMovement(of key: ReferenceKey) {
        stopRequests.append(key)
    }

    func resumeCombatPackage(for key: ReferenceKey) {
        packageResumes.append(key)
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        if
            name == CombatGraphNames.recoilStart,
            variables[CombatGraphNames.recoilMagnitude] != nil
        {
            wroteMagnitudeBeforeRecoil = true
        }
        raised.append(name)
        return target == nil
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
    }

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        clips.append((clip: clip, key: key))
        return true
    }

    var combatTransients: CombatTransientCounts {
        transients
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
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

    func despawnCombatTransients() {
        despawnRequests += 1
        transients = .none
    }

    func setCombatMusicActive(_ active: Bool) {
        musicChanges.append(active)
    }
}
