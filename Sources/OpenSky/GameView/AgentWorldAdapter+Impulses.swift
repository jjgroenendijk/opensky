// `state impulses` and `debug knock`: the push settings, the newest knocks, pushes,
// splashes, and physics hits, and a forced knockback (docs/engine/impulses.md).

import Foundation
import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyFormatsESM
import simd

extension AgentWorldAdapter {
    func impulsesState() -> AgentJSON {
        guard let impulses = game.combat.impulses else { return ["available": .bool(false)] }
        let settings = impulses.settings
        return [
            "available": .bool(true),
            "settings": [
                "knockbackDamageMult": .init(settings.knockbackDamageMult),
                "knockbackForceMax": .init(settings.knockbackForceMax),
                "knockbackTime": .init(settings.knockbackTime),
                "knockdownCurrentHealthThreshold": .init(settings.knockdownCurrentHealthThreshold),
                "explosionSourceRefMult": .init(settings.explosionSourceRefMult),
                "projectileKnockBiped": .init(settings.projectileKnock.biped),
                "splashModel": .string(impulses.water.splashModel),
                "waterKnockdownVelocity": .init(impulses.water.knockdownVelocity)
            ],
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
                "position": .array([splash.position.x, splash.position.y, splash.position.z]
                    .map { .init($0) })
            ]
        case let .physicsDamage(body, actor, damage):
            [
                "kind": "physicsDamage", "body": reference(body), "ref": reference(actor),
                "damage": .init(damage)
            ]
        }
    }

    private func reference(_ key: ReferenceKey) -> AgentJSON {
        key == .player ? .string("player") : formID(of: key) ?? .string("\(key)")
    }
}
