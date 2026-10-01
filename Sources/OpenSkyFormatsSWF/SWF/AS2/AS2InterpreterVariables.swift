// Variable resolution and the variable and member opcodes. A bare name looks
// in the scope chain, then `this`, then `_global`, as Flash does. `_root`,
// `_parent`, and `_level0` go to `AS2Host`. Spec: SWF v19 chapter 5.

import Foundation

nonisolated extension AS2Interpreter {
    public func variableOp(
        _ record: SWFActionRecord,
        frame: AS2Frame
    ) throws(AS2Fault) -> AS2Flow? {
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

    public func getVariable(
        _ name: String,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        if let value = specialVariable(name, frame: frame) {
            return value
        }
        if let value = try scopedVariable(name, frame: frame, offset: offset) {
            return value
        }
        if let value = try qualifiedVariable(name, frame: frame, offset: offset) {
            return value
        }
        runtime.noteMissing(name)
        return .undefined
    }

    /// The ordinary chain: innermost scope, then `this`, then `_global`. Returns
    /// nil rather than tallying, so a qualified name can try again.
    private func scopedVariable(
        _ name: String,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) -> AS2Value? {
        for scope in frame.scope.reversed() where scope.hasProperty(name) {
            return try getMember(name, of: .object(scope), offset: offset)
        }
        if let object = frame.thisValue.objectValue, object.hasProperty(name) {
            return try getMember(name, of: frame.thisValue, offset: offset)
        }
        if runtime.globalObject.hasProperty(name) {
            return try getMember(name, of: .object(runtime.globalObject), offset: offset)
        }
        return nil
    }

    /// A name with `.` or `/` separators. Dotted names walk members from the
    /// head first, so `gfx.controls.Button` reaches `_global`; only then the
    /// display path resolver runs. The other order breaks CLIK class lookups.
    private func qualifiedVariable(
        _ name: String,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) -> AS2Value? {
        guard name.contains(".") || name.contains("/") else {
            return nil
        }
        if !name.contains("/"), let value = try dottedVariable(name, frame: frame, offset: offset) {
            return value
        }
        guard let object = runtime.host.object(atPath: name, from: frame.target) else {
            return nil
        }
        return .object(object)
    }

    private func dottedVariable(
        _ name: String,
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) -> AS2Value? {
        var components = name.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count > 1, !components.contains(where: \.isEmpty) else {
            return nil
        }
        let first = components.removeFirst()
        var head = specialVariable(first, frame: frame)
        if head == nil {
            head = try scopedVariable(first, frame: frame, offset: offset)
        }
        guard var value = head else {
            return nil
        }
        for component in components {
            guard value.objectValue != nil else {
                return nil
            }
            value = try getMember(component, of: value, offset: offset)
        }
        return value == .undefined ? nil : value
    }

    public func setVariable(
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

    /// `this`, `super`, `_global`, and the host-owned targets `_root`,
    /// `_parent`, and `_level0`. Returns nil for an ordinary name; qualified
    /// names are resolved by `qualifiedVariable`.
    private func specialVariable(_ name: String, frame: AS2Frame) -> AS2Value? {
        switch name {
        case "this":
            return frame.thisValue
        case "super":
            return superBinding(for: frame.thisValue, base: frame.basePrototype)
                .map(AS2Value.object) ?? .undefined
        case "_global":
            return .object(runtime.globalObject)
        default:
            break
        }
        if let special = AS2SpecialTarget(rawValue: name) {
            guard let object = runtime.host.specialObject(special, relativeTo: frame.target) else {
                runtime.noteMissing(name)
                return .undefined
            }
            return .object(object)
        }
        return nil
    }

    private func deleteVariable(_ name: String, frame: AS2Frame) -> Bool {
        for scope in frame.scope.reversed() where scope.hasOwnProperty(name) {
            return scope.removeProperty(name)
        }
        return frame.target.removeProperty(name)
    }
}
