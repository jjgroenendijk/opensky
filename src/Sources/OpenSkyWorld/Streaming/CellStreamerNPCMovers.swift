// The NPC movement engine of the cell streamer: path starts, the per-frame movers,
// and the rest writes they emit.

import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension CellNPCMovers {
    /// A `direct` move walks the straight line to `point` on the terrain, without a
    /// navmesh path or static collision. `walkRunBlend` sets a speed from walk to run.
    @discardableResult
    public func moveActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false,
        gait: LocomotionGait? = nil, runSlowdown: FollowSettings? = nil,
        walkRunBlend: Float? = nil
    ) -> NPCMoveCommandResult {
        guard
            let entry = streamer.residents.referenceEntry(key: actor),
            entry.placedActor != nil
        else {
            return .actorNotResident
        }
        let standing = streamer.actors.npcMovement.standingTransform(
            of: entry,
            in: streamer.stateSource()
        )
        let result = direct ? .path(.straight(to: point)) : streamer.navigation
            .findPath(NavigationPathQuery(
                start: standing.position,
                target: point,
                capsuleRadius: PlayerCapsule.standard.radius
            ))
        let swim = streamer.npcMovementState.swimBreadcrumbs.trail(
            from: standing.position,
            to: point
        )
        let found: NavigationPath? = if case let .path(path) = result {
            path
        } else {
            swim.map(NavigationPath.through)
        }
        guard let path = found else {
            guard case let .miss(reason) = result else { return .noPath(.disconnected) }
            return .noPath(reason)
        }
        let bounds = streamer.npcMovementState.bodyHalfExtents?(actor)
        var start = NPCMoveStart(
            actor: actor,
            formID: entry.formID,
            placement: standing.placement,
            scale: standing.scale,
            capsule: bounds.flatMap { .upright(halfExtents: $0, scale: standing.scale) }
                ?? .standard,
            configuration: streamer.actors.npcMovementConfiguration,
            path: path,
            ignoresStatics: direct,
            gait: gait
        )
        start.runSlowdown = runSlowdown
        start.walkRunBlend = walkRunBlend
        start.longBody = bounds.flatMap { LongBodyShape(halfExtents: $0, scale: standing.scale) }
        let started = streamer.actors.npcMovement.start(start)
        return started ? .started : .moverCapReached
    }

    func advanceNPCMovement(frameTime: Float) {
        bindNPCMovementCallbacks()
        holdingRests { advanceMovers(frameTime: frameTime) }
        bakeBuiltRests()
        streamer.actors.onNPCPosesChanged?(streamer.actors.npcMovement.instanceDeltas())
    }

    /// Runs `body`, then delivers the rest writes it emitted, once the runtime holds
    /// its result.
    func holdingRests<T>(_ body: () -> T) -> T {
        streamer.npcMovementState.heldRests = []
        let result = body()
        let rests = streamer.npcMovementState.heldRests ?? []
        streamer.npcMovementState.heldRests = nil
        rests.forEach(deliverRest)
        return result
    }

    private func advanceMovers(frameTime: Float) {
        streamer.actors.npcMovement.advance(by: frameTime, world: NPCMovementWorld(
            sampleGround: { [weak streamer] position in
                streamer?.collision.sampleTerrain(at: position)
            },
            collisionQuery: { [weak streamer] bounds in
                streamer?.collision.characterCollisionCandidates(overlapping: bounds) ?? []
            },
            repath: { [weak streamer] query in
                streamer?.navigation.findPath(query) ?? .miss(.disconnected)
            },
            cellAt: { [weak streamer] position in
                streamer?.actors.movers.navigationCell(at: position)
            },
            triggersAt: { [weak streamer] state in
                Set(streamer?.triggers.triggerVolumes(intersecting: state).map(\.reference) ?? [])
            },
            hasGround: { [weak streamer] position in
                streamer?.interiorScene != nil || streamer?.collision
                    .sampleTerrain(at: position) != nil
            },
            standingActors: { [weak streamer] in streamer?.actors.npcStandingActors?() ?? [] },
            sampleWater: { [weak streamer] position in streamer?.collision.water(at: position) },
            waterPushRace: { [weak streamer] actor in
                streamer?.actors.npcWaterPushRace?(actor) ?? .normal
            },
            vehicleActors: streamer.npcMovementState.vehicleLinkedActors,
            collisionQueryIgnoringVehicles: { [weak streamer] bounds in
                streamer?.collision.collisionCandidatesIgnoringVehicles(overlapping: bounds) ?? []
            },
            movementSpeeds: { [weak streamer] actor in
                streamer?.npcMovementState.movementSpeeds?(actor)
            }
        ))
    }

    /// Called from `noteStateMutation` while a rest write is in progress. The actor
    /// already draws at that pose, so the write rebuilds nothing; a later build of
    /// its cell bakes it in. Returns false when no rest write is in progress.
    func noteNPCRestMutation(sequence: UInt64) -> Bool {
        guard let rest = streamer.npcMovementState.recordingRest else { return false }
        if let cell = streamer.residents.cellLocation(of: rest.actor) {
            streamer.npcMovementState.unbakedRests[rest.actor, default: []].append(NPCUnbakedRest(
                sequence: sequence, placement: rest.transform.placement, drawingCell: cell
            ))
        }
        return true
    }

    /// Moves each actor's draw base to the newest rest its cell's resident build holds.
    private func bakeBuiltRests() {
        for actor in streamer.npcMovementState.unbakedRests.keys.sorted() {
            guard
                var rests = streamer.npcMovementState.unbakedRests[actor],
                let cell = rests.last?.drawingCell,
                let built = residentStateSequence(at: cell),
                let baked = rests.lastIndex(where: { $0.sequence <= built })
            else { continue }
            streamer.actors.npcMovement.bake(actor, at: rests[baked].placement)
            rests.removeSubrange(...baked)
            streamer.npcMovementState.unbakedRests[actor] = rests.isEmpty ? nil : rests
        }
    }

    private func residentStateSequence(at location: CellSceneLocation) -> UInt64? {
        switch location {
        case let .exterior(coordinate):
            return streamer.composition.cells[coordinate]?.stateSequence
        case .interior:
            guard
                let interiorScene = streamer.interiorScene,
                interiorScene.location == location else { return nil }
            return interiorScene.stateSequence
        }
    }

    func navigationCell(at position: SIMD3<Float>) -> CellSceneLocation? {
        streamer.navigation.reconcileNavigation()
        return streamer.navigationState.graph.cell(at: position)
    }

    private func deliverRest(_ persistence: NPCMovementPersistence) {
        streamer.npcMovementState.recordingRest = persistence
        streamer.actors.onNPCMovementPersist?(persistence)
        streamer.npcMovementState.recordingRest = nil
        if persistence.reason == .cellHandoff {
            streamer.actors.onNPCCellHandoff?(persistence)
        }
    }

    public func bindNPCMovementCallbacks() {
        streamer.actors.npcMovement.onDrive = { [weak streamer] update in
            streamer?.actors.onNPCLocomotionDrive?(update)
        }
        streamer.actors.npcMovement.onPersist = { [weak streamer] persistence in
            guard let streamer else { return }
            if streamer.npcMovementState.heldRests != nil {
                streamer.npcMovementState.heldRests?.append(persistence)
            } else {
                deliverRest(persistence)
            }
        }
        streamer.actors.npcMovement.onTriggerTransition = { [weak streamer] event in
            streamer?.events.onTriggerTransition(event)
        }
        streamer.actors.npcMovement.onDoorCrossing = { [weak streamer] actor, door in
            streamer?.actors.onNPCDoorCrossing?(actor, door)
        }
        streamer.actors.npcMovement.onLanding = { [weak streamer] actor, landing in
            streamer?.actors.onNPCLanding?(actor, landing)
        }
    }
}
