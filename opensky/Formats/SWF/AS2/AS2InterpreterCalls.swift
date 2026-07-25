// Call and construction opcodes (milestone 8.3.2).
//
// All four call opcodes share the same operand shape: the callee (a name, or a
// name plus an object), then the argument count, then that many arguments with
// the first argument on top of the stack.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionCallFunction" (p. 82), "ActionCallMethod" and
// "ActionNewMethod" (p. 88), "ActionNewObject" (p. 86), and "ActionReturn"
// (p. 90).

import Foundation

extension AS2Interpreter {
    func callOp(
        _ record: SWFActionRecord,
        frame: AS2Frame,
        range: Range<Int>
    ) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.callFunction:
            try callNamedFunction(frame, offset: record.offset)
        case AS2Opcode.callMethod:
            try callNamedMethod(frame, offset: record.offset)
        case AS2Opcode.newObject:
            try constructNamed(frame, offset: record.offset)
        case AS2Opcode.newMethod:
            try constructMethod(frame, offset: record.offset)
        case AS2Opcode.returnValue:
            return .done(frame.pop())
        case AS2Opcode.defineFunction, AS2Opcode.defineFunction2:
            return try defineFunction(record, frame: frame, range: range)
        default:
            return nil
        }
        return .next
    }

    private func callNamedFunction(_ frame: AS2Frame, offset: Int) throws(AS2Fault) {
        let name = try toString(frame.pop())
        let arguments = try popArguments(frame)
        let callee = try getVariable(name, frame: frame, offset: offset)
        guard let function = callee.functionValue else {
            runtime.noteMissing(name)
            try frame.push(.undefined)
            return
        }
        let result = try call(
            function, thisValue: frame.thisValue, arguments: arguments, offset: offset
        )
        try frame.push(result)
    }

    private func callNamedMethod(_ frame: AS2Frame, offset: Int) throws(AS2Fault) {
        let nameValue = frame.pop()
        let receiver = frame.pop()
        let arguments = try popArguments(frame)
        var name = ""
        if nameValue != .undefined {
            name = try toString(nameValue)
        }
        // An empty method name calls the receiver itself, which is how
        // `super(...)` reaches the base constructor.
        var callee = receiver
        var defaultThis = AS2Value.undefined
        if !name.isEmpty {
            callee = try getMember(name, of: receiver, offset: offset)
            defaultThis = receiver
        }
        let thisValue = receiver.objectValue?.superThis ?? defaultThis
        guard let function = callee.functionValue else {
            runtime.noteMissing(name.isEmpty ? "[[call]]" : name)
            try frame.push(.undefined)
            return
        }
        let result = try call(
            function, thisValue: thisValue, arguments: arguments, offset: offset
        )
        try frame.push(result)
    }

    private func constructNamed(_ frame: AS2Frame, offset: Int) throws(AS2Fault) {
        let name = try toString(frame.pop())
        let arguments = try popArguments(frame)
        let callee = try getVariable(name, frame: frame, offset: offset)
        try pushConstructed(callee, name: name, arguments: arguments, frame: frame, offset: offset)
    }

    private func constructMethod(_ frame: AS2Frame, offset: Int) throws(AS2Fault) {
        let name = try toString(frame.pop())
        let receiver = frame.pop()
        let arguments = try popArguments(frame)
        var callee = receiver
        if !name.isEmpty {
            callee = try getMember(name, of: receiver, offset: offset)
        }
        try pushConstructed(callee, name: name, arguments: arguments, frame: frame, offset: offset)
    }

    private func pushConstructed(
        _ callee: AS2Value,
        name: String,
        arguments: [AS2Value],
        frame: AS2Frame,
        offset: Int
    ) throws(AS2Fault) {
        guard let constructor = callee.functionValue else {
            runtime.noteMissing(name)
            try frame.push(.undefined)
            return
        }
        try frame.push(construct(constructor, arguments: arguments, offset: offset))
    }

    /// `new`: a fresh object whose prototype is the constructor's `prototype`,
    /// handed to the constructor as `this`. A constructor that returns an
    /// object of its own wins, which is what the `Array` and `Object`
    /// built-ins rely on.
    func construct(
        _ constructor: AS2Object,
        arguments: [AS2Value],
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        let prototype = constructor.lookup("prototype")?.property.value.objectValue
        let instance = AS2Object(prototype: prototype ?? runtime.objectPrototype)
        instance.define(
            .object(constructor), for: "__constructor__", flags: [.dontEnumerate, .dontDelete]
        )
        let result = try call(
            constructor,
            thisValue: .object(instance),
            arguments: arguments,
            offset: offset,
            constructing: true
        )
        if let returned = result.objectValue {
            return .object(returned)
        }
        return .object(instance)
    }

    /// Pops the argument count and then the arguments. The first argument is on
    /// top of the stack, so the popped order is already the call order.
    func popArguments(_ frame: AS2Frame) throws(AS2Fault) -> [AS2Value] {
        let count = try toArgumentCount(frame.pop())
        var values: [AS2Value] = []
        values.reserveCapacity(min(count, 32))
        for _ in 0 ..< count {
            values.append(frame.pop())
        }
        return values
    }
}
