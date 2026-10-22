// App side of the AI coordinators: packages, the AI & Navigation panel, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol AIWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
    var actorGraphWorld: ActorGraphWorldAdapter { get }
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var crime: CrimeCoordinator { get }
    var crimeWorld: CrimeWorldAdapter { get }
    var dialogue: DialogueCoordinator { get }
    var dialogueMenu: DialogueMenuController { get }
    var factions: FactionCoordinator { get }
    var headTracking: HeadTrackingCoordinator { get }
    var idleWorld: IdleWorldAdapter { get }
    var inventory: InventoryCoordinator { get }
    var magic: MagicCoordinator { get }
    var npcAnimation: NPCAnimationCoordinator { get }
    var packages: PackageCoordinator { get }
    var perception: PerceptionCoordinator { get }
    var perks: PerkCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var scripts: ScriptCoordinator { get }
    var sessionWiring: WorldSessionWiring { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class AIWorldAdapter {
    unowned let game: any AIWorldHost

    init(game: any AIWorldHost) {
        self.game = game
    }

    func wireAIOverlay(renderer: Renderer, streamer: CellStreamer) {
        renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }

    /// The living actors and the player, for walkers to steer around. Each mover is
    /// dropped from this list by the movement runtime, which knows who walks. A rider
    /// is left out: it takes up its vehicle's space, and a horse must not steer around
    /// the rider in its own saddle.
    func standingActors() -> [NPCNeighbour] {
        let links = game.vehicleWorld.vehicles.core.links
        var actors = game.actorWorld.combatActors().filter {
            !$0.isDead && links[$0.key] == nil
        }.map {
            NPCNeighbour(
                key: $0.key, position: SIMD2($0.feet.x, $0.feet.y),
                radius: $0.capsule.radius * max($0.scale, 0)
            )
        }
        if links[.player] == nil, let feet = game.gameSession?.locomotion.status.feetPosition {
            actors.append(NPCNeighbour(
                key: .player, position: SIMD2(feet.x, feet.y),
                radius: PlayerCapsule.standard.radius
            ))
        }
        return actors
    }

    func wireNPCMovement(gameSession: GameSession, streamer: CellStreamer) {
        streamer.npcMovementConfiguration = gameSession.locomotion.configuration
        let worldState = game.worldState
        let packages = game.packages
        streamer.onNPCMovementPersist = { [weak packages] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            packages?.movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        gameSession.onPlayerWalkArrived = { [weak packages] in
            packages?.movementSettled(actor: .player, reason: .arrival)
        }
        streamer.onNPCPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.npcDeltas = deltas
        }
        streamer.npcStandingActors = { [weak self] in self?.standingActors() ?? [] }
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
        let graphs = game.actorGraphWorld
        streamer.onNPCLocomotionDrive = { [weak animation, weak graphs] update in
            graphs?.drive(update)
            animation?.drive(update)
        }
    }

    func wirePackages(provider: WorldDataStores, gameSession: GameSession) {
        guard let store = provider.packageStore else { return }
        game.packages.guardWarnings = GuardWarningSettings.resolve(store: provider.gameSettings)
        game.packages.wire(store: store)
        game.packages.sandboxSettings = SandboxSettings.resolve(store: provider.gameSettings)
        game.packages.bumpSettings = BumpReactionSettings.resolve(store: provider.gameSettings)
        game.packages.followSettings = FollowSettings.resolve(store: provider.gameSettings)
        let packages = game.packages
        gameSession.worldTick.register(.packages) { [weak self, weak packages] delta in
            packages?.advance(by: Float(delta))
            self?.advanceBumps()
        }
    }

    /// Runs after NPC movement and the combat loop, because the pass reads
    /// where actors ended up this frame and which of them are hostile.
    func wirePerception(provider: WorldDataStores, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let settings = provider.detectionSettings
        let perception = game.perception
        perception.wire(
            settings: settings,
            stealthPoints: StealthPointSettings.resolve(store: provider.gameSettings)
        )
        gameSession.worldTick.register(.perception) { [weak self] delta in
            guard let self else { return }
            run(game.perception.advance(by: delta))
            // After the pass, so a trespass is judged against this frame's detection.
            game.crime.advanceTrespass(by: Double(delta))
            game.crime.advanceReports()
            game.crime.advanceJail()
            // After the trespass, so the guards see a bounty charged this frame.
            game.crimeWorld.run(game.crime.advanceGuardResponse())
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
        game.gameSession?.gameClock
    }

    /// Reads only the store, so it is kept until the next store write.
    private func referenceEnableResolution() -> ReferenceEnableResolution {
        let store = game.worldState
        return store.derived(ReferenceEnableResolution.self, from: store) {
            ReferenceEnableResolution(snapshot: store.snapshot())
        }
    }

    func packageConditionContext(clock: GameClock) -> ConditionContext {
        var context = ConditionContext(
            globals: game.runtimeState.globalResolution(),
            quests: game.scripts.bridge?.questRuntime?.resolution() ?? .empty,
            aliases: game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: game.runtimeStateWorld.actorResolution(),
            detection: game.perception.perceptionResolution(),
            referenceEnable: referenceEnableResolution(),
            clock: clock,
            references: game.streamer?.residentReferenceIndex()
                ?? RuntimeReferenceIndex(entries: [])
        )
        game.runtimeStateWorld.addLiveSeams(to: &context)
        return context
    }
}

extension AIWorldAdapter {
    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        guard actor != .player else { return game.gameSession?.locomotion.status.feetPosition }
        guard let streamer = game.streamer else { return nil }
        if let live = streamer.npcTransform(for: actor) {
            return live.position
        }
        return streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
    }

    /// Only the player's gait is known; an NPC leader moves at its package's pace.
    func packageActorGait(_ actor: ReferenceKey) -> LocomotionGait? {
        actor == .player ? game.gameSession?.locomotion.status.gait : nil
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

    /// Whether the actor stands inside one package location input, by its radius.
    /// An "in cell" input names an interior cell, so it compares cells, not distance.
    func isWithin(_ location: Package.Location, actor: ReferenceKey) -> Bool {
        if location.kind == .inCell, let cell = location.formID {
            return game.streamer?.cellLocation(of: actor) == .interior(cell)
        }
        guard
            let place = packagePlace(of: location, actor: actor, aliasQuest: nil),
            let position = packageActorPosition(actor)
        else { return false }
        return simd_distance(place.point, position) <= Float(max(0, place.radius))
    }

    func packageActorActivity(_ actor: ReferenceKey) -> PackageActorActivity {
        if game.worldState.component(ActorDeathState.self, for: actor)?.isDead == true {
            return .dead
        }
        return game.combat.loop?.phase(of: actor)?.isEngaged == true ? .fighting : .free
    }

    func packageMoverHasRoom(for actor: ReferenceKey) -> Bool {
        actor == .player || game.streamer?.npcMovement.hasRoom(for: actor) ?? true
    }

    func packageActorHoldsIdleMarker(_ actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.holdsMarker(actor)
    }

    func packageSandboxActivityEnded(_ activity: SandboxActivity, actor: ReferenceKey) {
        switch activity {
        case .idleMarker: game.idleWorld.idles.leaveMarker(actor)
        case .wandering: game.idleWorld.idles.allowPreviousMarker(actor)
        default: break
        }
    }

    func movePackageActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool, gait: LocomotionGait?
    ) -> PackageMoveResult {
        if actor == .player {
            return walkPlayer(to: point, direct: direct) ? .started : .failed
        }
        let result = game.streamer?.moveActor(
            actor, to: point, direct: direct, gait: gait,
            runSlowdown: game.packages.followRunSlowdown(for: actor)
        ) ?? .actorNotResident
        game.packages.recordMove(result, for: actor)
        switch result {
        case .started: return .started
        case .moverCapReached: return .busy
        default: return .failed
        }
    }

    /// The player has no NPC mover, so the renderer walks the navmesh path. Without
    /// a path the player walks straight, as a direct move does.
    private func walkPlayer(to point: SIMD3<Float>, direct: Bool) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        let query = NavigationPathQuery(
            start: gameSession.walkController.feetPosition, target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        )
        gameSession.playerWalkIgnoresStatics = direct
        let found = direct ? NavigationPathResult.path(.straight(to: point))
            : game.streamer?.findPath(query) ?? .miss(.disconnected)
        switch found {
        case let .path(path):
            gameSession.playerWalkPath = path.waypoints + [point]
            game.packages.recordMove(.started, for: .player)
        case let .miss(reason):
            gameSession.playerWalkPath = [point]
            game.packages.recordMove(.noPath(reason), for: .player)
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
        guard
            let key = packageTargetKey(start, aliasQuest: aliasQuest),
            let lookup = game.streamer?.placedRecords
        else { return nil }
        let path = lookup.linkedChain(from: key)
        return path.isEmpty ? nil : path
    }

    /// The reference a package's single-reference input names.
    func packageTargetKey(_ target: Package.Target, aliasQuest: FormID?) -> ReferenceKey? {
        switch target.kind {
        case .specificReference:
            game.scripts.bridge?.formIDResolver.flatMap {
                ReferenceKey.resolve(FormID(target.value), using: $0)
            }
        case .referenceAlias:
            aliasQuest.flatMap {
                game.scripts.bridge?.questRuntime?.aliasResolution()
                    .reference(alias: target.value, in: $0)
            }
        default:
            nil
        }
    }

    func packageProcedure(_ event: PackageScriptEvent) {
        game.scripts.bridge?.runPackageFragment(
            of: event.package, slot: event.fragmentSlot, actor: event.actor
        )
        game.scripts.bridge?.queuePackageEvent(
            slot: event.fragmentSlot, package: event.package.formID, actor: event.actor
        )
    }

    private static func placedPosition(_ entry: RuntimeReferenceEntry) -> SIMD3<Float>? {
        entry.placedActor?.placement.position ?? entry.placedReference?.placement.position
    }
}

extension AIWorldAdapter: AINavigationWorld {
    /// The rider's root sits on this node of the horse skeleton (docs/engine/vehicles.md).
    static let saddleBone = "SaddleBone"

    /// The horse a placed actor starts on, `ACHR` `XHOR` (docs/formats/placed-references.md).
    func mountPackageActor(_ rider: ReferenceKey) -> ReferenceKey? {
        guard
            let raw = game.streamer?.placedRecords?.entry(for: rider)?.placedActor?
                .details.links["XHOR"],
            let resolver = game.scripts.bridge?.formIDResolver,
            let horse = ReferenceKey.resolve(raw, using: resolver),
            game.vehicleWorld.vehicles.seat(rider, on: horse, bone: Self.saddleBone)
        else { return nil }
        _ = game.streamer?.stopActor(rider)
        game.npcAnimation.ride(rider, on: horse)
        return horse
    }

    /// The horse walked the rider's package, so it stops with it.
    func dismountPackageActor(_ rider: ReferenceKey) {
        if let horse = vehicleCarrier(of: rider) {
            _ = game.streamer?.stopActor(horse)
        }
        game.vehicleWorld.detach(rider)
        game.npcAnimation.dismount(rider)
    }

    func vehicleCarrier(of actor: ReferenceKey) -> ReferenceKey? {
        game.vehicleWorld.vehicles.core.links[actor]?.carrier
    }

    var isStreaming: Bool {
        game.streamer != nil
    }

    var camera: AICameraPose? {
        game.gameSession.map {
            AICameraPose(position: $0.freeFlyCamera.position, forward: $0.freeFlyCamera.forward)
        }
    }

    func actorCandidates() -> [AIActorCandidate] {
        game.actorWorld.combatActors().map {
            AIActorCandidate(key: $0.key, name: $0.name, feet: $0.feet, isDead: $0.isDead)
        }
    }

    func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit? {
        game.streamer?.nearestCollisionHit(ray: ray)
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
        let readouts = game.packages.readouts().filter { $0.currentPackage != nil }
        let packaged = Set(readouts.map(\.actor))
        let sleepers = Set(readouts.filter { $0.procedure == .sleep }.map(\.actor))
        let isExterior = game.streamer?.interiorScene == nil
        return game.actorWorld.combatActors().map { actor in
            var observer = PerceptionObserver(
                key: actor.key,
                feet: actor.feet,
                eye: actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0)),
                facing: actor.facing,
                isExterior: isExterior,
                label: actor.label,
                sneakSkill: sneakSkill(of: actor.key)
            )
            observer.isSleeping = sleepers.contains(actor.key)
            observer.blindness = blindness(of: actor.key)
            observer.combatTarget = game.combat.loop?.combatTarget(of: actor.key)
            return PerceptionCandidate(
                observer: observer,
                isDead: actor.isDead,
                isHostile: game.factions.hostility(of: actor.key) == .hostile,
                isEngaged: game.combat.loop?.phase(of: actor.key)?.isEngaged == true,
                hasPackage: packaged.contains(actor.key)
            )
        }
    }

    func perceptionTargets() -> [PerceptionTarget] {
        guard let gameSession = game.gameSession else { return [] }
        let status = gameSession.locomotion.status
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
        return !streamer.staticCollisionBlocks(ray: ray)
    }

    func run(_ commands: [PerceptionCommand]) {
        for case let .reportSneakSkillUse(amount, actor) in commands {
            _ = game.progression.reportSkillUse(
                SkillUseEvent(actor: actor, action: .hidden, amount: amount)
            )
        }
    }
}
