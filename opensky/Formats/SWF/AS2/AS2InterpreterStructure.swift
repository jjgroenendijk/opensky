// Object-literal, enumeration, and class-relationship opcodes (milestone
// 8.3.2). These are what vanilla menu code spends its `DoInitAction` blocks on:
// 455 `ActionExtends`, 456 `ActionInstanceOf`, and 140 `ActionCastOp` across
// the 53 vanilla movies.
//
// The literal opcodes pop their elements in the order the compiler pushed
// them: an array or object literal is emitted back to front, so the first value
// popped is element zero.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionInitArray" and "ActionInitObject" (p. 86),
// "ActionEnumerate2" (p. 106), "ActionTypeOf" (p. 87), "ActionInstanceOf"
// (p. 106), "ActionCastOp" (p. 113), and "ActionExtends" (p. 114).

import Foundation

nonisolated extension AS2Interpreter {
    func structureOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.initObject:
            try frame.push(.object(initObject(frame)))
        case AS2Opcode.initArray:
            try frame.push(.object(initArray(frame)))
        case AS2Opcode.enumerate2:
            try enumerate(frame)
        case AS2Opcode.typeOf:
            let value = frame.pop()
            try frame.push(.string(value.typeName))
        case AS2Opcode.instanceOf:
            let constructor = frame.pop()
            let value = frame.pop()
            try frame.push(.boolean(isInstance(value, of: constructor)))
        case AS2Opcode.castOp:
            let constructor = frame.pop()
            let value = frame.pop()
            try frame.push(isInstance(value, of: constructor) ? value : .null)
        case AS2Opcode.extends:
            try applyExtends(frame)
        default:
            return nil
        }
        return .next
    }

    private func initObject(_ frame: AS2Frame) throws(AS2Fault) -> AS2Object {
        let count = try toArgumentCount(frame.pop())
        let object = runtime.makeObject()
        for _ in 0 ..< count {
            let value = frame.pop()
            let name = try toString(frame.pop())
            object.define(value, for: name)
        }
        return object
    }

    private func initArray(_ frame: AS2Frame) throws(AS2Fault) -> AS2Object {
        let count = try toArgumentCount(frame.pop())
        let array = runtime.makeArray()
        for index in 0 ..< count {
            array.setElement(frame.pop(), at: index)
        }
        return array
    }

    /// Pushes the sentinel `null` and then every enumerable name, last name
    /// first, so the consuming loop pops them in insertion order. ECMAScript
    /// leaves for-in order implementation-defined; fixing it here keeps a menu
    /// deterministic run to run.
    private func enumerate(_ frame: AS2Frame) throws(AS2Fault) {
        let value = frame.pop()
        try frame.push(.null)
        guard let object = value.objectValue else {
            return
        }
        for name in object.enumerableNames().reversed() {
            try frame.push(.string(name))
        }
    }

    /// Walks the object's `__proto__` chain looking for the constructor's
    /// `prototype`.
    func isInstance(_ value: AS2Value, of constructor: AS2Value) -> Bool {
        guard
            let object = value.objectValue,
            let target = constructor.objectValue?
                .lookup("prototype")?.property.value.objectValue
        else {
            return false
        }
        var current = object.prototype
        var steps = 0
        while let candidate = current, steps < AS2Object.prototypeChainLimit {
            if candidate === target {
                return true
            }
            current = candidate.prototype
            steps += 1
        }
        return false
    }

    /// `ActionExtends`: builds the bridge prototype that links a subclass to
    /// its superclass and records the superclass as `__constructor__`, which is
    /// how `super` finds the base constructor at call time.
    private func applyExtends(_ frame: AS2Frame) throws(AS2Fault) {
        let superclass = frame.pop()
        let subclass = frame.pop()
        guard
            let superObject = superclass.objectValue,
            let subObject = subclass.objectValue
        else {
            return
        }
        let base = superObject.lookup("prototype")?.property.value.objectValue
        let bridge = AS2Object(prototype: base)
        bridge.define(superclass, for: "constructor", flags: [.dontEnumerate, .dontDelete])
        bridge.define(superclass, for: "__constructor__", flags: [.dontEnumerate, .dontDelete])
        subObject.define(.object(bridge), for: "prototype")
    }

    /// The `super` binding a method sees: an empty object whose prototype is
    /// the superclass prototype and whose calls re-bind `this` to the original
    /// receiver. Nil when there is no prototype chain to climb.
    ///
    /// `base` is the prototype of the class whose method is running, which the
    /// frame carries. Deriving the binding from the receiver instead would pin
    /// it to `this.__proto__` for the whole chain, so the base constructor of a
    /// three-level hierarchy would call itself until the depth cap fired
    /// (issue #136). Only the class's own `__constructor__` counts: the
    /// inherited one belongs to the superclass and would name the wrong parent.
    func superBinding(for thisValue: AS2Value, base: AS2Object? = nil) -> AS2Object? {
        guard let home = base ?? thisValue.objectValue?.prototype else {
            return nil
        }
        let binding = AS2Object(prototype: home.prototype)
        binding.superThis = thisValue
        binding.superBase = home.prototype
        binding.callable = home.ownProperty("__constructor__")?.value.objectValue?.callable
        return binding
    }
}
