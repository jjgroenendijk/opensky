// PERK fragments: an Activate choice of a perk runs one fragment of the perk's
// fragment script, as `Fragment_N(ObjectReference akTargetRef, Actor akActor)`
// (<https://ck.uesp.net/wiki/Perk_Fragments>). Layout: docs/formats/vmad.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.FragmentRuns {
    /// Instantiates the perk's fragment script if needed and enqueues fragment `index`.
    /// Keyed by the PERK's `ReferenceKey` plus the script name.
    @discardableResult
    public func queuePerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        fragment slot: (index: UInt16, activation: PerkFragmentActivation),
        formIDResolver: FormIDResolver
    ) -> Bool {
        let (index, activation) = slot
        guard
            let fragment = perk.script.recordFragments?.fragment(slot: UInt32(index)),
            !fragment.scriptName.isEmpty
        else { return false }
        let target = PapyrusInstanceKey(reference: key, scriptName: fragment.scriptName)
        if
            world.instancesByKey[target] == nil,
            world.lifecycle.scriptsLoading([fragment.scriptName])
        {
            world.lifecycle.deferUntilScriptsLoad { [weak world] in
                world?.fragmentRuns.queuePerkFragment(
                    of: perk, key: key, fragment: (index, activation),
                    formIDResolver: formIDResolver
                )
            }
            return false
        }
        guard
            attachRecordScript(
                target, declared: perk.script.scripts, formIDResolver: formIDResolver
            )
        else { return false }
        world.enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: [
                .object(world.objectHandle(for: activation.target)),
                .object(world.objectHandle(for: activation.actor))
            ]
        ))
        return true
    }
}

@MainActor
extension PapyrusWorldStateBridge.StoryEvents {
    @discardableResult
    public func runPerkFragment(
        of perk: Perk, key: ReferenceKey, index: UInt16, activation: PerkFragmentActivation
    ) -> Bool {
        guard
            let world = bridge.world,
            let formIDResolver = bridge.formIDResolver else { return false }
        return world.fragmentRuns.queuePerkFragment(
            of: perk, key: key, fragment: (index, activation),
            formIDResolver: formIDResolver
        )
    }
}
