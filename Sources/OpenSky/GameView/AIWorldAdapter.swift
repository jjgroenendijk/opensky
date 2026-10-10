// App side of the AI coordinators: packages, the AI & Navigation panel, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

final class AIWorldAdapter {
    unowned let game: GameViewController
    /// The newest package move result per actor, for `state packages`.
    private(set) var lastPackageMoves: [ReferenceKey: NPCMoveCommandResult] = [:]

    init(game: GameViewController) {
        self.game = game
    }

    func wireAIOverlay(renderer: Renderer, streamer: CellStreamer) {
        renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }

    func wireNPCMovement(renderer: Renderer, streamer: CellStreamer) {
        streamer.npcMovementConfiguration = renderer.locomotion.configuration
        let worldState = game.worldState
        let packages = game.packages
        streamer.onNPCMovementPersist = { [weak packages] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            packages?.movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        renderer.onPlayerWalkArrived = { [weak packages] in
            packages?.movementSettled(actor: .player, reason: .arrival)
        }
        streamer.onNPCPosesChanged = { [weak renderer] deltas in
            renderer?.npcInstanceDeltas = deltas
        }
        // A walker drawn by the cell it left would vanish when that cell unloads, so
        // it moves into the cell it entered, and the cell it left drops it.
        streamer.onNPCCellHandoff = { [weak game, weak streamer] persistence in
            guard let cell = persistence.cell, let streamer else { return }
            let drawing = streamer.cellLocation(of: persistence.actor)
            game?.scripts.bridge?.relocate(persistence.actor, to: cell)
            if let drawing, drawing != cell {
                streamer.requestRebuild(of: drawing)
            }
        }
        let animation = game.npcAnimation
        streamer.onNPCLocomotionDrive = { [weak animation] update in
            animation?.drive(update)
        }
    }

    /// Package conditions read the live quest, actor and reference state, so
    /// selection advances after those runtimes in the same world tick.
    func wirePackages(provider: any WorldDataProviding, renderer: Renderer) {
        guard let store = (provider as? PackageDataProviding)?.packageStore else { return }
        game.packages.wire(store: store)
        let packages = game.packages
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak packages] delta in
            advancePreviousSystems?(delta)
            packages?.advance(by: Float(delta))
        }
    }

    /// Runs after NPC movement and the combat loop, because the pass reads
    /// where actors ended up this frame and which of them are hostile.
    func wirePerception(provider: any WorldDataProviding, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.detectionSettings else {
            return
        }
        let perception = game.perception
        let crime = game.crime
        perception.wire(settings: settings)
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak perception, weak crime] delta in
            advanceWorld?(delta)
            perception?.advance(by: delta)
            // After the pass, so a trespass is judged against this frame's detection.
            crime?.advanceTrespass()
            // After the trespass, so the guards see a bounty charged this frame.
            crime?.advanceGuardResponse()
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak perception] context, list in
                perception?.appendWorldOverlay(context: context, to: &list)
            }
    }
}

extension AIWorldAdapter: PackageWorld {
    var packageDrivesPlayer: Bool {
        game.vehicleWorld.isPlayerAIDriven
    }

    func packageResidents() -> [RuntimeReferenceEntry]? {
        guard game.renderer != nil else { return nil }
        return game.streamer?.residentActorEntries()
    }

    var packageClock: GameClock? {
        game.renderer?.gameClock
    }

    func packageConditionContext(clock: GameClock) -> ConditionContext {
        ConditionContext(
            globals: game.runtimeState.globalResolution(),
            quests: game.scripts.bridge?.questRuntime?.resolution() ?? .empty,
            aliases: game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: game.runtimeStateWorld.actorResolution(),
            detection: game.perception.perceptionResolution(),
            referenceEnable: ReferenceEnableResolution(snapshot: game.worldState.snapshot()),
            clock: clock,
            references: game.streamer?.residentReferenceIndex()
                ?? RuntimeReferenceIndex(entries: [])
        )
    }
}

