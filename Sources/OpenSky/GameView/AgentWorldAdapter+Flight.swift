// `openskycli game debug flight` and `state flight|mount`: force a take-off or a
// landing, and read each flight, its perch and landing, and the player's mount and
// orders (docs/engine/dragon-flight.md).

import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyPlayer

extension AgentWorldAdapter {
    func orderFlight(_ reference: String, order: AgentFlightOrder) throws(AgentFailure)
        -> AgentJSON
    {
        let actor = try resolveReference(reference)
        guard game.combatWorld.actorFlies(actor.key) else {
            throw AgentFailure(.invalidArgument, "\(reference) does not fly")
        }
        let flightOrder: DragonFlightOrder = switch order {
        case .takeOff: .takeOff
        case .land: .land
        case .perch: .perch
        case .hasty: .hastyLand
        case .crash: .crashLand
        }
        if game.mounts.drive?.mount == actor.key {
            game.mountWorld.run(game.mounts.orderDragon(flightOrder))
        } else {
            game.dragonFlight.order(flightOrder, for: actor.key)
        }
        return ["ref": .formID(actor.formID.rawValue), "order": .string(order.rawValue)]
    }

    func flightState(reference: String?) throws(AgentFailure) -> AgentJSON {
        if let reference {
            let actor = try resolveReference(reference)
            var json = flightJSON(of: actor.key)
            json["ref"] = .formID(actor.formID.rawValue)
            return .object(json)
        }
        let flying = game.dragonFlightWorld.flyingStates.keys.sorted()
        return [
            "flying": .array(flying.map { key in
                var json = flightJSON(of: key)
                json["ref"] = formID(of: key) ?? .string("\(key)")
                return .object(json)
            }),
            "eventsHandled": .init(game.dragonFlight.handledEvents)
        ]
    }

    func mountState() -> AgentJSON {
        let mounts = game.mounts
        guard let drive = mounts.drive else {
            return ["riding": .bool(false), "lastMount": mounts.lastMount.flatMap(formID) ?? .null]
        }
        let orders = mounts.dragonOrders
        return [
            "riding": .bool(true),
            "ref": formID(of: drive.mount) ?? .string("\(drive.mount)"),
            "kind": .string("\(drive.kind)"),
            "phase": .string("\(mounts.phase)"),
            "speed": .init(drive.motion.speed),
            "heading": .init(drive.heading),
            "flight": drive.flight.map { .object(Self.flightJSON($0)) } ?? .null,
            "orders": drive.kind == .dragon ? [
                "landingRequested": .bool(orders.landingRequested),
                "lockedTarget": orders.lockedTarget.flatMap(formID) ?? .null,
                "switchedTarget": orders.switchedTarget.flatMap(formID) ?? .null,
                "attacking": .bool(orders.isAttacking),
                "breath": .string("\(orders.breath)"),
                "breathCooldown": .init(orders.breathCooldown)
            ] : .null
        ]
    }

    private func flightJSON(of key: ReferenceKey) -> [String: AgentJSON] {
        if let drive = game.mounts.drive, drive.mount == key, let flight = drive.flight {
            let orders = game.mounts.dragonOrders
            var json = Self.flightJSON(flight)
            json["ridden"] = .bool(true)
            json["rider"] = [
                "lockedTarget": orders.lockedTarget.flatMap(formID) ?? .null,
                "switchedTarget": orders.switchedTarget.flatMap(formID) ?? .null,
                "attacking": .bool(orders.isAttacking)
            ]
            return json
        }
        var json = game.dragonFlight.flights[key].map(Self.flightJSON)
            ?? ["phase": .string("grounded"), "state": .init(0)]
        json["order"] = game.dragonFlight.orders[key].map { .string($0.rawValue) } ?? .null
        json["landingEvent"] = game.dragonFlight.landingEvents[key].map(AgentJSON.string) ?? .null
        if let perch = game.dragonFlight.flights[key]?.perch {
            json["perch"] = formID(of: perch.reference) ?? .string("\(perch.reference)")
        }
        json["getIsFlying"] = .bool(game.dragonFlightWorld.isFlying(key))
        return json
    }

    private static func flightJSON(_ state: DragonFlightState) -> [String: AgentJSON] {
        [
            "phase": .string("\(state.phase)"),
            "state": .init(Int(state.phase.rawValue)),
            "feet": .init(state.feet),
            "yaw": .init(state.yaw),
            "speed": .init(state.speed),
            "verticalSpeed": .init(state.verticalSpeed),
            "pitch": .init(state.pitch),
            "approaching": .bool(state.isApproaching),
            "landingRequest": .string(state.landingRequest.rawValue),
            "perched": .bool(state.phase == .perched),
            "landingPoint": state.landingPoint.map(AgentJSON.init) ?? .null
        ]
    }
}
