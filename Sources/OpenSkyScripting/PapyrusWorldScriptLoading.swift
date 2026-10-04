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
    /// Requests every named script. True when any of them still loads.
    func scriptsLoading(_ names: [String]) -> Bool {
        var loading = false
        for name in names where scriptAvailability(named: name) == .loading {
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