extension AIWorldAdapter {
    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        guard actor != .player else { return game.renderer?.locomotion.status.feetPosition }
        guard let streamer = game.streamer else { return nil }
        if let live = streamer.npcTransform(for: actor) {
            return live.position
        }
        return streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
    }

    /// Places OpenSky can name: a reference, a reference alias, and the actor itself.
    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        let point: SIMD3<Float>? = switch location.kind {
        case .nearReference, .inCell:
            location.formID
                .flatMap { game.streamer?.residentReferenceIndex().entry(for: $0) }
                .flatMap(Self.placedPosition)
        case .referenceAlias:
            aliasQuest
                .flatMap {
                    game.scripts.bridge?.questRuntime?.aliasResolution()
                        .reference(alias: location.value, in: $0)
                }
                .flatMap(packageActorPosition)
        case .nearSelf, .nearPackageStart:
            packageActorPosition(actor)
        case .nearEditorLocation:
            game.streamer?.referenceEntry(key: actor).flatMap(Self.placedPosition)
        default:
            nil
        }
        return point.map { PackagePlace(point: $0, radius: location.radius) }
    }

    func movePackageActor(_ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool) -> Bool {
        if actor == .player {
            return walkPlayer(to: point, direct: direct)
        }
        let result = game.streamer?.moveActor(actor, to: point, direct: direct) ?? .actorNotResident
        lastPackageMoves[actor] = result
        return result == .started
    }

    /// The player has no NPC mover, so the renderer walks the navmesh path. Without
    /// a path the player walks straight, as a direct move does.
    private func walkPlayer(to point: SIMD3<Float>, direct: Bool) -> Bool {
        guard let renderer = game.renderer else { return false }
        let query = NavigationPathQuery(
            start: renderer.walkController.feetPosition, target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        )
        renderer.playerWalkIgnoresStatics = direct
        let found = direct ? NavigationPathResult.path(.straight(to: point))
            : game.streamer?.findPath(query) ?? .miss(.disconnected)
        switch found {
        case let .path(path):
            renderer.playerWalkPath = path.waypoints + [point]
            lastPackageMoves[.player] = .started
        case let .miss(reason):
            renderer.playerWalkPath = [point]
            lastPackageMoves[.player] = .noPath(reason)
        }
        return true
    }

    /// Each running quest's alias packages, the higher-priority quest first.
    func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
        guard let quests = game.scripts.bridge?.questRuntime else { return [:] }
        var stacks: [ReferenceKey: PackageAliasStack] = [:]
        let running = quests.runningQuests().map(\.quest).sorted { $0.priority > $1.priority }
        for quest in running where quest.aliases.contains(where: { !$0.packages.isEmpty }) {
            guard let table = try? quests.aliasState(of: quest.formID) else { continue }
            for alias in quest.aliases where !alias.packages.isEmpty {
                guard let actor = table.reference(forAlias: alias.id), stacks[actor] == nil else {
                    continue
                }
                stacks[actor] = PackageAliasStack(packages: alias.packages, quest: quest.formID)
            }
        }
        return stacks
    }

    func packagePatrolPath(
        from start: Package.Target, actor _: ReferenceKey, aliasQuest: FormID?
    ) -> [SIMD3<Float>]? {
        let key: ReferenceKey? = switch start.kind {
        case .specificReference:
            game.scripts.bridge?.formIDResolver.flatMap {
                ReferenceKey.resolve(FormID(start.value), using: $0)
            }
        case .referenceAlias:
            aliasQuest.flatMap {
                game.scripts.bridge?.questRuntime?.aliasResolution()
                    .reference(alias: start.value, in: $0)
            }
        default:
            nil
        }
        guard let key, let lookup = game.streamer?.placedRecords else { return nil }
        let path = lookup.linkedChain(from: key)
        return path.isEmpty ? nil : path
    }

    func packageProcedure(_ event: PackageScriptEvent) {
        game.scripts.bridge?.runPackageFragment(
            of: event.package, slot: event.fragmentSlot, actor: event.actor
        )
    }

    private static func placedPosition(_ entry: RuntimeReferenceEntry) -> SIMD3<Float>? {
        entry.placedActor?.placement.position ?? entry.placedReference?.placement.position
    }
}

extension AIWorldAdapter: AINavigationWorld {
    /// An estimate: the game seats a rider on the horse's saddle node, which OpenSky
    /// does not read yet.
    private static let riderSeatHeight: Float = 90

    /// The horse a placed actor starts on, `ACHR` `XHOR` (docs/formats/placed-references.md).
    func mountPackageActor(_ rider: ReferenceKey) -> ReferenceKey? {
        guard
            let raw = game.streamer?.placedRecords?.entry(for: rider)?.placedActor?
                .details.links["XHOR"],
            let resolver = game.scripts.bridge?.formIDResolver,
            let horse = ReferenceKey.resolve(raw, using: resolver),
            game.vehicleWorld.vehicles.seat(rider, on: horse, height: Self.riderSeatHeight)
        else { return nil }
        _ = game.streamer?.stopActor(rider)
        return horse
    }

