// Variable resolution and the variable/member opcodes (milestone 8.3.2).
//
// A bare name resolves innermost-first through the scope chain, then through
// `this`, then through `_global`. That is the order Flash uses and the reason
// class-registration code can write `Object.registerClass(...)` with no
// qualification: `Object` is a `_global` member and nothing shadows it.
//
// `_root`, `_parent`, and `_level0` are display-list concepts, so they leave
// through `AS2Host` rather than being invented here.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionGetVariable" and "ActionSetVariable" (pp. 76-77),
// "ActionGetMember" and "ActionSetMember" (p. 87), "ActionDefineLocal" and
// "ActionDefineLocal2" (p. 89), "ActionDelete" and "ActionDelete2" (p. 88).

import Foundation

extension AS2Interpreter {
    func variableOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.getVariable:
            let name = try toString(frame.pop())
            try frame.push(getVariable(name, frame: frame, offset: record.offset))
        case AS2Opcode.setVariable:
            let value = frame.pop()
            let name = try toString(frame.pop())
            try setVariable(name, to: value, frame: frame, offset: record.offset)
        case AS2Opcode.getMember:
            let name = try toString(frame.pop())
            let object = frame.pop()
            try frame.push(getMember(name, of: object, offset: record.offset))
        case AS2Opcode.setMember:
            let value = frame.pop()
            let name = try toString(frame.pop())
            let object = frame.pop()
            try setMember(name, of: object, to: value, offset: record.offset)
        default:
            return try localOp(record, frame: frame)
        }
        return .next
    }

    private func localOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.defineLocal:
            let value = frame.pop()
            let name = try toString(frame.pop())
            frame.localScope.define(value, for: name)
        case AS2Opcode.defineLocal2:
            let name = try toString(frame.pop())
            if !frame.localScope.hasOwnProperty(name) {
                frame.localScope.define(.undefined, for: name)
            }
        case AS2Opcode.delete:
            let name = try toString(frame.pop())
            let object = frame.pop()
            let removed = object.objectValue?.removeProperty(name) ?? false
            try frame.push(.boolean(removed))
        case AS2Opcode.delete2:
            let name = try toString(frame.pop())
            try frame.push(.boolean(deleteVariable(name, frame: frame)))
        default:
            return nil
        }
        return .next
    }

    func getVariable(
        _ name: String,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        if let value = specialVariable(name, frame: frame) {
            return value
        }
        for scope in frame.scope.reversed() where scope.hasProperty(name) {
            return try getMember(name, of: .object(scope), offset: offset)
        }
        if let object = frame.thisValue.objectValue, object.hasProperty(name) {
            return try getMember(name, of: frame.thisValue, offset: offset)
        }
        if runtime.globalObject.hasProperty(name) {
            return try getMember(name, of: .object(runtime.globalObject), offset: offset)
        }
        runtime.noteMissing(name)
        return .undefined
    }

    func setVariable(
        _ name: String,
        to value: AS2Value,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) {
        for scope in frame.scope.reversed() where scope.hasProperty(name) {
            try setMember(name, of: .object(scope), to: value, offset: offset)
            return
        }
        // An assignment to a name nothing declared lands on the timeline, not
        // in the innermost activation — that is ActionScript, not ECMAScript.
        try setMember(name, of: .object(frame.target), to: value, offset: offset)
    }

    /// `this`, `super`, `_global`, the host-owned targets, and dotted or
    /// slash-separated paths. Returns nil for an ordinary name.
    private func specialVariable(_ name: String, frame: AS2Frame) -> AS2Value? {
        switch name {
        case "this":
            return frame.thisValue
        case "super":
            return superBinding(for: frame.thisValue).map(AS2Value.object) ?? .undefined
        case "_global":
            return .object(runtime.globalObject)
        default:
            break
        }
        if let special = AS2SpecialTarget(rawValue: name) {
            return hosted(runtime.host.specialObject(special, relativeTo: frame.target), name: name)
        }
        if name.contains(".") || name.contains("/") {
            return hosted(runtime.host.object(atPath: name, from: frame.target), name: name)
        }
        return nil
    }

    private func hosted(_ object: AS2Object?, name: String) -> AS2Value {
        guard let object else {
            runtime.noteMissing(name)
            return .undefined
        }
        return .object(object)
    }

    private func deleteVariable(_ name: String, frame: AS2Frame) -> Bool {
        for scope in frame.scope.reversed() where scope.hasOwnProperty(name) {
            return scope.removeProperty(name)
        }
        return frame.target.removeProperty(name)
    }
}
