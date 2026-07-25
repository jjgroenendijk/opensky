// Object literals, prototypes, and the class-relationship opcodes (milestone
// 8.3.2) — the shape of vanilla `DoInitAction` class-registration code.

import Foundation
@testable import opensky
import Testing

struct AS2ObjectModelTests {
    /// `{ a: 1, b: 2 }`. The compiler pushes the pairs back to front, so `a`
    /// is the first pair popped.
    private static let objectLiteral: [AS2Fixture.Action] = [
        AS2Fixture.push([
            .string("b"), .integer(2), .string("a"), .integer(1), .integer(2)
        ]),
        AS2Fixture.opcode(0x43)
    ]

    /// `[10, 20]`.
    private static let arrayLiteral: [AS2Fixture.Action] = [
        AS2Fixture.push([.integer(20), .integer(10), .integer(2)]),
        AS2Fixture.opcode(0x42)
    ]

    @Test func initObjectBuildsNamedProperties() {
        let value = AS2Fixture.evaluate(
            Self.objectLiteral + [AS2Fixture.push([.string("a")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(AS2Fixture.number(value) == 1)
        let second = AS2Fixture.evaluate(
            Self.objectLiteral + [AS2Fixture.push([.string("b")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(AS2Fixture.number(second) == 2)
    }

    @Test func initArrayBuildsIndexedElementsAndLength() {
        let first = AS2Fixture.evaluate(
            Self.arrayLiteral + [AS2Fixture.push([.string("0")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(AS2Fixture.number(first) == 10)
        let length = AS2Fixture.evaluate(
            Self.arrayLiteral + [AS2Fixture.push([.string("length")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(AS2Fixture.number(length) == 2)
    }

    @Test func enumerate2PushesNullThenNamesInReverseInsertionOrder() {
        let first = AS2Fixture.evaluate(Self.objectLiteral + [AS2Fixture.opcode(0x55)])
        #expect(AS2Fixture.string(first) == "a")
        let second = AS2Fixture.evaluate(
            Self.objectLiteral + [AS2Fixture.opcode(0x55), AS2Fixture.opcode(0x17)]
        )
        #expect(AS2Fixture.string(second) == "b")
        let sentinel = AS2Fixture.evaluate(
            Self.objectLiteral
                + [AS2Fixture.opcode(0x55), AS2Fixture.opcode(0x17), AS2Fixture.opcode(0x17)]
        )
        #expect(sentinel == .null)
    }

    @Test func extendsLinksThePrototypeChainForInstanceOf() {
        let actions = Self.classPair
            + AS2Fixture.getVariable("Derived") + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x69)]
            + Self.construct("Derived")
            + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x54)]
        #expect(AS2Fixture.boolean(AS2Fixture.evaluate(actions)) == true)
    }

    @Test func instanceOfIsFalseWithoutExtends() {
        let actions = Self.classPair
            + Self.construct("Derived")
            + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x54)]
        #expect(AS2Fixture.boolean(AS2Fixture.evaluate(actions)) == false)
    }

    @Test func castOpReturnsTheObjectOrNull() {
        let matching = Self.classPair
            + AS2Fixture.getVariable("Derived") + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x69)]
            + Self.construct("Derived")
            + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x2B)]
        #expect(AS2Fixture.evaluate(matching).objectValue != nil)

        let mismatched = Self.classPair
            + Self.construct("Base")
            + AS2Fixture.getVariable("Derived")
            + [AS2Fixture.opcode(0x2B)]
        #expect(AS2Fixture.evaluate(mismatched) == .null)
    }

    @Test func prototypeMethodsResolveThroughNewAndCallMethod() {
        let methodBody = [AS2Fixture.push([.string("hi")]), AS2Fixture.returnAction]
        let methodDefine = SWFActionFixture.defineFunction2(
            name: "", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(methodBody))
        )
        let install = AS2Fixture.getVariable("Base")
            + [AS2Fixture.push([.string("prototype")]), AS2Fixture.opcode(0x4E)]
            + [AS2Fixture.push([.string("speak")]), methodDefine]
            + methodBody
            + [AS2Fixture.opcode(0x4F)]
        let actions = Self.classPair
            + install
            + [AS2Fixture.push([.string("instance")])] + Self.construct("Base")
            + [AS2Fixture.opcode(0x1D)]
            + [AS2Fixture.push([.integer(0)])]
            + AS2Fixture.getVariable("instance")
            + [AS2Fixture.push([.string("speak")]), AS2Fixture.opcode(0x52)]
        #expect(AS2Fixture.string(AS2Fixture.evaluate(actions)) == "hi")
    }

    @Test func superCallsTheBaseConstructorWithTheDerivedInstance() {
        let baseBody: [AS2Fixture.Action] = [
            AS2Fixture.push([.string("this")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("tag"), .string("base")]),
            AS2Fixture.opcode(0x4F)
        ]
        let base = SWFActionFixture.defineFunction2(
            name: "Base", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(baseBody))
        )
        let derivedBody: [AS2Fixture.Action] = [
            AS2Fixture.push([.integer(0), .string("super")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("")]),
            AS2Fixture.opcode(0x52),
            AS2Fixture.opcode(0x17)
        ]
        let derived = SWFActionFixture.defineFunction2(
            name: "Derived", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(derivedBody))
        )
        let actions = [base] + baseBody + [derived] + derivedBody
            + AS2Fixture.getVariable("Derived") + AS2Fixture.getVariable("Base")
            + [AS2Fixture.opcode(0x69)]
            + Self.construct("Derived")
            + [AS2Fixture.push([.string("tag")]), AS2Fixture.opcode(0x4E)]
        #expect(AS2Fixture.string(AS2Fixture.evaluate(actions)) == "base")
    }

    @Test func addPropertyInstallsAGetter() {
        let getterBody = [AS2Fixture.push([.integer(42)]), AS2Fixture.returnAction]
        let getterDefine = SWFActionFixture.defineFunction2(
            name: "", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(getterBody))
        )
        let actions = [AS2Fixture.push([.string("holder")])]
            + Self.objectLiteral
            + [AS2Fixture.opcode(0x1D)]
            + [AS2Fixture.push([.null]), getterDefine]
            + getterBody
            + [AS2Fixture.push([.string("answer"), .integer(3)])]
            + AS2Fixture.getVariable("holder")
            + [AS2Fixture.push([.string("addProperty")]), AS2Fixture.opcode(0x52)]
            + [AS2Fixture.opcode(0x17)]
            + AS2Fixture.getVariable("holder")
            + [AS2Fixture.push([.string("answer")]), AS2Fixture.opcode(0x4E)]
        #expect(AS2Fixture.number(AS2Fixture.evaluate(actions)) == 42)
    }

    @Test func asSetPropFlagsHidesPropertiesFromEnumeration() {
        let hide = [AS2Fixture.push([.integer(0), .integer(1), .null])]
            + AS2Fixture.getVariable("holder")
            + [AS2Fixture.push([.integer(4), .string("ASSetPropFlags")]), AS2Fixture.opcode(0x3D)]
            + [AS2Fixture.opcode(0x17)]
        let prefix = [AS2Fixture.push([.string("holder")])]
            + Self.objectLiteral
            + [AS2Fixture.opcode(0x1D)]
            + hide
        let hidden = AS2Fixture.evaluate(
            prefix + AS2Fixture.getVariable("holder") + [AS2Fixture.opcode(0x55)]
        )
        #expect(hidden == .null)
        let stillReadable = AS2Fixture.evaluate(
            prefix + AS2Fixture.getVariable("holder")
                + [AS2Fixture.push([.string("a")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(AS2Fixture.number(stillReadable) == 1)
    }

    @Test func registerClassRecordsTheSymbolToConstructorMapping() {
        let runtime = AS2Runtime()
        let actions = Self.classPair
            + AS2Fixture.getVariable("Base")
            + [AS2Fixture.push([.string("MenuSymbol"), .integer(2)])]
            + AS2Fixture.getVariable("Object")
            + [AS2Fixture.push([.string("registerClass")]), AS2Fixture.opcode(0x52)]
        let value = AS2Fixture.evaluate(actions, runtime: runtime)
        #expect(AS2Fixture.boolean(value) == true)
        #expect(runtime.registeredClassNames == ["MenuSymbol"])
        #expect(runtime.registeredClass(named: "MenuSymbol")?.isFunction == true)
    }

    /// `function Base() {}` and `function Derived() {}`, both empty.
    private static let classPair: [AS2Fixture.Action] = [
        SWFActionFixture.defineFunction2(
            name: "Base", parameters: [], registerCount: 1, flags: [], bodySize: 0
        ),
        SWFActionFixture.defineFunction2(
            name: "Derived", parameters: [], registerCount: 1, flags: [], bodySize: 0
        )
    ]

    /// `new Name()` with no arguments.
    private static func construct(_ name: String) -> [AS2Fixture.Action] {
        [AS2Fixture.push([.integer(0), .string(name)]), AS2Fixture.opcode(0x40)]
    }
}
