import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
public import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `AgentMotionAdapter` reads from the session.
@MainActor
public protocol AgentMotionHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var dragonFlight: any DragonFlightPort { get }
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var mountWorld: any MountWorldPort { get }
    var mounts: any MountPort { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentMotionAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentMotionHost
}

extension AgentMotionAdapter {
    public func orderFlight(_ reference: String, order: AgentFlightOrder) throws(AgentFailure)
        -> AgentJSON
    {
        let actor = try owner.resolveReference(reference)
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

    public func flightState(reference: String?) throws(AgentFailure) -> AgentJSON {
        if let reference {
            let actor = try owner.resolveReference(reference)
            var json = flightJSON(of: actor.key)
            json["ref"] = .formID(actor.formID.rawValue)
            return .object(json)
        }
        let flying = game.dragonFlightWorld.flyingStates.keys.sorted()
        return [
            "flying": .array(flying.map { key in
                var json = flightJSON(of: key)
                json["ref"] = owner.behaviour.formID(of: key) ?? .string("\(key)")
                return .object(json)
            }),
            "eventsHandled": .init(game.dragonFlight.handledEvents)
        ]
    }

    public func mountState() -> AgentJSON {
        let mounts = game.mounts
        guard let drive = mounts.drive else {
            return [
                "riding": .bool(false),
                "lastMount": mounts.lastMount.flatMap(owner.behaviour.formID) ?? .null
            ]
        }
        let orders = mounts.dragonOrders
        return [
            "riding": .bool(true),
            "ref": owner.behaviour.formID(of: drive.mount) ?? .string("\(drive.mount)"),
            "kind": .string("\(drive.kind)"),
            "phase": .string("\(mounts.phase)"),
            "speed": .init(drive.motion.speed),
            "heading": .init(drive.heading),
            "turnRateDegrees": .init(MatrixMath.degrees(fromRadians: drive.turnRamp.rate)),
            "sprintAllowed": .bool(drive.bridge.isSprintAllowed),
            "stamina": mountStamina(drive.mount),
            "flight": drive.flight.map { .object(Self.flightJSON($0)) } ?? .null,
            "orders": drive.kind == .dragon ? [
                "landingRequested": .bool(orders.landingRequested),
                "lockedTarget": orders.lockedTarget.flatMap(owner.behaviour.formID) ?? .null,
                "switchedTarget": orders.switchedTarget.flatMap(owner.behaviour.formID) ?? .null,
                "attacking": .bool(orders.isAttacking),
                "breath": .string("\(orders.breath)"),
                "breathCooldown": .init(orders.breathCooldown)
            ] : .null
        ]
    }

    private func mountStamina(_ key: ReferenceKey) -> AgentJSON {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return .null }
        return [
            "current": .init(runtime.current(of: holder).stamina),
            "maximum": .init(runtime.maximums(of: holder).stamina)
        ]
    }

    private func flightJSON(of key: ReferenceKey) -> [String: AgentJSON] {
        if let drive = game.mounts.drive, drive.mount == key, let flight = drive.flight {
            let orders = game.mounts.dragonOrders
            var json = Self.flightJSON(flight)
            json["ridden"] = .bool(true)
            json["rider"] = [
                "lockedTarget": orders.lockedTarget.flatMap(owner.behaviour.formID) ?? .null,
                "switchedTarget": orders.switchedTarget.flatMap(owner.behaviour.formID) ?? .null,
                "attacking": .bool(orders.isAttacking)
            ]
            return json
        }
        var json = game.dragonFlight.flights[key].map(Self.flightJSON)
            ?? ["phase": .string("grounded"), "state": .init(0)]
        json["order"] = game.dragonFlight.orders[key].map { .string($0.rawValue) } ?? .null
        json["landingEvent"] = game.dragonFlight.landingEvents[key].map(AgentJSON.string) ?? .null
        if let perch = game.dragonFlight.flights[key]?.perch {
            json["perch"] = owner.behaviour
                .formID(of: perch.reference) ?? .string("\(perch.reference)")
        }
        json["getIsFlying"] = .bool(game.dragonFlightWorld.isFlying(key))
        return json
    }

