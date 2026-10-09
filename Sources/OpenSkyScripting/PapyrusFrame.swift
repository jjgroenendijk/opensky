// One explicitly stacked Papyrus function invocation.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated public enum PapyrusFrameCompletion: Sendable {
    case root
    case assign(PexValue)
    case discard
}

public final class PapyrusFrame {
    public let owner: PapyrusScriptIndex
    public let compiled: PapyrusCompiledFunction
    public let instanceHandle: PapyrusObjectHandle?
    public let completion: PapyrusFrameCompletion

    /// Parameters and locals, in `compiled`'s slot order.
    public private(set) var slots: [PapyrusValue]
    public var instructionIndex = 0

    public init(
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

    public var ownerScript: PexObject {
        owner.script
    }

    public var function: PexFunction {
        compiled.function
    }

    public var defaultReturnValue: PapyrusValue {
        compiled.defaultReturnValue
    }

    public func localValue(named name: String) -> PapyrusValue? {
        compiled.binding(for: name).slot.map { slots[$0] }
    }

    public func localType(named name: String) -> PapyrusType? {
        compiled.binding(for: name).slot.map { compiled.slotTypes[$0] }
    }

    public func setLocalValue(_ value: PapyrusValue, named name: String) -> Bool {
        guard let slot = compiled.binding(for: name).slot else {
            return false
        }
        slots[slot] = value
        return true
    }

    public func setSlot(_ slot: Int, to value: PapyrusValue) {
        slots[slot] = value
    }
}
