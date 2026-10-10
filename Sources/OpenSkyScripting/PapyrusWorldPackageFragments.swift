// PACK fragments: a package runs its begin fragment when its procedure starts, its end
// fragment when the procedure is done, and its change fragment when the actor leaves it.
// Each takes `akActor`, the actor running it
// (<https://ck.uesp.net/wiki/Package_Fragments>). Layout: docs/formats/vmad.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Instantiates the package's fragment script if needed and enqueues the fragment
    /// with flag `slot`. Keyed by the PACK's `ReferenceKey` plus the script name.
    @discardableResult
    public func queuePackageFragment(
        of package: Package,
        slot: UInt32,
        actor: ReferenceKey,
        formIDResolver: FormIDResolver
    ) -> Bool {
        guard
            let section = package.scriptData.recordFragments,
            let fragment = section.fragments.first(where: { $0.slot == slot }),
            !fragment.scriptName.isEmpty,
            let key = ReferenceKey.resolve(package.formID, using: formIDResolver)
        else { return false }
        let target = PapyrusInstanceKey(reference: key, scriptName: fragment.scriptName)
        if instancesByKey[target] == nil, scriptsLoading([fragment.scriptName]) {
            deferUntilScriptsLoad { [weak self] in
                self?.queuePackageFragment(
                    of: package, slot: slot, actor: actor, formIDResolver: formIDResolver
                )
            }
            return false
        }
        guard
            attachRecordScript(
                target, declared: package.scriptData.scripts, formIDResolver: formIDResolver
            )
        else { return false }
        if
            let quest = package.details.ownerQuest
                .flatMap({ ReferenceKey.resolve($0, using: formIDResolver) })
        {
            fragmentQuests[key] = quest
        }
        enqueue(PapyrusScriptEvent(
            target: target,
            functionName: fragment.functionName,
            arguments: [.object(objectHandle(for: actor))]
        ))
        return true
    }
}

@MainActor
extension PapyrusWorldStateBridge {
    @discardableResult
    public func runPackageFragment(
        of package: Package, slot: UInt32, actor: ReferenceKey
    ) -> Bool {
        guard let world, let formIDResolver else { return false }
        return world.queuePackageFragment(
            of: package, slot: slot, actor: actor, formIDResolver: formIDResolver
        )
    }

    /// The actor event that goes with a package fragment slot: start, end, or change.
    @discardableResult
    public func queuePackageEvent(slot: UInt32, package: FormID, actor: ReferenceKey) -> Int {
        let name: String
        switch slot {
        case 0x01: name = "OnPackageStart"
        case 0x02: name = "OnPackageEnd"
        case 0x04: name = "OnPackageChange"
        default: return 0
        }
        return world?.queuePackageEvent(name, package: package, actor: actor) ?? 0
    }
}
