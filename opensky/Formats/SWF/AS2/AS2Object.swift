// ActionScript 2 object model (milestone 8.3.2): a reference type with an
// insertion-ordered property table, a `__proto__` link, per-property
// attributes, and optional getter/setter pairs.
//
// Property attributes exist because vanilla menu code calls `ASSetPropFlags`
// 894 times while registering classes; getters and setters exist because it
// calls `addProperty` 1,535 times (measured by `openskycli swf action-sweep`,
// see docs/formats/swf.md). Both are undocumented Flash built-ins, so their
// behavior here is recorded as observed rather than cited to the spec — see
// docs/engine/as2-runtime.md.
//
// Reference: ECMA-262 3rd edition, section 8.6 "The Object Type" for the
// property model, section 8.6.2.1 "[[Get]]" and 8.6.2.2 "[[Put]]" for the
// prototype-chain walk, and section 4.3.5 "Prototype".

import Foundation

/// The attributes `ASSetPropFlags` toggles. The bit values are the ones the
/// Flash built-in has always used; the SWF specification does not define this
/// function, so this mapping is observed, not specified.
nonisolated struct AS2PropertyFlags: OptionSet, Equatable {
    let rawValue: UInt8

    /// Hidden from `ActionEnumerate2` (0x55) and `for (var name in object)`.
    static let dontEnumerate = AS2PropertyFlags(rawValue: 1)
    /// `ActionDelete` (0x3A) leaves the property in place.
    static let dontDelete = AS2PropertyFlags(rawValue: 2)
    /// Assignment is ignored.
    static let readOnly = AS2PropertyFlags(rawValue: 4)
}

/// One slot in an object's property table. A slot is either a stored value or a
/// getter/setter pair installed by `Object.prototype.addProperty`; the
/// interpreter, not the object, invokes the accessors because calling needs an
/// execution context.
nonisolated struct AS2Property {
    var value: AS2Value = .undefined
    var flags: AS2PropertyFlags = []
    var getter: AS2Object?
    var setter: AS2Object?

    var isVirtual: Bool {
        getter != nil || setter != nil
    }
}

/// Where a name resolved on a prototype chain: the object that owns the slot
/// and the slot itself.
nonisolated struct AS2PropertyLookup {
    let owner: AS2Object
    let property: AS2Property
}

/// Receives object-table mutations that a host needs to index. The interpreter
/// remains unaware of what the observer represents.
nonisolated protocol AS2ObjectMutationObserver: AnyObject {
    func object(_ object: AS2Object, didMutateProperty name: String)
    func objectDidMutatePrototype(_ object: AS2Object)
}

