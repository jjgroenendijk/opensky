// `openskycli game debug sit|stand|rest` and `state furniture`: seat an actor, get it
// up, pass time as the rest and wait menus do, and read who sits where.

import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension AgentWorldAdapter {
    func performFurniture(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .sit(reference, furniture): return try sit(reference, in: furniture)
        case let .stand(reference):
            let actor = try resolveReference(reference)
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
        let target = try resolveReference(reference)
        let furniture = game.furniture
        if let seats = game.aiWorld.furnitureSeats(of: target.key), !seats.isEmpty {
            let holders = furniture.ledger.holders(of: target.key)
            return [
                "ref": .formID(target.formID.rawValue),
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
            "position": game.aiWorld.furnitureActorPosition(target.key).map { .init($0) } ?? .null
        ]
    }

    private func sit(
        _ reference: String,
        in furnitureText: String?
    ) throws(AgentFailure) -> AgentJSON {
        let actor = try resolveReference(reference)
        let furniture: ReferenceKey
        if let furnitureText {
            furniture = try resolveReference(furnitureText).key
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

    private func formID(of key: ReferenceKey) -> AgentJSON? {
        game.streamer?.referenceEntry(key: key).map { .formID($0.formID.rawValue) }
    }
}
