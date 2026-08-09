// The perception-and-combat half of the M16 real-data gate (issue #203), as a
// small world both runtimes share.
//
// Separate from `M16AcceptanceRealDataTests` for the strict-lint type-length
// cap, and separate from `M16AcceptanceChain` because the two answer different
// questions: the synthetic chain drives navigation, packages, perception and
// combat together over invented geometry, while this drives perception and
// combat alone over *vanilla constants* at a position the real mover produced.
// Sharing one harness would mean the real-data gate carried a synthetic navmesh
// it never uses.
//
// Nothing here reads the install directly. It is handed the resolved settings
// and the arrival position, which is what keeps the record-reading in one place.

@testable import opensky
import simd

@MainActor
final class M16RealDataFight {
    let perception: PerceptionRuntime
    let combat: CombatLoopRuntime
    let actor: ReferenceKey

    var actorFeet: SIMD3<Float>
    var playerFeet = SIMD3<Float>()
    var blockSight = false
    var health: Float = 1

    private(set) var packageResumes: [ReferenceKey] = []
    private(set) var visitedPhases: Set<CombatBehaviorPhase> = []
    private(set) var stepCount = 0
    private var hostility: [ReferenceKey: ActorHostility] = [:]

    init(
        detection: DetectionSettings,
        combat settings: CombatSettings,
        actor: ReferenceKey,
        actorFeet: SIMD3<Float>
    ) {
        self.actor = actor
        self.actorFeet = actorFeet
        perception = PerceptionRuntime(settings: detection)
        combat = CombatLoopRuntime(settings: settings)
        combat.behaviorSettings = .quick
        perception.attach(world: self)
        combat.attach(world: self)
    }

    var phase: CombatBehaviorPhase? {
        combat.phase(of: actor)
    }

    var detectionState: DetectionState {
        perception.state(observer: actor, target: .player).state
    }

    func setHostile(_ hostile: Bool) {
        combat.setHostility(hostile ? .hostile : .neutral, on: actor)
    }

    /// One fixed step of both clocks, combat first so perception describes the
    /// world the fight left behind — the same order the app advances them in.
    func frame() {
        stepCount += 1
        combat.advance(by: CombatLoopRuntime.fixedStepSeconds)
        perception.advance(by: CombatLoopRuntime.fixedStepSeconds)
        if let phase {
            visitedPhases.insert(phase)
        }
    }

    @discardableResult
    func run(frames: Int, until: () -> Bool) -> Bool {
        for _ in 0 ..< frames {
            if until() {
                return true
            }
            frame()
        }
        return until()
    }
}

extension M16RealDataFight: PerceptionWorld {
    func perceptionObservers() -> [PerceptionObserver] {
        [PerceptionObserver(
            key: actor, feet: actorFeet, facing: 0, isExterior: false, name: "Resident"
        )]
    }

    func perceptionTargets() -> [PerceptionTarget] {
        [PerceptionTarget(key: .player, feet: playerFeet, gait: .run, name: "Player")]
    }

    func perceptionHasLineOfSight(from _: SIMD3<Float>, to _: SIMD3<Float>) -> Bool {
        !blockSight
    }
}

extension M16RealDataFight: CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        MeleeAttacker(key: .player, feet: playerFeet, facing: 0)
    }

    func combatActors() -> [CombatActorObservation] {
        [CombatActorObservation(key: actor, feet: actorFeet, name: "Resident")]
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        return true
    }

    @discardableResult
    func applyCombatDamage(_: Float, to _: ReferenceKey) -> Bool {
        true
    }

    func combatBlock(of _: ReferenceKey) -> MeleeBlockKind? {
        nil
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        let pair = perception.state(observer: observer, target: target)
        return CombatAwareness(state: pair.state, lastKnownPosition: pair.lastKnownPosition)
    }

    func combatHealthFraction(of _: ReferenceKey) -> Float {
        health
    }

    func combatWeapon(of _: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    /// No navmesh here, so the actor walks straight at whatever it was told to
    /// go to. The corridor half of the gate is the mover's own step over the
    /// real navmesh, which ran before this one and is asserted there.
    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        guard key == actor else { return false }
        actorFeet = point
        return true
    }

    func stopCombatMovement(of _: ReferenceKey) {}

    func resumeCombatPackage(for key: ReferenceKey) {
        packageResumes.append(key)
    }

    @discardableResult
    func raiseCombatEvent(_: String, on _: ReferenceKey?) -> Bool {
        false
    }

    @discardableResult
    func playCombatClip(_: CombatActorClip, on _: ReferenceKey) -> Bool {
        true
    }

    func writeCombatVariable(_: BehaviorVariableValue, named _: String) {}

    var combatTransients: CombatTransientCounts {
        .none
    }

    @discardableResult
    func trimCombatTransients(to _: CombatTransientLimits) -> CombatTransientCounts {
        CombatTransientCounts()
    }

    func despawnCombatTransients() {}

    func setCombatMusicActive(_: Bool) {}
}
