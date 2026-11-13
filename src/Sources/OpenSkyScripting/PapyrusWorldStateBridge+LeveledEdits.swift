// Hands the leveled-list changes scripts made to the shared roller: the entries
// `AddForm` added and the global values `LVLG` reads (docs/engine/leveled-lists.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.LeveledEdits {
    static func addedLevelName(_ form: ReferenceKey) -> String {
        "addedLevel:\(form)"
    }

    static func addedCountName(_ form: ReferenceKey) -> String {
        "addedCount:\(form)"
    }

    /// Run after an `AddForm`, a `Revert`, a global write, and a load.
    public func publishLeveledEdits() {
        guard let edits = bridge.natives.session.leveledEdits?() else { return }
        edits.setAddedEntries(scriptAddedLeveledEntries())
        var globals: [FormID: Float] = [:]
        for key in bridge.worldState.sortedOverriddenGlobalKeys() {
            guard
                let id = bridge.localFormID(of: key),
                let value = bridge.worldState.globalValue(for: key)
            else { continue }
            globals[id] = value.value
        }
        edits.setGlobals(globals)
    }

    /// A leveled list's added forms carry a level; a form list's do not.
    func scriptAddedLeveledEntries() -> [FormID: [LeveledList.Entry]] {
        var added: [FormID: [LeveledList.Entry]] = [:]
        for key in bridge.worldState.sortedDirtyKeys() {
            guard
                let state = bridge.worldState.component(ScriptedReferenceState.self, for: key),
                let list = bridge.localFormID(of: key)
            else { continue }
            let entries = state.addedForms.compactMap { form -> LeveledList.Entry? in
                guard
                    let level = state.value(Self.addedLevelName(form)),
                    let id = bridge.localFormID(of: form)
                else { return nil }
                let count = state.value(Self.addedCountName(form)) ?? 1
                return LeveledList.Entry(
                    addedForm: id, level: UInt16(clamping: Int(level)),
                    count: UInt32(clamping: Int(count))
                )
            }
            if !entries.isEmpty {
                added[list] = entries
            }
        }
        return added
    }
}
