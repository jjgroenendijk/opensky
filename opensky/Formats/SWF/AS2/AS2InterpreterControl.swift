// Branches, and the opcodes that leave through the host seam (milestone
// 8.3.2).
//
// `ActionStop`, `ActionPlay`, `ActionGotoFrame`, `ActionGoToLabel`,
// `ActionGetProperty`, `ActionSetProperty`, and `ActionTargetPath` are all
// display-list operations. The interpreter decodes them fully and hands them to
// `AS2Host`; the display objects that answer them arrive in a later milestone.
// A host that declines becomes a tally entry, never an error.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionJump" (p. 84) and "ActionIf" (p. 85) for the branch offset
// being relative to the end of the branch action, plus "ActionPlay",
// "ActionStop", "ActionGotoFrame", "ActionGoToLabel", "ActionGetProperty",
// "ActionSetProperty", "ActionTargetPath", and "ActionTrace".

import Foundation

nonisolated extension AS2Interpreter {
    func controlOp(
        _ record: SWFActionRecord,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow? {
        guard case let .branch(offset) = record.operands else {
            return nil
        }
        switch record.code {
        case AS2Opcode.jump:
            let target = record.endOffset + Int(offset)
            return try .jump(recordIndex(forByteOffset: target, frame: frame))
        case AS2Opcode.branchIfTrue:
            let condition = frame.pop()
            guard toBoolean(condition) else {
                return .next
            }
            let target = record.endOffset + Int(offset)
            return try .jump(recordIndex(forByteOffset: target, frame: frame))
        default:
            return nil
        }
    }

    func hostOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.stop:
            runtime.host.perform(.stop, target: frame.target)
        case AS2Opcode.play:
            runtime.host.perform(.play, target: frame.target)
        case AS2Opcode.gotoFrame:
            guard case let .gotoFrame(number) = record.operands else {
                return .next
            }
            runtime.host.perform(.gotoFrame(Int(number)), target: frame.target)
        case AS2Opcode.goToLabel:
            guard case let .goToLabel(label) = record.operands else {
                return .next
            }
            runtime.host.perform(.gotoLabel(label), target: frame.target)
        case AS2Opcode.trace:
            let message = try toString(frame.pop())
            runtime.trace(message)
        default:
            return try displayOp(record, frame: frame)
        }
        return .next
    }

    private func displayOp(
        _ record: SWFActionRecord,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.getProperty:
            let index = try toNumber(frame.pop())
            let target = frame.pop()
            try frame.push(hostProperty(index, of: target))
        case AS2Opcode.setProperty:
            let value = frame.pop()
            let index = try toNumber(frame.pop())
            let target = frame.pop()
            setHostProperty(index, of: target, to: value)
        case AS2Opcode.targetPath:
            let value = frame.pop()
            try frame.push(targetPath(of: value))
        default:
            return nil
        }
        return .next
    }

    private func hostProperty(_ index: Double, of target: AS2Value) -> AS2Value {
        guard let property = displayProperty(index) else {
            return .undefined
        }
        guard let value = runtime.host.property(property, of: target) else {
            runtime.noteMissing(property.actionScriptName)
            return .undefined
        }
        return value
    }

    private func setHostProperty(_ index: Double, of target: AS2Value, to value: AS2Value) {
        guard let property = displayProperty(index) else {
            return
        }
        if !runtime.host.setProperty(property, of: target, to: value) {
            runtime.noteMissing(property.actionScriptName)
        }
    }

    private func targetPath(of value: AS2Value) -> AS2Value {
        guard let object = value.objectValue else {
            return .undefined
        }
        guard let path = runtime.host.targetPath(of: object) else {
            runtime.noteMissing("_target")
            return .undefined
        }
        return .string(path)
    }

    private func displayProperty(_ index: Double) -> AS2DisplayProperty? {
        guard index.isFinite, index >= 0 else {
            return nil
        }
        return AS2DisplayProperty(rawValue: Int(index))
    }
}
