// Function definition, calling, registers, and the preload flags (milestone
// 8.3.2). `ActionDefineFunction2` outnumbers `ActionDefineFunction` eight to
// one in the vanilla movies, so both paths are pinned here.

import Foundation
@testable import opensky
import Testing

struct AS2FunctionTests {
    @Test func defineFunction2BindsParametersToRegisters() {
        let body: [AS2Fixture.Action] = [
            AS2Fixture.push([.register(1), .register(2)]),
            AS2Fixture.opcode(0x47),
            AS2Fixture.returnAction
        ]
        let define = SWFActionFixture.defineFunction2(
            name: "add",
            parameters: [(1, "first"), (2, "second")],
            registerCount: 3,
            flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let value = AS2Fixture.evaluate([define] + body + Self.call("add", arguments: [4, 3]))
        #expect(AS2Fixture.number(value) == 7)
    }

    @Test func defineFunctionBindsParametersByName() {
        let body: [AS2Fixture.Action] = [
            AS2Fixture.push([.string("first")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("second")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.opcode(0x47),
            AS2Fixture.returnAction
        ]
        let define = SWFActionFixture.defineFunction(
            name: "add",
            parameters: ["first", "second"],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let value = AS2Fixture.evaluate([define] + body + Self.call("add", arguments: [4, 3]))
        #expect(AS2Fixture.number(value) == 7)
    }

    @Test func preloadThisFillsTheFirstRegister() {
        let body = [AS2Fixture.push([.register(1)]), AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "who",
            parameters: [],
            registerCount: 2,
            flags: [.preloadThis],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let runtime = AS2Runtime()
        let value = AS2Fixture.evaluate(
            [define] + body + Self.call("who", arguments: []), runtime: runtime
        )
        #expect(value.objectValue === runtime.root)
    }

    @Test func preloadArgumentsFollowsPreloadThis() {
        let body: [AS2Fixture.Action] = [
            AS2Fixture.push([.register(2), .string("length")]),
            AS2Fixture.opcode(0x4E),
            AS2Fixture.returnAction
        ]
        let define = SWFActionFixture.defineFunction2(
            name: "count",
            parameters: [],
            registerCount: 3,
            flags: [.preloadThis, .preloadArguments],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let value = AS2Fixture.evaluate([define] + body + Self.call("count", arguments: [1, 2]))
        #expect(AS2Fixture.number(value) == 2)
    }

    @Test func preloadGlobalReachesTheGlobalObject() {
        let body: [AS2Fixture.Action] = [
            AS2Fixture.push([.register(1), .string("Math")]),
            AS2Fixture.opcode(0x4E),
            AS2Fixture.returnAction
        ]
        let define = SWFActionFixture.defineFunction2(
            name: "globals",
            parameters: [],
            registerCount: 2,
            flags: [.preloadGlobal],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let value = AS2Fixture.evaluate([define] + body + Self.call("globals", arguments: []))
        #expect(value.objectValue != nil)
    }

    @Test func anonymousFunctionsArePushedRatherThanNamed() {
        let body = [AS2Fixture.push([.integer(42)]), AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "",
            parameters: [],
            registerCount: 1,
            flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let value = AS2Fixture.evaluate([define] + body)
        #expect(value.functionValue != nil)
    }

    @Test func nestedCallsReturnThroughEveryFrame() {
        let innerBody = [AS2Fixture.push([.integer(5)]), AS2Fixture.returnAction]
        let inner = SWFActionFixture.defineFunction2(
            name: "inner", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(innerBody))
        )
        let outerBody = Self.call("inner", arguments: []) + [AS2Fixture.returnAction]
        let outer = SWFActionFixture.defineFunction2(
            name: "outer", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(outerBody))
        )
        let actions = [inner] + innerBody + [outer] + outerBody
            + Self.call("outer", arguments: [])
        #expect(AS2Fixture.number(AS2Fixture.evaluate(actions)) == 5)
    }

    @Test func runawayRecursionStopsAtTheCallDepthCap() {
        let body = Self.call("loop", arguments: []) + [AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "loop", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        var limits = AS2Limits.standard
        limits.callDepth = 8
        let runtime = AS2Runtime(limits: limits)
        let result = AS2Fixture.result(
            [define] + body + Self.call("loop", arguments: []), runtime: runtime
        )
        #expect(result.fault?.kind == "callDepthExceeded")
        #expect(runtime.tally.faultTotal == 1)
        // The call that exceeded the cap is counted before the cap is checked.
        #expect(runtime.tally.callsPerformed == 9)
    }

    @Test func aBodyLongerThanItsStreamFaults() {
        let define = SWFActionFixture.defineFunction2(
            name: "broken", parameters: [], registerCount: 1, flags: [], bodySize: 64
        )
        let result = AS2Fixture.run([define])
        #expect(result.fault?.kind == "truncatedBody")
    }

    @Test func closuresCaptureTheDefiningConstantPool() {
        let body = [AS2Fixture.push([.constant8(1)]), AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "poolReader", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let actions = [SWFActionFixture.constantPool(["zero", "one"]), define]
            + body + Self.call("poolReader", arguments: [])
        #expect(AS2Fixture.string(AS2Fixture.evaluate(actions)) == "one")
    }

    /// `ActionCallFunction` operand order: the arguments deepest with the first
    /// argument on top of them, then the count, then the name.
    private static func call(_ name: String, arguments: [Int32]) -> [AS2Fixture.Action] {
        var values = arguments.reversed().map { SWFActionFixture.PushValue.integer($0) }
        values.append(.integer(Int32(arguments.count)))
        values.append(.string(name))
        return [AS2Fixture.push(values), AS2Fixture.opcode(0x3D)]
    }
}
