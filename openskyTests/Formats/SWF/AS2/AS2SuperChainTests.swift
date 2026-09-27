// `super` across a class hierarchy deeper than two levels (issue #136) — the
// shape every CLIK component has, because a component extends
// `gfx.core.UIComponent`, which extends `MovieClip`.

import Foundation
@testable import opensky
import Testing

struct AS2SuperChainTests {
    /// `Leaf extends Mid extends Base`, with both `Leaf` and `Mid` calling
    /// `super()`. Resolving `super` from the receiver pinned it to
    /// `this.__proto__`, so `Mid`'s constructor called itself until the
    /// call-depth cap fired; resolving it from the running class walks up one
    /// level per call and reaches `Base`.
    @Test func superWalksOneLevelPerCallInAThreeLevelHierarchy() {
        let outcome = AS2Fixture.result(
            Self.threeLevelHierarchy + Self.construct("Leaf")
                + [AS2Fixture.push([.string("tag")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(outcome.fault == nil)
        #expect(AS2Fixture.string(outcome.value) == "base")
    }

    /// Two levels kept working throughout: `new Mid()` reaches `Base` whether
    /// `super` is resolved from the receiver or from the running class.
    @Test func twoLevelConstructionStillReachesTheBaseConstructor() {
        let outcome = AS2Fixture.result(
            Self.threeLevelHierarchy + Self.construct("Mid")
                + [AS2Fixture.push([.string("tag")]), AS2Fixture.opcode(0x4E)]
        )
        #expect(outcome.fault == nil)
        #expect(AS2Fixture.string(outcome.value) == "base")
    }

    /// The same walk for an inherited method: `Mid.prototype.speak` calls
    /// `super.speak()`, and it has to reach `Base.prototype.speak` rather than
    /// find itself again through the leaf instance's prototype.
    @Test func superMethodResolvesFromTheClassThatDefinedIt() {
        let speak = Self.method(on: "Base", named: "speak", returning: "base")
            + Self.superMethod(on: "Mid", named: "speak")
        let actions = Self.threeLevelHierarchy + speak
            + [AS2Fixture.push([.string("instance")])] + Self.construct("Leaf")
            + [AS2Fixture.opcode(0x1D)]
            + [AS2Fixture.push([.integer(0)])]
            + AS2Fixture.getVariable("instance")
            + [AS2Fixture.push([.string("speak")]), AS2Fixture.opcode(0x52)]
        let outcome = AS2Fixture.result(actions)
        #expect(outcome.fault == nil)
        #expect(AS2Fixture.string(outcome.value) == "base")
    }

    /// `new Name()` with no arguments.
    private static func construct(_ name: String) -> [AS2Fixture.Action] {
        [AS2Fixture.push([.integer(0), .string(name)]), AS2Fixture.opcode(0x40)]
    }

    /// `super(...)` with no arguments, discarding what the call left behind.
    private static let superCall: [AS2Fixture.Action] = [
        AS2Fixture.push([.integer(0), .string("super")]),
        AS2Fixture.opcode(0x1C),
        AS2Fixture.push([.string("")]),
        AS2Fixture.opcode(0x52),
        AS2Fixture.opcode(0x17)
    ]

    /// `function Base() { this.tag = "base" }`, then `Mid` and `Leaf`, each
    /// calling `super()` and each extending the class before it.
    private static let threeLevelHierarchy: [AS2Fixture.Action] = {
        let baseBody: [AS2Fixture.Action] = [
            AS2Fixture.push([.string("this")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("tag"), .string("base")]),
            AS2Fixture.opcode(0x4F)
        ]
        return classDefinition(named: "Base", body: baseBody)
            + classDefinition(named: "Mid", body: superCall)
            + classDefinition(named: "Leaf", body: superCall)
            + extendsAction(subclass: "Mid", superclass: "Base")
            + extendsAction(subclass: "Leaf", superclass: "Mid")
    }()

    private static func classDefinition(
        named name: String,
        body: [AS2Fixture.Action]
    ) -> [AS2Fixture.Action] {
        let define = SWFActionFixture.defineFunction2(
            name: name, parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        return [define] + body
    }

    private static func extendsAction(
        subclass: String,
        superclass: String
    ) -> [AS2Fixture.Action] {
        AS2Fixture.getVariable(subclass) + AS2Fixture.getVariable(superclass)
            + [AS2Fixture.opcode(0x69)]
    }

    /// `Class.prototype.name = function () { return text }`.
    private static func method(
        on className: String,
        named name: String,
        returning text: String
    ) -> [AS2Fixture.Action] {
        installMethod(
            on: className,
            named: name,
            body: [AS2Fixture.push([.string(text)]), AS2Fixture.returnAction]
        )
    }

    /// `Class.prototype.name = function () { return super.name() }`.
    private static func superMethod(
        on className: String,
        named name: String
    ) -> [AS2Fixture.Action] {
        installMethod(on: className, named: name, body: [
            AS2Fixture.push([.integer(0), .string("super")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string(name)]),
            AS2Fixture.opcode(0x52),
            AS2Fixture.returnAction
        ])
    }

    private static func installMethod(
        on className: String,
        named name: String,
        body: [AS2Fixture.Action]
    ) -> [AS2Fixture.Action] {
        let define = SWFActionFixture.defineFunction2(
            name: "", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        return AS2Fixture.getVariable(className)
            + [AS2Fixture.push([.string("prototype")]), AS2Fixture.opcode(0x4E)]
            + [AS2Fixture.push([.string(name)]), define]
            + body
            + [AS2Fixture.opcode(0x4F)]
    }
}
