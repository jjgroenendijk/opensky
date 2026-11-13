// `ActiveMagicEffect` scripts: a magic effect's VMAD scripts run while the effect runs
// on an actor. `OnEffectStart` follows `OnInit`; `OnEffectFinish` is the last event
// before the instance retires (<https://ck.uesp.net/wiki/OnEffectStart_-_ActiveMagicEffect>,
// <https://ck.uesp.net/wiki/OnEffectFinish_-_ActiveMagicEffect>).
// See docs/engine/papyrus-magic-effects.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.ActiveEffects {
    /// Starts the scripts of one effect run on its target and queues `OnEffectStart`.
    /// A script still loading attaches once it loads, unless the run ended first.
    /// `announces` false attaches an effect a save brought back, with no `OnInit` or start.
    func startEffectScripts(
        _ run: PapyrusActiveEffectRun,
        scripts: [AttachedScript],
        formIDResolver: FormIDResolver,
        announces: Bool = true
    ) {
        let live = scripts.filter { !$0.isRemoved }
        guard !live.isEmpty else { return }
        world.effectScripts.begin(run)
        attachEffectScripts(
            run,
            scripts: live,
            formIDResolver: formIDResolver,
            announces: announces
        )
    }

    /// Ends one effect run: queues `OnEffectFinish` on each instance that served it,
    /// and retires an instance that now serves no run once its events have run.
    public func finishEffectScripts(_ id: PapyrusActiveEffectID) {
        guard let run = world.effectScripts.runs[id] else { return }
        let (served, idle) = world.effectScripts.end(id)
        for key in served where world.instancesByKey[key] != nil {
            world.enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onEffectFinish,
                arguments: effectArguments(run)
            ))
        }
        world.retiringKeys.formUnion(idle.filter { world.instancesByKey[$0] != nil })
    }

    private func attachEffectScripts(
        _ run: PapyrusActiveEffectRun,
        scripts: [AttachedScript],
        formIDResolver: FormIDResolver,
        announces: Bool
    ) {
        if world.lifecycle.scriptsLoading(scripts.map(\.name)) {
            world.lifecycle.deferUntilScriptsLoad { [weak world] in
                guard let world, world.effectScripts.runs[run.id] != nil else { return }
                world.activeEffects.attachEffectScripts(
                    run, scripts: scripts, formIDResolver: formIDResolver, announces: announces
                )
            }
            return
        }
        guard let serial = world.effectScripts.serials[run.id] else { return }
        for script in scripts {
            let key = PapyrusInstanceKey(
                reference: run.id.target, scriptName: script.name, effectRun: serial
            )
            if !announces {
                world.firedOnInit.insert(key)
            }
            guard world.instancesByKey[key] != nil || makeEffectInstance(
                key,
                script,
                formIDResolver
            )
            else { continue }
            world.effectScripts.attach(key, to: run.id)
            world.retiringKeys.remove(key)
            guard announces else { continue }
            world.enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onEffectStart,
                arguments: effectArguments(run)
            ))
        }
    }

    private func makeEffectInstance(
        _ key: PapyrusInstanceKey, _ script: AttachedScript, _ resolver: FormIDResolver
    ) -> Bool {
        guard world.resolveScript(named: script.name) else {
            world.skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(key: key, script: script, isPersistent: false)
        guard world.lifecycle.instantiate(item) else { return false }
        world.lifecycle.bind(plan: [item], created: [key], formIDResolver: resolver)
        world.enqueueOnInitIfNeeded(key)
        return true
    }

    /// `(Actor akTarget, Actor akCaster)`. A potion nobody cast has no caster.
    private func effectArguments(_ run: PapyrusActiveEffectRun) -> [PapyrusValue] {
        [
            .object(world.objectHandle(for: run.id.target)),
            run.caster.map { .object(world.objectHandle(for: $0)) } ?? .none
        ]
    }
}
