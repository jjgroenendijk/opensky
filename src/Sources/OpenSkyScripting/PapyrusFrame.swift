// One explicitly stacked Papyrus function invocation.

import Foundation
public import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated enum PapyrusFrameCompletion: Sendable {
    case root
    case assign(PexValue)
    case discard
}

final class PapyrusFrame {
    let owner: PapyrusScriptIndex
    let compiled: PapyrusCompiledFunction
    let instanceHandle: PapyrusObjectHandle?
    let completion: PapyrusFrameCompletion

    /// Parameters and locals, in `compiled`'s slot order.
    private(set) var slots: [PapyrusValue]
    var instructionIndex = 0

    init(
        owner: PapyrusScriptIndex,
        compiled: PapyrusCompiledFunction,
        instanceHandle: PapyrusObjectHandle?,
        completion: PapyrusFrameCompletion
    ) {
        self.owner = owner
        self.compiled = compiled
        self.instanceHandle = instanceHandle
        self.completion = completion
        slots = compiled.slotDefaults
    }

    var ownerScript: PexObject {
        owner.script
    }

    var function: PexFunction {
        compiled.function
    }

    var defaultReturnValue: PapyrusValue {
        compiled.defaultReturnValue
    }

    func setSlot(_ slot: Int, to value: PapyrusValue) {
        slots[slot] = value
    }
}
