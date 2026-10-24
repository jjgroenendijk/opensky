// Scripts load off the main actor during play. Work that needs a script that has
// not arrived waits here and runs again after the next drain, in the order it came.
// See docs/decisions/concurrency.md.

import OpenSkyFormatsESM
import OpenSkyFormatsPEX
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

    /// Requests every named script, the reference types, and the scripts their code calls
    /// global functions on, such as `Custom.countLinks`. True when any still loads.
    func scriptsLoading(_ names: [String]) -> Bool {
        var loading = false
        var pending = names + Self.referenceTypeScripts
        var seen: Set<String> = []
        while let name = pending.popLast() {
            guard seen.insert(PapyrusRuntime.key(name)).inserted else { continue }
            switch scriptAvailability(named: name) {
            case .loading: loading = true
            case .ready: pending += staticCallScripts(ofChain: name)
            case .missing: break
            }
        }
        return loading
    }

    /// The static call targets of `name` and its loaded ancestors.
    private func staticCallScripts(ofChain name: String) -> [String] {
        var targets: [String] = []
        var current = name
        var visited: Set<String> = []
        while !current.isEmpty, visited.insert(PapyrusRuntime.key(current)).inserted {
            let key = PapyrusRuntime.key(current)
            guard let object = runtime.script(named: current) else { break }
            if let known = staticCallScriptsByKey[key] {
                targets += known
            } else {
                let found = object.staticCallScripts
                staticCallScriptsByKey[key] = found
                targets += found
            }
            current = object.parentClassName
        }
        return targets
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
