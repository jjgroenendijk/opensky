// What scripts changed about the leveled lists: the entries `AddForm` added and the
// values of the `LVLG` chance-none globals. Every resolver reads them through the
// one shared roller. See docs/engine/leveled-lists.md#script-changes.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import Synchronization

nonisolated public final class LeveledScriptEdits: Sendable {
    private struct State {
        var added: [UInt32: [LeveledList.Entry]] = [:]
        var globals: [UInt32: Float] = [:]
        /// The globals a roll read, so a write to any other global keeps the memos.
        var read: Set<UInt32> = []
        var revision = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// Rises with each change, so a roll memo keyed on it derives again.
    public var revision: Int {
        state.withLock { $0.revision }
    }

    /// Replaces every added entry, keyed by the list's load-order FormID.
    public func setAddedEntries(_ added: [FormID: [LeveledList.Entry]]) {
        let byRaw = Dictionary(uniqueKeysWithValues: added.map { ($0.key.rawValue, $0.value) })
        state.withLock { state in
            guard state.added != byRaw else { return }
            state.added = byRaw
            state.revision += 1
        }
    }

    /// Replaces the script-set global values.
    public func setGlobals(_ values: [FormID: Float]) {
        let byRaw = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        state.withLock { state in
            let changed = state.read.contains { state.globals[$0] != byRaw[$0] }
            state.globals = byRaw
            if changed {
                state.revision += 1
            }
        }
    }

    public func global(_ id: FormID) -> Float? {
        state.withLock { state in
            state.read.insert(id.rawValue)
            return state.globals[id.rawValue]
        }
    }

    /// The list with the entries scripts added after its plugin entries.
    public func edited(_ list: LeveledList) -> LeveledList {
        let added = state.withLock { $0.added[list.formID.rawValue] } ?? []
        return added.isEmpty ? list : list.appending(added)
    }
}
