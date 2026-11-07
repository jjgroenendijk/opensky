// `state impulses` and `debug knock`: the push settings, the newest knocks, pushes,
// splashes, and physics hits, and a forced knockback (docs/engine/impulses.md).

import Foundation
import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import simd

extension AgentWorldAdapter {
    func impulsesState() -> AgentJSON {
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
            "events": .array(impulses.events.map(eventJSON))
        ]
    }

    func knock(_ reference: String, damage: Float) throws(AgentFailure) -> AgentJSON {
        let actor = try resolveReference(reference)
        let knock = game.combat.forceKnockBack(actor.key, damage: damage)
        return [
            "ref": .formID(actor.formID.rawValue),
            "knocked": .bool(knock != nil),
            "speed": knock.map { .init($0.speed) } ?? .null,
            "knockdown": .bool(knock?.isKnockdown ?? false)
        ]
    }

    func knockDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .knock(reference, damage): try knock(reference, damage: damage)
        case let .knockdown(reference, magnitude): try knockDown(reference, magnitude: magnitude)
        default: throw AgentFailure(.invalidArgument, "not a knock command")
        }
    }

    func knockDown(_ reference: String, magnitude: Float) throws(AgentFailure) -> AgentJSON {
        let actor = try resolveReference(reference)
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
        key == .player ? .string("player") : formID(of: key) ?? .string("\(key)")
    }
}
