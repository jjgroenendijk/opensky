// The value a fake answers before a test sets one. A type with no obvious empty value
// gets none: the fake then stores an optional and stops the test that reads it unset.

import SwiftSyntax

let numberTypes: Set = [
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Float", "Double", "CGFloat", "TimeInterval"
]

struct TypeContext {
    /// Associated type name to the fake that stands in for it.
    var associated: [String: String]
    /// Every port the generator writes a fake for.
    var ports: Set<String>
    /// Fakes that stay on the main actor, which a nonisolated fake cannot build by default.
    var mainActorFakes: Set<String> = []
    var isNonisolated = true
    /// Generic parameter names of the function being written.
    var generics: Set<String> = []

    /// `any CombatPort` and `CombatPort` become the fake's name; an associated type its fake.
    func fake(for type: TypeSyntax) -> String? {
        var text = type.trimmedDescription
        if text.hasPrefix("any ") {
            text.removeFirst(4)
        }
        if let fake = associated[text] {
            return fake
        }
        return ports.contains(text) ? "Fake\(text)" : nil
    }

    func emptyValue(for type: TypeSyntax) -> String? {
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return "nil"
        }
        if type.is(ArrayTypeSyntax.self) {
            return "[]"
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "[:]"
        }
        if let fake = fake(for: type) {
            return isNonisolated && mainActorFakes.contains(fake) ? nil : "\(fake)()"
        }
        let text = type.trimmedDescription
        if numberTypes.contains(text) {
            return "0"
        }
        switch text {
        case "Bool": return "false"
        case "String": return "\"\""
        case "Void", "()": return "()"
        default: break
        }
        if text.hasPrefix("Set<") {
            return "[]"
        }
        if text.hasPrefix("SIMD") {
            return ".zero"
        }
        return nil
    }

    func mentionsGeneric(_ type: TypeSyntax) -> Bool {
        type.tokens(viewMode: .sourceAccurate).contains { generics.contains($0.text) }
    }

    /// The type as a stored property can hold it: `some P` becomes `any P`.
    func storable(_ type: TypeSyntax) -> String {
        if let some = type.as(SomeOrAnyTypeSyntax.self), some.someOrAnySpecifier.text == "some" {
            return "any \(some.constraint.trimmedDescription)"
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return attributed.baseType.trimmedDescription
        }
        return type.trimmedDescription
    }
}

func isFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) {
        return true
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isFunctionType(attributed.baseType)
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return isFunctionType(optional.wrappedType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let only = tuple.elements.first
    {
        return isFunctionType(only.type)
    }
    return false
}