    func dismountPackageActor(_ rider: ReferenceKey) {
        game.vehicleWorld.vehicles.detach(rider)
    }

    func vehicleCarrier(of actor: ReferenceKey) -> ReferenceKey? {
        game.vehicleWorld.vehicles.core.links[actor]?.carrier
    }

    var isStreaming: Bool {
        game.streamer != nil
    }

    var camera: AICameraPose? {
        game.renderer.map {
            AICameraPose(position: $0.freeFlyCamera.position, forward: $0.freeFlyCamera.forward)
        }
    }

    func actorCandidates() -> [AIActorCandidate] {
        game.actorWorld.combatActors().map {
            AIActorCandidate(key: $0.key, name: $0.name, feet: $0.feet, isDead: $0.isDead)
        }
    }

    func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        game.streamer?.collisionCandidates(overlapping: bounds) ?? []
    }

    func residentActor(for reference: FormID) -> ReferenceKey? {
        game.streamer?.residentActorEntries().first { $0.formID == reference }?.key
    }

    func movementReadout(for actor: ReferenceKey) -> NPCMovementReadout? {
        game.streamer?.npcMovementReadouts().first { $0.actor == actor }
    }

    var activeMoverCount: Int {
        game.streamer?.npcMovement.activeMoverCount ?? 0
    }

    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.streamer?.moveActor(actor, to: point) ?? .actorNotResident
    }

    func stopActor(_ actor: ReferenceKey) -> Bool {
        game.streamer?.stopActor(actor) ?? false
    }

    func isHostile(_ actor: ReferenceKey) -> Bool {
        game.factions.hostility(of: actor) == .hostile
    }

    func setHostile(_ hostile: Bool, actor: ReferenceKey) {
        game.factions.setHostility(hostile ? .hostile : .neutral, on: actor)
    }
}

extension AIWorldAdapter: NPCAnimationWorld {
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback? {
        game.actorPlayback(for: actor)
    }

    var animationClips: ActorClipLoader? {
        game.sessionWiring.animationClips
    }
}

extension AIWorldAdapter: PerceptionSessionWorld {
    func perceptionCandidates() -> [PerceptionCandidate] {
        let packaged = Set(game.packages.readouts().filter { $0.currentPackage != nil }
            .map(\.actor))
        let isExterior = game.streamer?.interiorScene == nil
        return game.actorWorld.combatActors().map { actor in
            PerceptionCandidate(
                observer: PerceptionObserver(
                    key: actor.key,
                    feet: actor.feet,
                    eye: actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0)),
                    facing: actor.facing,
                    isExterior: isExterior,
                    label: actor.label,
                    sneakSkill: sneakSkill(of: actor.key)
                ),
                isDead: actor.isDead,
                isHostile: game.factions.hostility(of: actor.key) == .hostile,
                isEngaged: game.combat.loop?.phase(of: actor.key)?.isEngaged == true,
                hasPackage: packaged.contains(actor.key)
            )
        }
    }

    func perceptionTargets() -> [PerceptionTarget] {
        guard let renderer = game.renderer else { return [] }
        let status = renderer.locomotion.status
        let isMoving = simd_length_squared(status.lastPlan.horizontalDisplacement) > 0
        return [PerceptionTarget(
            key: .player,
            feet: status.feetPosition,
            eye: status.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            gait: isMoving ? status.gait : nil,
            isSneaking: status.gait == .sneak,
            traits: playerDetectionTraits(
                at: status.feetPosition, eyeHeight: PlayerCapsule.standard.eyeHeight
            ),
            name: "Player"
        )]
    }

    func perceptionHasLineOfSight(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> Bool {
        guard let streamer = game.streamer else { return true }
        let offset = destination - origin
        let distance = simd_length(offset)
        guard
            distance.isFinite, distance > 0,
            let ray = InteractionRay(origin: origin, direction: offset, maximumDistance: distance)
        else { return true }
        let shapes = streamer.staticCollisionCandidates(overlapping: ray.bounds)
        return InteractionRaycaster.nearestHit(ray: ray, shapes: shapes) == nil
    }
}
