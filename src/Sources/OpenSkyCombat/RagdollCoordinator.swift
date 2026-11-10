// The shell of death and ragdoll: owns the runtime and the ragdoll definitions,
// sweeps resident actors for zero health, and publishes the simulated poses.
// The runtime resolves through this coordinator. See docs/engine/ragdoll.md.

public import OpenSkyActorsInterface
import OpenSkyBehavior
public import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyWorldState
import simd

/// Owns the ragdoll runtime and reads the world through `RagdollSessionWorld`.
public final class RagdollCoordinator {
    /// Decodes the ragdoll one skeleton `.nif` carries, at one scale.
    typealias DefinitionLoader = (
        _ skeletonMeshPath: String, _ skeleton: HKASkeleton, _ scale: Float
    ) -> RagdollDefinition?

    /// Nil without game data. The readout then reports itself unavailable.
    public private(set) var runtime: RagdollRuntime?
    let world: any RagdollSessionWorld
    /// Whether the scene holds poses from this coordinator, so an empty frame clears them once.
    var hasPublishedPoses = false
    /// Whether the player body holds a ragdoll pose, so its end clears it once.
    var hasPublishedPlayerRagdoll = false
    let store: WorldStateStore
    private let loadDefinition: DefinitionLoader?
    /// Keyed by path and scale: a definition bakes the scale into every pivot,
    /// so a giant and a Nord cannot share one.
    private var definitions: [String: RagdollDefinition] = [:]
    /// Keys that produced no ragdoll, so they are not decoded once per frame.
    private var unresolvableSkeletons: Set<String> = []
    /// The install's death settings.
    public let deathSettings: DeathSettings
    /// Seconds of simulated time since wiring, the clock of hits and deaths.
    var clock: Float = 0
    /// Each actor's last landed hit and when it landed.
    var recentHits: [ReferenceKey: (hit: CombatHitRecord, time: Float)] = [:]
    /// The push of a death in progress, read when the ragdoll spawns, which waits
    /// for the death graph's hand-off.
    var deathImpulses: [ReferenceKey: SIMD3<Float>] = [:]
    /// Each cut head of a resident body, falling or at rest.
    public internal(set) var severedHeads: [ReferenceKey: SeveredHead] = [:]
    /// Whether the scene holds cut-head poses, so an empty frame clears them once.
    var hasPublishedHeads = false
    /// The simulated bones each corpse was last drawn with, so a cut starts where the
    /// body lies even when its ragdoll is gone or restarts.
    var drawnRagdollBones: [ReferenceKey: [String: float4x4]] = [:]
    /// When each dead actor died, or was first seen dead.
    var deathTimes: [ReferenceKey: Float] = [:]
    var deathRandom = ConditionRandom()
    /// Essential and protected actors kneeling at zero health.
    var bleedout = BleedoutTracker()
    public internal(set) var deathEffects = DeathEffectCounts()
    /// The player's own zero health. The app steps it each world tick.
    public var playerDeath = PlayerDeath()
    /// Living actors on the ground after a knock.
    public internal(set) var knockdowns = KnockdownTracker()
    /// Knockdown commands raised between frames, run with the next frame's.
    var queuedKnockdownCommands: [RagdollCommand] = []

    public init(store: WorldStateStore, world: any RagdollSessionWorld, data: RagdollSessionData?) {
        self.store = store
        self.world = world
        loadDefinition = data?.loadDefinition
        deathSettings = data?.deathSettings ?? .vanilla
        playerDeath = PlayerDeath(settings: deathSettings)
        if data != nil {
            runtime = RagdollRuntime(seam: self)
        }
    }

    /// One frame: zero-health actors die, `events` hand off, live ragdolls step.
    /// The caller drains `events` every frame, so no backlog builds up.
    /// - Returns: a murder report for each actor that died.
    public func advance(
        events: [String], controls: RagdollGraphControls, delta: Float
    ) -> [RagdollCommand] {
        guard let runtime else { return [] }
        clock += max(delta.isFinite ? delta : 0, 0)
        runtime.retainRagdolls(in: world.residentRagdollCells)
        let recoveries = recoverFromBleedout(delta: delta)
        let murders = killZeroHealthActors(runtime: runtime)
        removeExcessDead(runtime: runtime)
        for key in runtime.pendingHandOffs.sorted() {
            runtime.handleGraphEvents(events, on: key)
        }
        // A graph-driven death spawns its ragdoll frames later; keep its push until then.
        deathImpulses = deathImpulses.filter { runtime.pendingHandOffs.contains($0.key) }
        runtime.blendDuration = controls.blendDuration
            ?? HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration
        runtime.motor = controls.powered.map(RagdollMotor.init)
        runtime.contactEvent = controls.contactEvent
        runtime.advance(by: delta)
        advanceSeveredHeads(by: delta)
        return recoveries + murders + advanceKnockdowns(delta: delta, runtime: runtime)
    }

