// A recording fake of the session `CombatLoopRuntime` runs over. Answers are
// stored values and actions are recorded, so a whole fight runs without a
// renderer, window, or game data.

import Foundation
@testable public import OpenSkyActorsInterface
@testable public import OpenSkyBehavior
@testable public import OpenSkyCombat
@testable public import OpenSkyCombatInterface
@testable public import OpenSkyFormatsESM
public import OpenSkyGameData
@testable public import OpenSkyMagicInterface
@testable public import OpenSkyPhysics
@testable public import OpenSkyProgressionInterface
import simd

@MainActor
public final class FakeCombatWorld: CombatLoopWorld {
    public var player = MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    public var actors: [CombatActorObservation] = []
    public var hostility: [ReferenceKey: ActorHostility] = [:]
    public var reactions: [ReferenceKey: ActorReaction] = [:]
    public var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    /// Actors with no shield; every other actor wears one.
    public var shieldless: Set<ReferenceKey> = []
    /// The base rating of each actor's worn shield; a missing actor wears none.
    public var shieldRatings: [ReferenceKey: Float] = [:]
    /// What the player's melee does, for the block loop.
    public var playerMelee: CombatPlayerMelee?
    /// Each Bash line said, as speaker and target.
    public var bashLines: [[ReferenceKey]] = []
    public var awareness: [ReferenceKey: CombatAwareness] = [:]
    /// One observer's awareness of one target, read before `awareness`.
    public var pairAwareness: [CombatFoePair: CombatAwareness] = [:]
    /// The NPC pairs whose observer attacks its target on sight.
    public var hostilePairs: Set<CombatFoePair> = []
    /// What an observer makes of another actor.
    public var pairReactions: [CombatFoePair: ActorReaction] = [:]
    /// Helper and ally pairs: the observer helps its target in a fight.
    public var assistPairs: Set<CombatFoePair> = []
    public var teammates: Set<ReferenceKey> = []
    public var moralities: [ReferenceKey: Float] = [:]
    /// What each helper (observer) makes of each actor (target) as a criminal.
    public var crimeStandings: [CombatFoePair: CombatCrimeStanding] = [:]
    public var guards: Set<ReferenceKey> = []
    public var crimeAttackers: Set<ReferenceKey> = []
    public var aggroRadii: [ReferenceKey: AggroRadius] = [:]
    /// The last head-look target each actor was given, and for how many seconds.
    public var looks: [ReferenceKey: AggroLook] = [:]
    /// The last point each actor turned toward.
    public var turns: [ReferenceKey: SIMD3<Float>] = [:]
    /// Where each archer's arrow would meet its target.
    public var aimPoints: [ReferenceKey: SIMD3<Float>] = [:]
    /// Each warning line said: the speaker, then its target.
    public var warningLines: [[ReferenceKey]] = []
    public var temperaments: [ReferenceKey: CombatTemperament] = [:]
    public var dangerThreats: [DangerThreat] = []
    public var healthFractions: [ReferenceKey: Float] = [:]
    public var influences: [ReferenceKey: ActorMagicInfluence] = [:]
    /// Actors whose current package has the Ignore Combat flag.
    public var ignoringCombat: Set<ReferenceKey> = []
    public var children: Set<ReferenceKey> = []
    public var weapons: [ReferenceKey: MeleeWeaponProfile] = [:]
    public var leftWeapons: [ReferenceKey: MeleeWeaponProfile] = [:]
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

    /// The disease each attacker's race attacks carry.
    public var attackDiseases: [ReferenceKey: ReferenceKey] = [:]
    public var diseaseResists: [ReferenceKey: Float] = [:]
    /// Each disease given, as (disease, target), in order.
    public private(set) var contractedDiseases: [(disease: ReferenceKey, target: ReferenceKey)] = []

    /// Each actor's race attacks, and its Stamina when set.
    public var raceAttacks: [ReferenceKey: [RaceAttack]] = [:]
    public var staminas: [ReferenceKey: Float] = [:]
    /// Each knockdown pushed, as (target, magnitude), in order.
    public private(set) var knockdowns: [(target: ReferenceKey, magnitude: Float)] = []
    public private(set) var knockdownStaggerMults: [Float] = []
    /// A turn faces the actor at its point at once, as the mover does over a few frames.
    public var turnsActors = true

    public init() {}

