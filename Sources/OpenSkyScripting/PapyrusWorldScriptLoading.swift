// Scripts load off the main actor during play. Work that needs a script that has
// not arrived waits here and runs again after the next drain, in the order it came.
// See docs/decisions/concurrency.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum PapyrusScriptAvailability: Equatable, Sendable {
    case ready
    case loading
    case missing
}

/// One attach or fragment that waits for a script. `cell` and `quest` let a detach
/// or a stop drop it.
public struct PapyrusDeferredScriptWork {
    let cell: CellSceneLocation?
    let quest: ReferenceKey?
    let run: () -> Void
}

extension PapyrusWorldRuntime {
    /// Types whose property handlers a script runs on a form without a script instance,
    /// such as `ObjectReference.Motion_Keyframed`. Nothing else may load them.
    static let referenceTypeScripts = ["ObjectReference", "Actor", "GlobalVariable"]

    /// The scripts of the quests and references that `scripts`' object properties name.
    /// An attach waits for them too, so a first use can attach them at once (`attachOnUse`).
    func targetScripts(of scripts: [AttachedScript], resolver: FormIDResolver) -> [String] {
        guard let scriptsOfTarget else { return [] }
        let objects = scripts.flatMap(\.properties).flatMap { property -> [ScriptObjectReference] in
            switch property.value {
            case let .object(object): [object]
            case let .objects(objects): objects
            default: []
            }
        }
        let keys = Set(objects.compactMap { $0.directReferenceKey(using: resolver) })
        return keys.sorted().flatMap(scriptsOfTarget)
    }

    /// Requests every named script, and the reference types. True when any still loads.
    func scriptsLoading(_ names: [String]) -> Bool {
        var loading = false
        for name in names + Self.referenceTypeScripts
            where scriptAvailability(named: name) == .loading
        {
            loading = true
        }
        return loading
    }

    func deferUntilScriptsLoad(
        cell: CellSceneLocation? = nil,
        quest: ReferenceKey? = nil,
        _ run: @escaping () -> Void
    ) {
        deferredScriptWork.append(PapyrusDeferredScriptWork(cell: cell, quest: quest, run: run))
    }

    func hasDeferredWork(forQuest key: ReferenceKey) -> Bool {
        deferredScriptWork.contains { $0.quest == key }
    }

    /// Runs the waiting work again, oldest first. Work that still waits queues again.
    public func retryDeferredScriptWork() {
        guard !deferredScriptWork.isEmpty else { return }
        let waiting = deferredScriptWork
        deferredScriptWork = []
        for work in waiting {
            work.run()
        }
    }
}
