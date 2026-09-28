// Stack, register, and constant-pool opcodes (milestone 8.3.2).
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionPush" (p. 69), "ActionPop" (p. 70), "ActionPushDuplicate"
// and "ActionStackSwap" (p. 91), "ActionStoreRegister" (p. 90), and
// "ActionConstantPool" (p. 91).

import Foundation

nonisolated extension AS2Interpreter {
    func stackOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.push:
            guard case let .push(values) = record.operands else {
                return .next
            }
            for value in values {
                try frame.push(resolve(value, frame: frame))
            }
        case AS2Opcode.pop:
            _ = frame.pop()
        case AS2Opcode.pushDuplicate:
            let duplicate = frame.peek()
            try frame.push(duplicate)
        case AS2Opcode.stackSwap:
            let top = frame.pop()
            let under = frame.pop()
            try frame.push(top)
            try frame.push(under)
        case AS2Opcode.storeRegister:
            guard case let .storeRegister(index) = record.operands else {
                return .next
            }
            // The specification is explicit that the value stays on the stack.
            let stored = frame.peek()
            frame.setRegister(Int(index), to: stored)
        case AS2Opcode.constantPool:
            guard case let .constantPool(strings) = record.operands else {
                return .next
            }
            frame.constantPool = strings
        default:
            return nil
        }
        return .next
    }

    /// Turns one parsed `ActionPush` literal into a runtime value. Register and
    /// constant-pool references resolve against the frame, so the same record
    /// pushed inside two different functions reads two different values.
    func resolve(_ value: SWFActionValue, frame: AS2Frame) -> AS2Value {
        switch value {
        case let .string(text): .string(text)
        case let .float(number): .number(Double(number))
        case .null: .null
        case .undefined: .undefined
        case let .register(index): frame.register(Int(index))
        case let .boolean(flag): .boolean(flag)
        case let .double(number): .number(number)
        case let .integer(number): .number(Double(number))
        case let .constant8(index): frame.constant(Int(index))
        case let .constant16(index): frame.constant(Int(index))
        }
    }
}