    /// Destructible objects in the world, and the damage each took from a swing.
    public var destructibles: [MeleeTarget] = []
    public private(set) var objectDamage: [ReferenceKey: Float] = [:]

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
    /// Each event raised on an actor's graph, by name and actor.
    public private(set) var actorEvents: [(name: String, key: ReferenceKey)] = []
    public private(set) var actorVariables: [ReferenceKey: [String: BehaviorVariableValue]] = [:]
    /// Actors whose graph still plays its equip clip.
    public var equipping: Set<ReferenceKey> = []
    /// Actors that play a half of a kill move.
    public var inKillMove: Set<ReferenceKey> = []
    /// Actors whose graph reports `IsAttackReady` false.
    public var notAttackReady: Set<ReferenceKey> = []
    public private(set) var clips: [(clip: CombatActorClip, key: ReferenceKey)] = []
    public private(set) var arrowShots: [CombatArrowShot] = []
    public private(set) var musicChanges: [Bool] = []
    public private(set) var moveRequests: [(key: ReferenceKey, point: SIMD3<Float>)] = []
    public private(set) var stopRequests: [ReferenceKey] = []
    public private(set) var packageResumes: [ReferenceKey] = []
    /// Casts begun, released and dropped, in the order they happened.
    public private(set) var castBegins: [(option: CombatSpellOption, key: ReferenceKey)] = []
    public private(set) var castReleases: [(option: CombatSpellOption, key: ReferenceKey)] = []
    public private(set) var castCancels: [ReferenceKey] = []
    public private(set) var trimRequests = 0
    /// Each kill move an NPC asked for, attacker first.
    public private(set) var killMoveAttempts: [(actor: ReferenceKey, target: ReferenceKey)] = []
    public var playsKillMoves = false
    public private(set) var despawnRequests = 0
    /// True when `recoilMagnitude` was written before `recoilStart` was raised,
    /// which is the write-then-raise order the graph depends on.
    public private(set) var wroteMagnitudeBeforeStagger = false

    public func startCombatKillMove(
        by actor: ReferenceKey, on target: ReferenceKey, damage _: Float, action _: String
    ) -> Bool {
        killMoveAttempts.append((actor: actor, target: target))
        return playsKillMoves
    }

    /// Moves one actor to `feet`, which is what a fake mover that actually
    /// walked would have done by the next step.
    public func place(_ key: ReferenceKey, at feet: SIMD3<Float>) {
        guard let index = actors.firstIndex(where: { $0.key == key }) else { return }
        let previous = actors[index]
        actors[index] = CombatActorObservation(
            key: previous.key,
            feet: feet,
            capsule: previous.capsule,
            heading: previous.heading,
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
            heading: previous.heading,
            scale: previous.scale,
            isDead: true,
            name: previous.name
        )
    }

    public var combatPlayer: MeleeAttacker {
        player
    }

    public func combatActors() -> [CombatActorObservation] {
        actors
    }

    public func combatTemperament(
        of key: ReferenceKey, toward _: ReferenceKey
    ) -> CombatTemperament? {
        temperaments[key]
    }

    public func combatReaction(toPlayerOf key: ReferenceKey) -> ActorReaction? {
        reactions[key]
    }

    public func combatDangerThreats() -> [DangerThreat] {
        dangerThreats
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

    public func combatWearsShield(_ key: ReferenceKey) -> Bool {
        !shieldless.contains(key)
    }

    public func combatShieldRating(of key: ReferenceKey) -> Float? {
        shieldRatings[key]
    }

    public func combatPlayerMelee() -> CombatPlayerMelee? {
        playerMelee
    }

    public func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        blocks[key]
    }

    public func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        pairAwareness[CombatFoePair(observer: observer, target: target)]
            ?? awareness[observer] ?? .unaware
    }

    public func combatHealthFraction(of key: ReferenceKey) -> Float {
        healthFractions[key] ?? 1
    }

    public func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        weapons[key] ?? .unarmed
    }

    public func combatLeftWeapon(of key: ReferenceKey) -> MeleeWeaponProfile? {
        leftWeapons[key]
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
            name == CombatGraphNames.staggerStart,
            variables[CombatGraphNames.staggerMagnitude] != nil
        {
            wroteMagnitudeBeforeStagger = true
        }
        raised.append(name)
        if let target {
            actorEvents.append((name: name, key: target))
        }
        return target == nil
    }

    @discardableResult
    public func fireCombatArrow(_ shot: CombatArrowShot) -> Bool {
        arrowShots.append(shot)
        return true
    }

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

    public func combatInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        influences[key] ?? .none
    }

    public func combatIgnoredByPackage(_ key: ReferenceKey) -> Bool {
        ignoringCombat.contains(key)
    }
}

/// The actor graph reads and writes.
extension FakeCombatWorld {
    public func writeCombatActorVariable(
        _ value: BehaviorVariableValue, named name: String, on actor: ReferenceKey
    ) {
        actorVariables[actor, default: [:]][name] = value
    }
}

