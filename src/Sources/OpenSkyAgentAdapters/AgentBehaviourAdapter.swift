import Foundation
import OpenSkyActorPresentation
public import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentBehaviourAdapter` reads from the session.
@MainActor
public protocol AgentBehaviourHost: AnyObject, SendableMetatype {
    var actorGraphs: any ActorGraphPort { get }
    var aiWorld: any AIWorldPort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var menuScreensWorld: any MenuScreensWorldPort { get }
    var packages: any PackagePort { get }
    var renderer: (any RendererPort)? { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentBehaviourAdapter {
    public let hub: AgentHub
    public let game: any AgentBehaviourHost
}

extension AgentBehaviourAdapter {
    func packagesState(reference: String) throws(AgentFailure) -> AgentJSON {
        try packageReadout.packagesState(reference: reference)
    }

    func playPaired(
        _ reference: String, target: String, idle editorID: String
    ) throws(AgentFailure) -> AgentJSON {
        let lead = try hub.resolveReference(reference)
        let partner = try hub.resolveReference(target)
        let idles = game.idleWorld.idles
        guard let idle = idles.store?.idles.record(editorID: editorID) else {
            throw AgentFailure(.notFound, "no idle '\(editorID)'")
        }
        let report = idles.fireIdle(
            idle.id, on: lead.key, target: partner.key, ignoringConditions: true
        )
        return [
            "idle": .string(editorID), "chosen": AgentJSON(report?.chosen),
            "failure": AgentJSON(report?.failure), "pairs": pairsJSON()
        ]
    }

    func pairedState() -> AgentJSON {
        ["pairs": pairsJSON()]
    }

    private func pairsJSON() -> AgentJSON {
        .array(game.idleWorld.idles.pairs.map { play in
            [
                "idle": .string(play.idle), "event": .string(play.event),
                "killMove": .bool(play.isKillMove),
                "partnerTookEvent": .bool(play.partnerTookEvent),
                "partnerAtMark": .bool(play.isAtMark),
                "lead": actorJSON(play.lead), "partner": actorJSON(play.partner)
            ]
        })
    }

    /// The paired clips the actor's graph sampled, as the track prefix, `|`, and the clip.
    private func actorJSON(_ key: ReferenceKey) -> AgentJSON {
        let graph = key == .player
            ? game.gameSession?.locomotion.graph
            : game.actorGraphs.instance(of: key)
        return [
            "ref": .string("\(key)"),
            "clips": .array((graph?.pairedClipNames ?? []).map { .string($0) }),
            "getToMarkTime": graph?.synchronizedMark.map { .number(Double($0.getToMarkTime)) }
                ?? .null
        ]
    }

    public func performFurniture(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .sit(reference, furniture): return try sit(reference, in: furniture)
        case let .stand(reference):
            let actor = try hub.resolveReference(reference)
            return [
                "ref": .formID(actor.formID.rawValue),
                "stood": .bool(game.furniture.stand(actor.key))
            ]
        case let .passTime(hours, sleeping):
            guard game.gameSession != nil
            else { throw AgentFailure(.notReady, "no world is loaded") }
            game.menuScreensWorld.passTime(hours: hours, sleeping: sleeping)
            return ["hours": .init(hours), "sleeping": .bool(sleeping)]
        default:
            throw AgentFailure(.invalidArgument, "not a furniture command")
        }
    }

    func furnitureState(reference: String) throws(AgentFailure) -> AgentJSON {
        let target = try hub.resolveReference(reference)
        let furniture = game.furniture
        if let seats = game.aiWorld.furnitureSeats(of: target.key), !seats.isEmpty {
            let holders = furniture.ledger.holders(of: target.key)
            let rules = seats[0].rules
            return [
                "ref": .formID(target.formID.rawValue),
                "rules": [
                    "childCanUse": .bool(rules.childCanUse),
                    "mustExitToTalk": .bool(rules.mustExitToTalk),
                    "perch": .bool(rules.isPerch),
                    "ignoredBySandbox": .bool(rules.ignoredBySandbox),
                    "spell": rules.associatedSpell.map { .formID($0.rawValue) } ?? .null
                ],
                "markers": .array(seats.indices.map { index in
                    let seat = seats[index]
                    return [
                        "index": .init(index), "type": .init(Int(seat.animationType)),
                        "enabled": .bool(seat.isEnabled), "entries": .init(Int(seat.entryPoints)),
                        "position": .init(seat.position), "root": .init(seat.root),
                        "heading": .init(seat.heading),
                        "holder": holders[index].map { .string("\($0)") } ?? .null,
                        "inUse": .bool(furniture.isInUse(
                            target.key,
                            marker: index,
                            ignoringReserved: true
                        ))
                    ]
                })
            ]
        }
        let occupancy = furniture.occupancies[target.key]
        let use = game.idleWorld.idles.furnitureResolution.uses[target.key]
        return [
            "ref": .formID(target.formID.rawValue),
            "sitState": .init(Int(use?.sitState.rawValue ?? 0)),
            "furniture": occupancy.flatMap { formID(of: $0.seat.furniture) } ?? .null,
            "marker": occupancy.map { .init($0.seat.index) } ?? .null,
            "entry": occupancy.map { .init(Int($0.entry)) } ?? .null,
            "sittingRotation": .init(furniture.sittingRotation),
            "leaving": .bool(furniture.isLeavingSeat(target.key)),
            "idle": idleReport(of: target.key),
            "position": game.aiWorld.furnitureActorPosition(target.key).map { .init($0) } ?? .null
        ]
    }

    private func sit(
        _ reference: String,
        in furnitureText: String?
    ) throws(AgentFailure) -> AgentJSON {
        let actor = try hub.resolveReference(reference)
        let furniture: ReferenceKey
        if let furnitureText {
            furniture = try hub.resolveReference(furnitureText).key
        } else {
            guard let nearest = game.furniture.nearestFurniture(to: actor.key) else {
                throw AgentFailure(.notFound, "no loaded furniture has a free seat")
            }
            furniture = nearest
        }
        switch game.furniture.use(furniture, by: actor.key) {
        case let .success(occupancy):
            return [
                "ref": .formID(actor.formID.rawValue),
                "furniture": formID(of: occupancy.seat.furniture) ?? .null,
                "marker": .init(occupancy.seat.index), "entry": .init(Int(occupancy.entry))
            ]
        case let .failure(refusal):
            throw AgentFailure(.failed, "the actor cannot sit: \(refusal.rawValue)")
        }
    }

    /// The last idle the actor played, such as its furniture entry or exit idle.
    private func idleReport(of actor: ReferenceKey) -> AgentJSON {
        guard let report = game.idleWorld.idles.lastReport(of: actor) else { return .null }
        return [
            "chosen": report.chosen.map { .string($0) } ?? .null,
            "failure": report.failure.map { .string($0) } ?? .null,
            "seconds": report.seconds.isFinite ? .init(report.seconds) : .string("held"),
            "rootMotion": .bool(report.plan?.rootMotion != nil)
        ]
    }

    func formID(of key: ReferenceKey) -> AgentJSON? {
        game.streamer.referenceEntry(key: key).map { .formID($0.formID.rawValue) }
    }
}

extension AgentBehaviourAdapter {
    var packageReadout: AgentPackageReadout {
        AgentPackageReadout(hub: hub, game: game)
    }
}

struct AgentPackageReadout {
    let hub: AgentHub
    let game: any AgentBehaviourHost

    func packagesState(reference: String) throws(AgentFailure) -> AgentJSON {
        let key = try hub.resolveReference(reference).key
        let readout = game.packages.readout(for: key)
        let execution = game.packages.executions[key]?.readout
        let mover = game.streamer.npcMovementReadouts().first { $0.actor == key }
        let links = game.vehicleWorld.vehicles.core.links
        return [
            "package": readout?.editorID.map(AgentJSON.string) ?? .null,
            "procedure": readout?.procedure.map { .string("\($0)") } ?? .null,
            "evaluatedAt": readout?.lastEvaluationGameSeconds
                .map { unsafe .string(String(format: "%.1f", $0)) } ?? .null,
            "override": readout?.override.map { .string("\($0)") } ?? .null,
            "state": execution?.state.map(AgentJSON.string) ?? .null,
            "pathIndex": execution?.pathIndex.map { .init($0) } ?? .null,
            "pathCount": execution?.pathCount.map { .init($0) } ?? .null,
            "running": .array((execution?.running ?? []).map(AgentJSON.string)),
            "carrier": game.vehicleWorld.vehicles.core.links[key]
                .map { .string("\($0.carrier)") } ?? .null,
            "mover": mover.map {
                .string("\($0.state) waypoint \($0.waypointIndex) of \($0.waypointCount)"
                    + " at \($0.feetPosition)")
            } ?? .null,
            "movement": movementReadout(key),
            "vehicle": vehicleReadout(key),
            "vehicleLinks": .array(links.keys.sorted()
                .map { .string("\($0) -> \(links[$0]?.carrier as Any)") }),
            "lastMove": game.packages.lastMoves[key].map { .string("\($0)") } ?? .null,
            "walk": key == .player ? .array((game.gameSession?.playerWalkPath ?? []).map {
                .string("\($0.x.rounded()), \($0.y.rounded()), \($0.z.rounded())")
            }) : .null,
            "idle": game.idleWorld.idles.idleSnapshot(for: key).report.map {
                .string("\($0.chosen ?? "none") from \($0.source) "
                    + ($0.seconds.isFinite ? "for \($0.seconds) s" : "held")
                    + ($0.failure.map { ", failed: \($0)" } ?? ""))
            } ?? .null,
            "idleTrace": .array((game.idleWorld.idles.idleSnapshot(for: key).report?.trace ?? [])
                .map { .string(IdleReadout.traceLine($0)) })
        ]
    }

    /// The movement type the actor's graph names, its speeds, and the shape it collides as.
    func movementReadout(_ key: ReferenceKey) -> AgentJSON {
        let name = game.actorGraphs.movementStateName(of: key)
        let speeds = game.streamer.npcMovementSpeeds?(key)
        let scale = game.streamer.npcTransform(for: key)?.scale ?? 1
        let bounds = game.streamer.npcBodyHalfExtents?(key)
        let capsule = bounds.flatMap { PlayerCapsule.upright(halfExtents: $0, scale: scale) }
        let long = bounds.flatMap { LongBodyShape(halfExtents: $0, scale: scale) }
        return [
            "type": name.map(AgentJSON.string) ?? .null,
            "walk": speeds.map { .init($0.forwardWalk * scale) } ?? .null,
            "run": speeds.map { .init($0.forwardRun * scale) } ?? .null,
            "capsuleRadius": capsule.map { .init($0.radius) } ?? .null,
            "capsuleHeight": capsule.map { .init($0.height) } ?? .null,
            "endRadius": long.map { .init($0.endRadius) } ?? .null,
            "endOffset": long.map { .init($0.endOffset) } ?? .null
        ]
    }

    /// Where the vehicle pass puts `key`, and which cell draws it at which pose.
    func vehicleReadout(_ key: ReferenceKey) -> AgentJSON {
        guard let live = game.vehicleWorld.vehicles.lastPoses[key] else { return .null }
        let built = game.vehicleWorld.vehicleFormID(of: key)
            .flatMap { game.renderer?.scene.referencePlacements[$0]?.columns.3 }
        let head = game.idleWorld.idles.idleBone(of: key, named: DialogueCamera.headBoneName)
            .map { bone in
                let root = MatrixMath.placement(
                    position: live.position, rotation: live.rotation, scale: 1
                )
                let world = root * SIMD4(bone, 1)
                return SIMD3(world.x, world.y, world.z)
            }
        return [
            "head": head.map { .init($0) } ?? .null,
            "live": .init(live.position),
            "yaw": .init(live.rotation.z),
            "cell": game.streamer.cellLocation(of: key).map { .string("\($0)") } ?? .null,
            "built": built.map { .init(SIMD3($0.x, $0.y, $0.z)) } ?? .null
        ]
    }
}
