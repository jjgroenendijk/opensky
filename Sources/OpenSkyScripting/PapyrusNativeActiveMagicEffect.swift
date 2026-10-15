// The `ActiveMagicEffect` natives (<https://ck.uesp.net/wiki/ActiveMagicEffect_Script>) and
// `MagicEffect.GetAssociatedSkill`. The receiver is the script instance that serves one
// running effect; its oldest run answers. See docs/engine/papyrus-magic-effects.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installActiveMagicEffect(into registry: inout PapyrusNativeRegistry) {
        withEffectRun("GetTargetActor", into: &registry) { _, bridge, run in
            .returned(bridge.objectHandle(for: run.id.target).map { .object($0) } ?? .none)
        }
        withEffectRun("GetCasterActor", into: &registry) { _, bridge, run in
            .returned(run.caster.flatMap(bridge.objectHandle(for:)).map { .object($0) } ?? .none)
        }
        withEffectRun("GetBaseObject", into: &registry) { _, bridge, run in
            .returned(bridge.objectHandle(for: run.effect).map { .object($0) } ?? .none)
        }
        withEffectRun("Dispel", into: &registry) { call, bridge, run in
            guard
                let holder = bridge.actorHolder(for: run.id.target),
                let dispel = bridge.dispelEffects
            else { return failure(call, "Dispel needs an effect runtime and an actor target") }
            _ = dispel(holder) { $0.sequence == run.id.sequence }
            return .returned(.none)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "MagicEffect", functionName: "GetAssociatedSkill"
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver,
                let key = bridge.referenceKey(for: receiver),
                let data = bridge.magicEffectStore?.effect(key: key)?.effect.data
            else { return failure(call, "GetAssociatedSkill needs a magic effect record") }
            let names = ActorValueIdentity.vanillaNames
            let index = Int(data.magicSkill)
            return .returned(.string(names.indices.contains(index) ? names[index] : ""))
        })
    }

    /// Registers an `ActiveMagicEffect` native whose receiver serves a running effect.
    private static func withEffectRun(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, PapyrusActiveEffectRun
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ActiveMagicEffect", functionName: name
        ) { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let world = bridge.world,
                let receiver = call.receiver,
                let key = world.keysByHandle[receiver],
                let run = world.effectScripts.run(servedBy: key)
            else { return failure(call, "\(name) needs a running magic effect") }
            return body(call, bridge, run)
        })
    }
}
