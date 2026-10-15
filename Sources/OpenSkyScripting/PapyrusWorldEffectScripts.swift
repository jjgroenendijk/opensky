// `ActiveMagicEffect` scripts: a magic effect's VMAD scripts run while the effect runs
// on an actor. `OnEffectStart` follows `OnInit`; `OnEffectFinish` is the last event
// before the instance retires (<https://ck.uesp.net/wiki/OnEffectStart_-_ActiveMagicEffect>,
// <https://ck.uesp.net/wiki/OnEffectFinish_-_ActiveMagicEffect>).
// See docs/engine/papyrus-magic-effects.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Starts the scripts of one effect run on its target and queues `OnEffectStart`.
    /// A script still loading attaches once it loads, unless the run ended first.
    public func startEffectScripts(
        _ run: PapyrusActiveEffectRun,
        scripts: [AttachedScript],
        formIDResolver: FormIDResolver
    ) {
        let live = scripts.filter { !$0.isRemoved }
        guard !live.isEmpty else { return }
        effectScripts.begin(run)
        attachEffectScripts(run, scripts: live, formIDResolver: formIDResolver)
    }

    /// Ends one effect run: queues `OnEffectFinish` on each instance that served it,
    /// and retires an instance that now serves no run once its events have run.
    public func finishEffectScripts(_ id: PapyrusActiveEffectID) {
        guard let run = effectScripts.runs[id] else { return }
        let (served, idle) = effectScripts.end(id)
        for key in served where instancesByKey[key] != nil {
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onEffectFinish,
                arguments: effectArguments(run)
            ))
        }
        retiringKeys.formUnion(idle.filter { instancesByKey[$0] != nil })
    }

    private func attachEffectScripts(
        _ run: PapyrusActiveEffectRun,
        scripts: [AttachedScript],
        formIDResolver: FormIDResolver
    ) {
        if scriptsLoading(scripts.map(\.name)) {
            deferUntilScriptsLoad { [weak self] in
                guard let self, effectScripts.runs[run.id] != nil else { return }
                attachEffectScripts(run, scripts: scripts, formIDResolver: formIDResolver)
            }
            return
        }
        for script in scripts {
            let key = PapyrusInstanceKey(reference: run.id.target, scriptName: script.name)
            guard instancesByKey[key] != nil || makeEffectInstance(key, script, formIDResolver)
            else { continue }
            effectScripts.attach(key, to: run.id)
            retiringKeys.remove(key)
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onEffectStart,
                arguments: effectArguments(run)
            ))
        }
    }

    private func makeEffectInstance(
        _ key: PapyrusInstanceKey, _ script: AttachedScript, _ resolver: FormIDResolver
    ) -> Bool {
        guard resolveScript(named: script.name) else {
            skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(key: key, script: script, isPersistent: false)
        guard instantiate(item) else { return false }
        bind(plan: [item], created: [key], formIDResolver: resolver)
        enqueueOnInitIfNeeded(key)
        return true
    }

    /// `(Actor akTarget, Actor akCaster)`. A potion nobody cast has no caster.
    private func effectArguments(_ run: PapyrusActiveEffectRun) -> [PapyrusValue] {
        [
            .object(objectHandle(for: run.id.target)),
            run.caster.map { .object(objectHandle(for: $0)) } ?? .none
        ]
    }
}