extension FakeCombatWorld {
    public func sayCombatWarning(by key: ReferenceKey, to target: ReferenceKey) {
        warningLines.append([key, target])
    }

    public func sayCombatBash(by key: ReferenceKey, to target: ReferenceKey) {
        bashLines.append([key, target])
    }

    public func lookCombatActor(_ key: ReferenceKey, at target: ReferenceKey?, seconds: Float?) {
        looks[key] = AggroLook(target: target, seconds: seconds)
    }

    public func turnCombatActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        turns[key] = point
        guard turnsActors, let index = actors.firstIndex(where: { $0.key == key }) else { return }
        let previous = actors[index]
        let offset = point - previous.feet
        guard offset.x != 0 || offset.y != 0 else { return }
        actors[index] = CombatActorObservation(
            key: previous.key,
            feet: previous.feet,
            capsule: previous.capsule,
            heading: CombatActorObservation.heading(fromYaw: atan2(offset.y, offset.x)),
            scale: previous.scale,
            isDead: previous.isDead,
            name: previous.name
        )
    }

    public func combatAimPoint(
        of shooter: CombatActorObservation, at _: SIMD3<Float>, velocity _: SIMD3<Float>
    ) -> SIMD3<Float>? {
        aimPoints[shooter.key]
    }

    public func combatAggroRadius(of key: ReferenceKey) -> AggroRadius? {
        aggroRadii[key]
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
    }

    public func combatReaction(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> ActorReaction? {
        pairReactions[CombatFoePair(observer: observer, target: target)]
    }

    public func combatIsHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool {
        hostilePairs.contains(CombatFoePair(observer: observer, target: target))
    }

    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        styles[key]
    }

    public func combatIsChild(_ key: ReferenceKey) -> Bool {
        children.contains(key)
    }

    public func combatGraphIsAttackReady(_ actor: ReferenceKey) -> Bool? {
        notAttackReady.contains(actor) ? false : nil
    }

    public func combatIsInKillMove(_ actor: ReferenceKey) -> Bool {
        inKillMove.contains(actor)
    }

    public func combatGraphIsEquipping(_ actor: ReferenceKey) -> Bool {
        equipping.contains(actor)
    }

    public func combatDestructibles(
        within radius: Float,
        of center: SIMD3<Float>
    ) -> [MeleeTarget] {
        destructibles.filter { simd_distance($0.feet, center) <= radius }
    }

    public func damageCombatDestructible(_ object: ReferenceKey, amount: Float) {
        objectDamage[object, default: 0] += amount
    }
}

extension FakeCombatWorld {
    public func combatAssists(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        assistPairs.contains(CombatFoePair(observer: helper, target: ally))
    }

    public func combatIsTeammate(_ key: ReferenceKey) -> Bool {
        teammates.contains(key)
    }

    public func combatMorality(of key: ReferenceKey) -> Float {
        moralities[key] ?? 0
    }

    public func combatCrimeStanding(
        of actor: ReferenceKey, judgedBy helper: ReferenceKey
    ) -> CombatCrimeStanding {
        crimeStandings[CombatFoePair(observer: helper, target: actor)] ?? .clean
    }

    public func combatIsGuard(_ key: ReferenceKey) -> Bool {
        guards.contains(key)
    }

    public func combatAttacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        crimeAttackers.contains(key)
    }
}

/// One head-look call the fake recorded.
public struct AggroLook: Equatable, Sendable {
    public let target: ReferenceKey?
    public let seconds: Float?

    public init(target: ReferenceKey?, seconds: Float?) {
        self.target = target
        self.seconds = seconds
    }
}

/// The race attack, knockdown, and disease reads a blow lands through.
extension FakeCombatWorld {
    public func combatAttacks(of attacker: ReferenceKey) -> [RaceAttack] {
        raceAttacks[attacker] ?? []
    }

    public func combatStamina(of key: ReferenceKey) -> Float? {
        staminas[key]
    }

    public func knockDownCombatTarget(
        _ target: ReferenceKey, from _: SIMD3<Float>, magnitude: Float, staggerMult: Float
    ) {
        knockdowns.append((target, magnitude))
        knockdownStaggerMults.append(staggerMult)
    }

    public func combatAttackDisease(of attacker: ReferenceKey) -> ReferenceKey? {
        attackDiseases[attacker]
    }

    public func combatDiseaseResist(of target: ReferenceKey) -> Float? {
        diseaseResists[target]
    }

    @discardableResult
    public func contractCombatDisease(_ disease: ReferenceKey, on target: ReferenceKey) -> Bool {
        guard !contractedDiseases.contains(where: { $0 == (disease, target) }) else { return false }
        contractedDiseases.append((disease, target))
        return true
    }
}
