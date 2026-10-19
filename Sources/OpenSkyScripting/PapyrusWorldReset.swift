// Script side of a cell reset (<https://ck.uesp.net/wiki/OnReset_-_ObjectReference>):
// a reset reference starts with fresh script data, runs `OnInit` again, then `OnReset`.
// See docs/engine/cell-reset.md.

import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Before the cell's attach: drops the live instances on `references`, so the
    /// attach makes new ones, and lets each run `OnInit` again.
    public func prepareReset(of references: [ReferenceKey]) {
        for reference in references {
            for key in instanceKeys(on: reference) {
                retire(key)
                persistentKeys.remove(key)
            }
            firedOnInit = firedOnInit.filter { $0.reference != reference }
        }
    }

    /// After the cell's attach, so `OnReset` runs after `OnInit`. Returns the count.
    @discardableResult
    public func enqueueReset(of references: [ReferenceKey]) -> Int {
        var queued = 0
        for reference in references {
            for key in instanceKeys(on: reference)
                where handlesEvent(PapyrusEngineEvents.onReset, key: key)
            {
                enqueue(PapyrusScriptEvent(
                    target: key, functionName: PapyrusEngineEvents.onReset, arguments: []
                ))
                queued += 1
            }
        }
        return queued
    }
}
