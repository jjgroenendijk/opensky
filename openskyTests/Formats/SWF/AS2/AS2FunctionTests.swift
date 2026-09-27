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

    /// The interpreter runs calls on its own frame stack, so nesting far past
    /// the old Swift-recursive cap of 64 completes (issue #132). Two hundred
    /// nested calls is deeper than any vanilla CLIK constructor chain.
    @Test func deepRecursionCompletesWithoutTouchingTheSwiftStack() {
        let runtime = AS2Runtime()
        let result = AS2Fixture.result(Self.countdown(from: 200), runtime: runtime)
        #expect(result.fault == nil)
        #expect(AS2Fixture.number(result.value) == 0)
        #expect(runtime.tally.callsPerformed == 200)
    }

    /// A built-in that calls back into bytecode does consume Swift stack, so it
    /// runs under `AS2Limits.reentryDepth` rather than the call-depth cap.
    /// `Function.prototype.call` recursing on itself is the shape that shows it.
    @Test func reentrantNativeRecursionStopsAtTheReentryCap() {
        var limits = AS2Limits.standard
        limits.reentryDepth = 4
        let runtime = AS2Runtime(limits: limits)
        let body = Self.callMethod("recurse", named: "call") + [AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "recurse", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let result = AS2Fixture.result(
            [define] + body + Self.call("recurse", arguments: []), runtime: runtime
        )
        #expect(result.fault?.kind == "reentryDepthExceeded")
    }

    /// Sequential calls are not nested calls: the frame stack has to give the
    /// depth back on every return, or a long timeline of ordinary calls would
    /// fault against a cap it never actually reaches.
    @Test func sequentialCallsDoNotAccumulateDepth() {
        var limits = AS2Limits.standard
        limits.callDepth = 4
        let runtime = AS2Runtime(limits: limits)
        let body = [AS2Fixture.push([.integer(1)]), AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "once", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        let step = Self.call("once", arguments: []) + [AS2Fixture.opcode(0x17)]
        var actions = [define] + body
        for _ in 0 ..< 200 {
            actions += step
        }
        let result = AS2Fixture.run(actions, runtime: runtime)
        #expect(result.fault == nil)
        #expect(runtime.tally.callsPerformed == 200)
    }

    /// `n = n - 1; if (n) { down(); } return n;`, called once with `n` preset,
    /// so the stream performs exactly `count` strictly nested calls.
    private static func countdown(from count: Int32) -> [AS2Fixture.Action] {
        let recurse = call("down", arguments: []) + [AS2Fixture.opcode(0x17)]
        let body = [AS2Fixture.push([.string("n")])]
            + AS2Fixture.getVariable("n")
            + [
                AS2Fixture.push([.integer(1)]),
                AS2Fixture.opcode(0x0B),
                AS2Fixture.opcode(0x1D)
            ]
            + AS2Fixture.getVariable("n")
            // `ActionNot` so the branch skips the recursive call once `n` is 0.
            + [
                AS2Fixture.opcode(0x12),
                SWFActionFixture.branch(code: 0x9D, offset: Int16(AS2Fixture.size(recurse)))
            ]
            + recurse
            + AS2Fixture.getVariable("n")
            + [AS2Fixture.returnAction]
        let define = SWFActionFixture.defineFunction2(
            name: "down", parameters: [], registerCount: 1, flags: [],
            bodySize: UInt16(AS2Fixture.size(body))
        )
        return AS2Fixture.setVariable("n", .integer(count))
            + [define] + body + call("down", arguments: [])
    }

    /// `ActionCallMethod` on a named variable: the argument count, then the
    /// receiver the variable holds, then the method name on top.
    private static func callMethod(_ variable: String, named method: String)
        -> [AS2Fixture.Action]
    {
        [AS2Fixture.push([.integer(0)])]
            + AS2Fixture.getVariable(variable)
            + [AS2Fixture.push([.string(method)]), AS2Fixture.opcode(0x52)]
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