    /// Rebuilt each frame, so a corpse whose cell unloaded stops being drawn as
    /// a ragdoll once its instance is gone.
    public func publishPoses() -> [RagdollCommand] {
        guard let runtime else { return [] }
        var commands: [RagdollCommand] = []
        let heads = severedHeadPoses()
        if !heads.isEmpty || hasPublishedHeads {
            commands.append(.publishSeveredHeads(heads))
            hasPublishedHeads = !heads.isEmpty
        }
        let hasPlayer = runtime.world.isRagdolling(.player)
        if hasPlayer || hasPublishedPlayerRagdoll {
            let bones = hasPlayer ? simulatedBones(of: .player, in: runtime) ?? [:] : [:]
            commands.append(.publishPlayerRagdoll(bones))
            hasPublishedPlayerRagdoll = !bones.isEmpty
        }
        let actors = runtime.world.ragdolls.filter { $0.key != .player }
        guard !actors.isEmpty || hasPublishedPoses else { return commands }
        var poses: [UInt32: [String: float4x4]] = [:]
        for entry in actors {
            guard
                let reference = ragdollActor(for: entry.key)?.reference,
                let bones = simulatedBones(of: entry.key, in: runtime)
            else { continue }
            poses[reference.rawValue] = bones
        }
        hasPublishedPoses = !poses.isEmpty
        return commands + [.publishPoses(poses)]
    }

    private func simulatedBones(
        of key: ReferenceKey, in runtime: RagdollRuntime
    ) -> [String: float4x4]? {
        guard
            let instance = runtime.world.ragdolls.first(where: { $0.key == key })?.instance,
            let actor = ragdollActor(for: key),
            let animated = world.animatedPose(of: key)
        else { return nil }
        let weight = knockdowns.ragdollWeight(of: key).map { min($0, instance.simulationWeight) }
        let bones = instance.blendedBoneMatrices(
            animated: animated, worldToActor: actor.actorToWorld.inverse, weight: weight
        )
        drawnRagdollBones[key] = bones
        return bones
    }

    /// The dead player's body falls as an NPC's does, pushed by the killing hit.
    public func dropPlayerBody() {
        guard let runtime else { return }
        if let hit = recentHit(on: .player), let feet = world.playerFeetPosition {
            let resident = RagdollResident(key: .player, position: feet)
            deathImpulses[.player] = impulse(of: hit, on: resident)
        }
        runtime.startFall(of: .player)
    }

    /// A load or the main menu brings the player back: alive, and off the floor.
    public func resetPlayerDeath() {
        playerDeath.reset()
        runtime?.removeRagdoll(.player)
        deathImpulses[.player] = nil
    }

    /// A sweep, not a hook, because health reaches zero from several places.
    /// `noteZeroHealth(of:)` is true only for the call that killed the actor,
    /// so each murder is reported once. The last hit names the killer and pushes the body.
    private func killZeroHealthActors(runtime: RagdollRuntime) -> [RagdollCommand] {
        var murders: [RagdollCommand] = []
        for resident in world.ragdollResidents {
            let key = resident.key
            guard !runtime.isDead(key) else { continue }
            guard world.hasZeroHealth(key) else {
                murders += kneelBelowThreshold(key)
                continue
            }
            let hit = recentHit(on: key)
            switch world.zeroHealthOutcome(of: key, killer: hit?.attacker) {
            case .deferred:
                continue
            case .bleedsOut:
                if bleedout.enter(key) {
                    murders.append(.enterBleedout(key))
                }
                continue
            case .dies:
                bleedout.remove(key)
            }
            deathImpulses[key] = hit.map { impulse(of: $0, on: resident) }
            guard runtime.noteZeroHealth(of: key, killer: hit?.attacker) else { continue }
            murders.append(.reportMurder(key))
            applyDeathEffects(of: hit, to: key)
        }
        return murders
    }

    /// An essential or protected actor kneels once its health share falls to its ratio,
    /// before its health reaches zero.
    private func kneelBelowThreshold(_ key: ReferenceKey) -> [RagdollCommand] {
        guard
            !bleedout.contains(key), let fraction = world.healthFraction(of: key),
            // A healthy actor skips the threshold lookup, which reads its records.
            fraction < 1,
            fraction <= world.bleedoutThreshold(of: key) ?? deathSettings.bleedoutThreshold,
            world.zeroHealthOutcome(of: key, killer: recentHit(on: key)?.attacker) == .bleedsOut,
            bleedout.enter(key)
        else { return [] }
        return [.enterBleedout(key)]
    }

