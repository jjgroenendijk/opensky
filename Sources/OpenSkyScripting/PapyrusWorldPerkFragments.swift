// PERK fragments: an Activate choice of a perk runs one fragment of the perk's
// fragment script, as `Fragment_N(ObjectReference akTargetRef, Actor akActor)`
// (<https://ck.uesp.net/wiki/Perk_Fragments>). Layout: docs/formats/vmad.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Instantiates the perk's fragment script if needed and enqueues fragment `index`.
    /// Keyed by the PERK's `ReferenceKey` plus the script name.
    @discardableResult
    public func queuePerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        index: UInt16,
        activation: PerkFragmentActivation,
        formIDResolver: FormIDResolver
    ) -> Bool {
        guard
            let fragment = perk.script.recordFragments?.fragment(slot: UInt32(index)),
            !fragment.scriptName.isEmpty
        else { return false }
        let target = PapyrusInstanceKey(reference: key, scriptName: fragment.scriptName)
        if instancesByKey[target] == nil, scriptsLoading([fragment.scriptName]) {
            deferUntilScriptsLoad { [weak self] in
                self?.queuePerkFragment(
                    of: perk, key: key, index: index, activation: activation,
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
        enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: [
                .object(objectHandle(for: activation.target)),
                .object(objectHandle(for: activation.actor))
            ]
        ))
        return true
    }
}

/// Who pressed the use key on what, for one perk fragment.
nonisolated public struct PerkFragmentActivation: Equatable, Sendable {
    public let actor: ReferenceKey
    public let target: ReferenceKey

    public init(actor: ReferenceKey, target: ReferenceKey) {
        self.actor = actor
        self.target = target
    }
}

@MainActor
extension PapyrusWorldStateBridge {
    @discardableResult
    public func runPerkFragment(
        of perk: Perk, key: ReferenceKey, index: UInt16, activation: PerkFragmentActivation
    ) -> Bool {
        guard let world, let formIDResolver else { return false }
        return world.queuePerkFragment(
            of: perk, key: key, index: index, activation: activation,
            formIDResolver: formIDResolver
        )
    }
}