    private static func flightJSON(_ state: any DragonFlightStatePort) -> [String: AgentJSON] {
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

    public func impulsesState() -> AgentJSON {
        guard let impulses = game.combat.impulses else { return ["available": .bool(false)] }
        let settings = impulses.settings
        return [
            "available": .bool(true),
            "settings": [
                "knockbackDamageMult": .init(settings.knockbackDamageMult),
                "knockbackDamageBase": .init(settings.knockbackDamageBase),
                "knockdownChance": .init(settings.knockdownChance),
                "gameplayImpulseScale": .init(settings.gameplayImpulseScale),
                "explosionMaxImpulse": .init(settings.explosionMaxImpulse),
                "splashTimer": .init(impulses.water.splashTimer),
                "knockbackForceMax": .init(settings.knockbackForceMax),
                "knockbackTime": .init(settings.knockbackTime),
                "knockdownCurrentHealthThreshold": .init(settings.knockdownCurrentHealthThreshold),
                "explosionSourceRefMult": .init(settings.explosionSourceRefMult),
                "projectileKnockBiped": .init(settings.projectileKnock.biped),
                "splashModel": .string(impulses.water.splashModel),
                "waterKnockdownVelocity": .init(impulses.water.knockdownVelocity)
            ],
            "knockdowns": knockdownsJSON(),
            "splashCount": .init(impulses.splashCount),
            "waterRings": .init(game.renderer?.waterRipples.ripples.count ?? 0),
            "playerWater": playerWaterJSON(),
            "events": .array(impulses.events.map(eventJSON))
        ]
    }

    /// The water over the player's feet and what its current added to the last step.
    private func playerWaterJSON() -> AgentJSON {
        guard let plan = game.gameSession?.locomotion.status.lastPlan, let water = plan.water
        else { return .null }
        return [
            "surface": .init(water.surface),
            "current": .init(water.current),
            "push": .init(plan.waterPush),
            "dangerous": .bool(water.isDangerous),
            "waterType": water.waterType.map { .formID($0.rawValue) } ?? .null
        ]
    }

    public func knock(_ reference: String, damage: Float) throws(AgentFailure) -> AgentJSON {
        let actor = try owner.resolveReference(reference)
        let knock = game.combat.forceKnockBack(actor.key, damage: damage)
        return [
            "ref": .formID(actor.formID.rawValue),
            "knocked": .bool(knock != nil),
            "speed": knock.map { .init($0.speed) } ?? .null,
            "knockdown": .bool(knock?.isKnockdown ?? false)
        ]
    }

    public func knockDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .knock(reference, damage): try knock(reference, damage: damage)
        case let .knockdown(reference, magnitude): try knockDown(reference, magnitude: magnitude)
        default: throw AgentFailure(.invalidArgument, "not a knock command")
        }
    }

    public func knockDown(_ reference: String, magnitude: Float) throws(AgentFailure) -> AgentJSON {
        let actor = try owner.resolveReference(reference)
        let source = game.combat.meleeAttacker.feet
        let knocked = game.effectsWorld.knockDown(actor.key, from: source, magnitude: magnitude)
        return [
            "ref": .formID(actor.formID.rawValue),
            "knocked": .bool(knocked),
            "ragdoll": .bool(game.ragdoll.knockdowns.isKnockedDown(actor.key))
        ]
    }

    private func knockdownsJSON() -> AgentJSON {
        let phases = game.ragdoll.knockdowns.phases
        return .array(phases.keys.sorted().compactMap { key in
            switch phases[key] {
            case let .down(remaining):
                ["ref": reference(key), "phase": "down", "remaining": .init(remaining)]
            case let .gettingUp(elapsed, duration):
                [
                    "ref": reference(key), "phase": "gettingUp", "elapsed": .init(elapsed),
                    "duration": .init(duration)
                ]
            case nil: nil
            }
        })
    }

    private func eventJSON(_ event: ImpulseEvent) -> AgentJSON {
        switch event {
        case let .knock(key, speed, knockdown, cause):
            [
                "kind": "knock", "ref": reference(key), "speed": .init(speed),
                "knockdown": .bool(knockdown), "cause": .string(cause.rawValue)
            ]
        case let .push(key, impulse, cause):
            [
                "kind": "push", "ref": reference(key), "impulse": .init(impulse),
                "cause": .string(cause.rawValue)
            ]
        case let .splash(splash):
            [
                "kind": "splash", "ref": splash.source.map(reference) ?? .null,
                "weight": .string(splash.weight.rawValue), "model": .string(splash.model),
                "sound": splash.weight.sound.map(AgentJSON.string) ?? .null,
                "scale": .init(splash.scale),
                "position": .array([splash.position.x, splash.position.y, splash.position.z]
                    .map { .init($0) })
            ]
        case let .physicsDamage(body, actor, damage):
            [
                "kind": "physicsDamage", "body": reference(body), "ref": reference(actor),
                "damage": .init(damage)
            ]
        case let .collision(collision):
            [
                "kind": "collision", "ref": reference(collision.body),
                "speedLoss": .init(collision.speedLoss), "gain": .init(collision.gain),
                "material": collision.material.map { .string("\($0)") } ?? .null
            ]
        }
    }

    private func reference(_ key: ReferenceKey) -> AgentJSON {
        key == .player ? .string("player") : owner.behaviour.formID(of: key) ?? .string("\(key)")
    }
}
