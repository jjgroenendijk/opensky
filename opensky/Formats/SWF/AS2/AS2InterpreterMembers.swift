// Member reads and writes (milestone 8.3.2): the prototype-chain walk, the
// getter/setter invocation `Object.prototype.addProperty` installs, the
// `__get__name`/`__set__name` convention the ActionScript 2 compiler emits for
// class properties, and the fall-through to `AS2Host` for objects the engine
// owns.
//
// Reference: ECMA-262 3rd edition, sections 8.6.2.1 "[[Get]] (P)", 8.6.2.2
// "[[Put]] (P, V)", and 8.6.2.3 "[[CanPut]] (P)". The `addProperty` built-in
// and the `__get__`/`__set__` naming are Flash extensions with no
// specification; both are recorded here as observed.

import Foundation

extension AS2Interpreter {
    /// Prefix the compiler gives a class property's generated getter.
    static let getterPrefix = "__get__"
    /// Prefix the compiler gives a class property's generated setter.
    static let setterPrefix = "__set__"

    func getMember(_ name: String, of value: AS2Value, offset: Int) throws(AS2Fault) -> AS2Value {
        guard let object = value.objectValue else {
            return try primitiveMember(name, of: value, offset: offset)
        }
        if name == "__proto__" {
            return object.prototype.map(AS2Value.object) ?? .undefined
        }
        if object.isArray, name == "length" {
            return .integer(object.arrayLength ?? 0)
        }
        if let found = object.lookup(name) {
            return try read(found, receiver: value, offset: offset)
        }
        if let accessor = object.lookup(Self.getterPrefix + name)?.property.value.functionValue {
            return try call(accessor, thisValue: value, arguments: [], offset: offset)
        }
        if object.isHostBacked, let hosted = runtime.host.member(name, of: object) {
            return hosted
        }
        noteMissingMember(name, of: object)
        return .undefined
    }

    /// The prototype a method resolved on, which is the class a `super` inside
    /// that method walks up from (issue #136). Nil when the receiver owns the
    /// slot itself — there is no class in between, so the caller falls back to
    /// the receiver's own prototype.
    func memberHome(_ name: String, of value: AS2Value) -> AS2Object? {
        guard
            let object = value.objectValue,
            let found = object.lookup(name),
            found.owner !== object
        else {
            return nil
        }
        return found.owner
    }

    func setMember(
        _ name: String,
        of value: AS2Value,
        to newValue: AS2Value,
        offset: Int
    ) throws(AS2Fault) {
        guard let object = value.objectValue else {
            return
        }
        if name == "__proto__" {
            object.prototype = newValue.objectValue
            return
        }
        if object.isArray, name == "length" {
            try object.resizeArray(to: arrayLength(from: newValue))
            return
        }
        if let found = object.lookup(name), found.property.isVirtual {
            if let setter = found.property.setter {
                _ = try call(setter, thisValue: value, arguments: [newValue], offset: offset)
            }
            return
        }
        if let accessor = object.lookup(Self.setterPrefix + name)?.property.value.functionValue {
            _ = try call(accessor, thisValue: value, arguments: [newValue], offset: offset)
            return
        }
        writeMember(name, of: object, to: newValue)
    }

    private func writeMember(_ name: String, of object: AS2Object, to newValue: AS2Value) {
        // ECMA-262 8.6.2.3: an inherited read-only property blocks the write.
        if let found = object.lookup(name), found.property.flags.contains(.readOnly) {
            return
        }
        if object.isHostBacked, runtime.host.setMember(name, of: object, to: newValue) {
            return
        }
        object.assign(newValue, for: name)
    }

    /// Reads a resolved slot, invoking a getter with the original receiver so
    /// an inherited accessor sees the instance rather than the prototype.
    private func read(
        _ lookup: AS2PropertyLookup,
        receiver: AS2Value,
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        guard lookup.property.isVirtual else {
            return lookup.property.value
        }
        guard let getter = lookup.property.getter else {
            return .undefined
        }
        return try call(getter, thisValue: receiver, arguments: [], offset: offset)
    }

    /// Members of a primitive: `"text".length` plus whatever the matching
    /// built-in prototype carries. ActionScript reads these without boxing the
    /// primitive first.
    private func primitiveMember(
        _ name: String,
        of value: AS2Value,
        offset: Int
    ) throws(AS2Fault) -> AS2Value {
        if case let .string(text) = value, name == "length" {
            return .integer(text.utf16.count)
        }
        guard
            let prototype = runtime.prototype(for: value),
            let found = prototype.lookup(name)
        else {
            return .undefined
        }
        return try read(found, receiver: value, offset: offset)
    }

    private func arrayLength(from value: AS2Value) throws(AS2Fault) -> Int {
        let number = try toNumber(value)
        guard number.isFinite, number > 0 else {
            return 0
        }
        return min(Int(number), limits.stackDepth)
    }

    /// A missing member is only worth naming when it is a demand on the engine:
    /// an unimplemented member of a host-backed object, or an unknown global
    /// class such as `MovieClip` or `gfx`. A miss on an ordinary object is just
    /// ECMAScript producing `undefined`.
    private func noteMissingMember(_ name: String, of object: AS2Object) {
        guard object.isHostBacked || object === runtime.globalObject else {
            return
        }
        runtime.noteMissing(name)
    }
}