/// An ActionScript 2 object. Functions are objects with a `callable`; arrays
/// are objects with a live `arrayLength`; display objects (a later milestone)
/// are objects carrying a `hostPayload`.
nonisolated final class AS2Object {
    /// `__proto__`. Member lookup walks this chain.
    var prototype: AS2Object? {
        didSet {
            mutationObserver?.objectDidMutatePrototype(self)
        }
    }

    /// Optional weak hook for host indexes derived from dynamic members.
    weak var mutationObserver: (any AS2ObjectMutationObserver)?
    /// Non-nil when this object can be called or constructed.
    var callable: AS2Callable?
    /// Opaque engine-owned payload — the seam a later milestone uses to back an
    /// object with a display object. The interpreter never inspects it, but its
    /// presence routes unresolved members to `AS2Host`.
    var hostPayload: AnyObject?
    /// Overrides what `ActionTypeOf` reports, so a host-backed object can
    /// answer `"movieclip"`.
    var typeOverride: String?
    /// Set on a `super` binding: calls through this object bind `this` to the
    /// stored value instead of to the binding itself.
    var superThis: AS2Value?
    /// Set on a `super` binding: the prototype the superclass constructor this
    /// binding calls belongs to. It becomes the called frame's
    /// `AS2Frame.basePrototype`, so the next `super` up the chain resolves one
    /// level higher instead of re-entering the same constructor (issue #136).
    var superBase: AS2Object?
    /// Non-nil for array-like objects; one past the highest assigned index.
    private(set) var arrayLength: Int?

    private var order: [String] = []
    private var table: [String: AS2Property] = [:]

    init(prototype: AS2Object? = nil) {
        self.prototype = prototype
    }

    var isFunction: Bool {
        callable != nil
    }

    var isArray: Bool {
        arrayLength != nil
    }

    /// True when a host owns this object's real state, so member misses are
    /// worth asking `AS2Host` about.
    var isHostBacked: Bool {
        hostPayload != nil
    }

    var typeName: String {
        if let typeOverride {
            return typeOverride
        }
        return isFunction ? "function" : "object"
    }

    /// Own property names in insertion order.
    var ownPropertyNames: [String] {
        order
    }

    func ownProperty(_ name: String) -> AS2Property? {
        table[name]
    }

    func hasOwnProperty(_ name: String) -> Bool {
        table[name] != nil
    }

    /// Walks `__proto__` until the name resolves. Cycles are bounded by
    /// `prototypeChainLimit` so a malformed `__proto__` assignment cannot hang
    /// the interpreter.
    func lookup(_ name: String) -> AS2PropertyLookup? {
        var current: AS2Object? = self
        var steps = 0
        while let object = current, steps < AS2Object.prototypeChainLimit {
            if let property = object.table[name] {
                return AS2PropertyLookup(owner: object, property: property)
            }
            current = object.prototype
            steps += 1
        }
        return nil
    }

    func hasProperty(_ name: String) -> Bool {
        lookup(name) != nil
    }

    /// Installs or replaces a slot, ignoring `readOnly` — the path natives and
    /// the object model itself use.
    func define(_ value: AS2Value, for name: String, flags: AS2PropertyFlags = []) {
        var property = table[name] ?? AS2Property()
        property.value = value
        property.flags = flags
        property.getter = nil
        property.setter = nil
        store(property, for: name)
    }

    /// Assignment from bytecode. Returns false when the slot is read-only, so
    /// the caller can leave the value untouched without raising an error —
    /// ActionScript assignment to a read-only property fails silently.
    @discardableResult
    func assign(_ value: AS2Value, for name: String) -> Bool {
        var property = table[name] ?? AS2Property()
        if property.flags.contains(.readOnly) {
            return false
        }
        property.value = value
        store(property, for: name)
        return true
    }

    /// `Object.prototype.addProperty(name, getter, setter)`. A getter is
    /// mandatory in Flash; a nil setter makes the property read-only.
    @discardableResult
    func addAccessor(name: String, getter: AS2Object?, setter: AS2Object?) -> Bool {
        guard getter != nil || setter != nil else {
            return false
        }
        var property = table[name] ?? AS2Property()
        property.value = .undefined
        property.getter = getter
        property.setter = setter
        store(property, for: name)
        return true
    }

    @discardableResult
    func removeProperty(_ name: String) -> Bool {
        guard let property = table[name] else {
            return false
        }
        if property.flags.contains(.dontDelete) {
            return false
        }
        table[name] = nil
        order.removeAll { $0 == name }
        mutationObserver?.object(self, didMutateProperty: name)
        return true
    }

    private func store(_ property: AS2Property, for name: String) {
        if table[name] == nil {
            order.append(name)
            noteArrayIndex(name)
        }
        table[name] = property
        mutationObserver?.object(self, didMutateProperty: name)
    }

    /// Replaces a slot's attributes without touching its value.
    func setFlags(_ flags: AS2PropertyFlags, for name: String) {
        guard var property = table[name] else {
            return
        }
        property.flags = flags
        table[name] = property
    }

    /// Marks this object as array-like with the given length.
    func markArray(length: Int) {
        arrayLength = max(0, length)
    }

    private func noteArrayIndex(_ name: String) {
        guard let length = arrayLength, let index = AS2Object.arrayIndex(name) else {
            return
        }
        if index >= length {
            arrayLength = index + 1
        }
    }

    /// A canonical array index: decimal digits with no sign, no leading zero
    /// beyond `"0"` itself, and inside `Int32` range.
    static func arrayIndex(_ name: String) -> Int? {
        guard !name.isEmpty, name.allSatisfy(\.isASCII), name.allSatisfy(\.isNumber) else {
            return nil
        }
        if name.count > 1, name.hasPrefix("0") {
            return nil
        }
        guard let value = Int(name), value <= Int(Int32.max) else {
            return nil
        }
        return value
    }

    /// Guards against a `__proto__` cycle built by malformed bytecode.
    static let prototypeChainLimit = 64
}
