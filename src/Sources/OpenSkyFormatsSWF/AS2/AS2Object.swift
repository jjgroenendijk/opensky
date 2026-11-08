// ActionScript 2 object: ordered properties, a `__proto__` link, attributes,
// and getter/setter pairs. Vanilla menus need attributes for `ASSetPropFlags`
// and accessors for `addProperty`; both are observed behavior.
// Spec: ECMA-262 3rd ed. section 8.6. See docs/engine/as2-runtime.md.

import Foundation

/// The attributes `ASSetPropFlags` toggles. The bit values are the ones the
/// Flash built-in has always used; the SWF specification does not define this
/// function, so this mapping is observed, not specified.
nonisolated public struct AS2PropertyFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Hidden from `ActionEnumerate2` (0x55) and `for (var name in object)`.
    public static let dontEnumerate = AS2PropertyFlags(rawValue: 1)
    /// `ActionDelete` (0x3A) leaves the property in place.
    public static let dontDelete = AS2PropertyFlags(rawValue: 2)
    /// Assignment is ignored.
    public static let readOnly = AS2PropertyFlags(rawValue: 4)
}

/// One slot in an object's property table. A slot is either a stored value or a
/// getter/setter pair installed by `Object.prototype.addProperty`; the
/// interpreter, not the object, invokes the accessors because calling needs an
/// execution context.
nonisolated public struct AS2Property {
    public var value: AS2Value = .undefined
    public var flags: AS2PropertyFlags = []
    public var getter: AS2Object?
    public var setter: AS2Object?

    public var isVirtual: Bool {
        getter != nil || setter != nil
    }
}

/// Where a name resolved on a prototype chain: the object that owns the slot
/// and the slot itself.
nonisolated public struct AS2PropertyLookup {
    public let owner: AS2Object
    public let property: AS2Property
}

/// Receives object-table mutations that a host needs to index. The interpreter
/// remains unaware of what the observer represents.
nonisolated public protocol AS2ObjectMutationObserver: AnyObject {
    func object(_ object: AS2Object, didMutateProperty name: String)
    func objectDidMutatePrototype(_ object: AS2Object)
}

/// An ActionScript 2 object. Functions are objects with a `callable`; arrays
/// are objects with a live `arrayLength`; display objects (a later milestone)
/// are objects carrying a `hostPayload`.
nonisolated public final class AS2Object {
    /// `__proto__`. Member lookup walks this chain.
    public var prototype: AS2Object? {
        didSet {
            mutationObserver?.objectDidMutatePrototype(self)
        }
    }

    /// Optional weak hook for host indexes derived from dynamic members.
    public weak var mutationObserver: (any AS2ObjectMutationObserver)?
    /// Non-nil when this object can be called or constructed.
    public var callable: AS2Callable?
    /// Opaque engine-owned payload — the seam a later milestone uses to back an
    /// object with a display object. The interpreter never inspects it, but its
    /// presence routes unresolved members to `AS2Host`.
    public var hostPayload: AnyObject?
    /// Overrides what `ActionTypeOf` reports, so a host-backed object can
    /// answer `"movieclip"`.
    public var typeOverride: String?
    /// Set on a `super` binding: calls through this object bind `this` to the
    /// stored value instead of to the binding itself.
    public var superThis: AS2Value?
    /// On a `super` binding: the prototype of the superclass constructor it
    /// calls. It becomes the called frame's `AS2Frame.basePrototype`, so the
    /// next `super` resolves one level higher.
    public var superBase: AS2Object?
    /// Non-nil for array-like objects; one past the highest assigned index.
    public private(set) var arrayLength: Int?

    private var order: [String] = []
    private var table: [String: AS2Property] = [:]

    public init(prototype: AS2Object? = nil) {
        self.prototype = prototype
    }

    public var isFunction: Bool {
        callable != nil
    }

    public var isArray: Bool {
        arrayLength != nil
    }

    /// True when a host owns this object's real state, so member misses are
    /// worth asking `AS2Host` about.
    public var isHostBacked: Bool {
        hostPayload != nil
    }

    public var typeName: String {
        if let typeOverride {
            return typeOverride
        }
        return isFunction ? "function" : "object"
    }

    /// Own property names in insertion order.
    public var ownPropertyNames: [String] {
        order
    }

    public func ownProperty(_ name: String) -> AS2Property? {
        table[name]
    }

    public func hasOwnProperty(_ name: String) -> Bool {
        table[name] != nil
    }

    /// Walks `__proto__` until the name resolves. Cycles are bounded by
    /// `prototypeChainLimit` so a malformed `__proto__` assignment cannot hang
    /// the interpreter.
    public func lookup(_ name: String) -> AS2PropertyLookup? {
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

    public func hasProperty(_ name: String) -> Bool {
        lookup(name) != nil
    }

    /// Installs or replaces a slot, ignoring `readOnly` — the path natives and
    /// the object model itself use.
    public func define(_ value: AS2Value, for name: String, flags: AS2PropertyFlags = []) {
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
    public func assign(_ value: AS2Value, for name: String) -> Bool {
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
    public func addAccessor(name: String, getter: AS2Object?, setter: AS2Object?) -> Bool {
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
    public func removeProperty(_ name: String) -> Bool {
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
    public func setFlags(_ flags: AS2PropertyFlags, for name: String) {
        guard var property = table[name] else {
            return
        }
        property.flags = flags
        table[name] = property
    }

    /// Marks this object as array-like with the given length.
    public func markArray(length: Int) {
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
    public static func arrayIndex(_ name: String) -> Int? {
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
    public static let prototypeChainLimit = 64
}