    /// An actor whose cell unloaded stands up at once, so it does not kneel forever.
    private func recoverFromBleedout(delta: Float) -> [RagdollCommand] {
        let resident = Set(world.ragdollResidents.map(\.key))
        let unloaded = bleedout.seconds.keys.filter { !resident.contains($0) }.sorted()
        for key in unloaded {
            bleedout.remove(key)
        }
        let regen = deathSettings.bleedoutRegenPercent / 100 * max(delta, 0)
        for key in bleedout.seconds.keys.sorted() where regen > 0 {
            world.restoreHealthShare(regen, of: key)
        }
        let recovered = bleedout.advance(
            by: delta, settings: deathSettings,
            held: { world.blocksBleedoutRecovery(of: $0) },
            recovered: { key in
                let ratio = world.bleedoutThreshold(of: key) ?? deathSettings.bleedoutThreshold
                let share = world.healthFraction(of: key) ?? 0
                return share >= ratio + deathSettings.bleedoutRecoverMargin
            }
        )
        return (unloaded + recovered).map { .leaveBleedout($0) }
    }

    func definition(for pose: RagdollActorPose) -> RagdollDefinition? {
        let path = pose.skeletonMeshPath
        guard !path.isEmpty else { return nil }
        let cacheKey = "\(path)@\(pose.scale)"
        guard !unresolvableSkeletons.contains(cacheKey) else { return nil }
        if let cached = definitions[cacheKey] {
            return cached
        }
        guard let definition = loadDefinition?(path, pose.skeleton, pose.scale) else {
            unresolvableSkeletons.insert(cacheKey)
            return nil
        }
        definitions[cacheKey] = definition
        return definition
    }

    static func definitionLoader(_ library: NIFCollisionLibrary) -> DefinitionLoader {
        { path, skeleton, scale in
            guard
                let model = attempt({ try library.model(path: path) }),
                let bind = attempt({
                    try SkeletonPoseMath.worldMatrices(
                        skeleton: skeleton, localPoses: skeleton.referencePose
                    )
                })
            else { return nil }
            return RagdollDefinition(
                model: model, boneNames: skeleton.boneNames, bindMatrices: bind, scale: scale
            )
        }
    }
}

extension RagdollCoordinator: RagdollWorldSeam {
    public func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        guard
            let pose = world.ragdollPose(of: key),
            let definition = definition(for: pose)
        else { return nil }
        return RagdollActor(
            key: key,
            cell: pose.cell,
            reference: pose.reference,
            definition: definition,
            animatedBoneMatrices: pose.animatedBoneMatrices,
            actorToWorld: pose.actorToWorld,
            impulse: deathImpulses[key] ?? .zero
        )
    }

    /// Only the player has a graph, so every NPC death takes the fallback.
    @discardableResult
    public func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        guard key == .player else { return false }
        return world.raisePlayerGraphEvent(name)
    }

    public var ragdollStepWorld: DynamicStepWorld {
        world.ragdollStepWorld
    }

    public func writeDeathState(
        _ state: ActorDeathState,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    ) {
        store.set(state, for: key, in: cell)
    }

    public func deathState(of key: ReferenceKey) -> ActorDeathState? {
        store.component(ActorDeathState.self, for: key)
    }

    @discardableResult
    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        world.queueActorDeathEvents(for: key, killer: killer)
    }

    public func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation? {
        world.unloadedActorHome(of: key)
    }
}

/// What the ragdoll coordinator is built from. Without collision models nothing
/// can ragdoll, but deaths still record.
public struct RagdollSessionData {
    let loadDefinition: RagdollCoordinator.DefinitionLoader?
    let deathSettings: DeathSettings

    public init(collisionModels: NIFCollisionLibrary?, deathSettings: DeathSettings = .vanilla) {
        self.init(
            loadDefinition: collisionModels.map(RagdollCoordinator.definitionLoader),
            deathSettings: deathSettings
        )
    }

    init(
        loadDefinition: RagdollCoordinator.DefinitionLoader?,
        deathSettings: DeathSettings = .vanilla
    ) {
        self.loadDefinition = loadDefinition
        self.deathSettings = deathSettings
    }
}

extension RagdollCoordinator {
    public func advancePlayerDeath(
        by delta: Float, health: PlayerHealthSample
    ) -> [PlayerDeathCommand] {
        playerDeath.advance(by: delta, health: health)
    }
}
