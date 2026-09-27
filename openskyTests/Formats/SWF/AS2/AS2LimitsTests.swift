// Bounded execution, diagnostics, and the host seam (milestone 8.3.2). Every
// way a stream can be wrong has to end in a recorded fault; every demand on the
// display layer has to end in a host event and a tally entry.

import Foundation
@testable import opensky
import Testing

struct AS2LimitsTests {
    @Test func aSelfJumpStopsAtTheActionBudget() {
        var limits = AS2Limits.standard
        limits.actionBudget = 100
        let runtime = AS2Runtime(limits: limits)
        let result = AS2Fixture.run(
            [SWFActionFixture.branch(code: 0x99, offset: -5)], runtime: runtime
        )
        #expect(result.fault?.kind == "budgetExhausted")
        #expect(result.actionsExecuted == 100)
        #expect(runtime.tally.faultTotal == 1)
    }

    /// Flash tolerates an empty-stack read, and vanilla bytecode depends on it:
    /// 666 of the 1,180 vanilla action blocks reach a compiler-emitted
    /// `ActionPop` at a branch join with nothing on the stack.
    @Test func emptyStackReadsYieldUndefinedAndAreTallied() {
        let runtime = AS2Runtime()
        let result = AS2Fixture.run(
            [AS2Fixture.opcode(0x17), AS2Fixture.opcode(0x0B)], runtime: runtime
        )
        #expect(result.completed)
        #expect(runtime.tally.stackUnderflows == 3)
        #expect(runtime.tally.faultTotal == 0)
    }

    @Test func stackOverflowAbortsTheBlock() {
        var limits = AS2Limits.standard
        limits.stackDepth = 4
        let runtime = AS2Runtime(limits: limits)
        let values = (0 ..< 8).map { SWFActionFixture.PushValue.integer(Int32($0)) }
        let result = AS2Fixture.run([AS2Fixture.push(values)], runtime: runtime)
        #expect(result.fault?.kind == "stackOverflow")
    }

    @Test func aFaultInOneBlockLeavesTheRuntimeUsable() {
        let runtime = AS2Runtime()
        _ = AS2Fixture.run(
            [SWFActionFixture.branch(code: 0x99, offset: 1), AS2Fixture.push([.integer(1)])],
            runtime: runtime
        )
        let value = AS2Fixture.evaluate([AS2Fixture.push([.integer(3)])], runtime: runtime)
        #expect(AS2Fixture.number(value) == 3)
        #expect(runtime.tally.faultTotal == 1)
        #expect(runtime.tally.blocksExecuted == 2)
    }

    @Test func unimplementedOpcodesAreTalliedNotFatal() {
        let runtime = AS2Runtime()
        // ActionEnumerate (0x46) never occurs in a vanilla movie, so it is one
        // of the opcodes deliberately routed to the tallied no-op path.
        let value = AS2Fixture.evaluate(
            [AS2Fixture.opcode(0x46), AS2Fixture.push([.integer(1)])], runtime: runtime
        )
        #expect(AS2Fixture.number(value) == 1)
        #expect(runtime.tally.unimplementedTotal == 1)
        #expect(runtime.tally.unimplementedOpcodes[0x46] == 1)
        #expect(runtime.tally.rankedUnimplemented.first?.name == "ActionEnumerate")
    }

    @Test func unresolvedNamesAreTalliedAsMissingAPIs() {
        let runtime = AS2Runtime()
        let value = AS2Fixture.evaluate(AS2Fixture.getVariable("MovieClip"), runtime: runtime)
        #expect(value == .undefined)
        #expect(runtime.tally.missingNames["MovieClip"] == 1)
        #expect(runtime.tally.missingTotal == 1)
        #expect(runtime.tally.isClean == false)
    }

    @Test func tallyNamesAreCappedButTotalsKeepCounting() {
        var limits = AS2Limits.standard
        limits.tallyNames = 2
        var tally = AS2Tally(limits: limits)
        for name in ["one", "two", "three", "four"] {
            tally.noteMissing(name)
        }
        tally.noteMissing("one")
        #expect(tally.missingNames.count == 2)
        #expect(tally.missingTotal == 5)
        #expect(tally.unnamedMissing == 2)
        #expect(tally.missingNames["one"] == 2)
    }

    @Test func traceRoutesToTheBoundedLog() {
        let runtime = AS2Runtime()
        _ = AS2Fixture.run(
            [AS2Fixture.push([.string("hello")]), AS2Fixture.opcode(0x26)],
            runtime: runtime
        )
        #expect(runtime.traceLog.messages == ["hello"])
        #expect(runtime.traceLog.total == 1)
    }

    @Test func traceLogDropsOldestPastItsLimit() {
        var limits = AS2Limits.standard
        limits.traceEntries = 2
        limits.traceLength = 4
        var log = AS2TraceLog(limits: limits)
        log.append("first")
        log.append("second")
        log.append("third")
        #expect(log.messages == ["seco", "thir"])
        #expect(log.total == 3)
        #expect(log.dropped == 1)
    }

    @Test func timelineOpcodesReachTheHost() {
        let host = AS2RecordingHost()
        let runtime = AS2Runtime(host: host)
        _ = AS2Fixture.run([
            AS2Fixture.opcode(0x07),
            AS2Fixture.opcode(0x06),
            SWFActionFixture.gotoFrame(4),
            SWFActionFixture.goToLabel("MenuOpen")
        ], runtime: runtime)
        #expect(host.timelineCommands == [.stop, .play, .gotoFrame(4), .gotoLabel("MenuOpen")])
    }

    @Test func displayPropertiesRouteThroughTheHostAndTally() {
        let host = AS2RecordingHost()
        let runtime = AS2Runtime(host: host)
        let value = AS2Fixture.evaluate([
            AS2Fixture.push([.string("clip"), .integer(0)]), AS2Fixture.opcode(0x22)
        ], runtime: runtime)
        #expect(value == .undefined)
        #expect(host.events.contains(.propertyRead(.positionX)))
        #expect(runtime.tally.missingNames["_x"] == 1)
    }

    @Test func rootReferencesAskTheHost() {
        let host = AS2RecordingHost()
        let runtime = AS2Runtime(host: host)
        let value = AS2Fixture.evaluate(AS2Fixture.getVariable("_root"), runtime: runtime)
        #expect(value == .undefined)
        #expect(host.events.contains(.specialRequest(.root)))
        #expect(runtime.tally.missingNames["_root"] == 1)
    }

    @Test func everyImplementedOpcodeIsANamedAdobeAction() {
        #expect(AS2Opcode.implemented.count == 58)
        for code in AS2Opcode.implemented {
            #expect(SWFActionName.isKnown(code), "opcode \(code) is not in the Adobe table")
        }
    }

    @Test func doInitActionRunsThroughTheSameEntryPoint() {
        let runtime = AS2Runtime()
        let block = AS2Fixture.block(AS2Fixture.setVariable("ready", .boolean(true)))
        let result = runtime.execute(SWFDoInitAction(spriteId: 3, actions: block))
        #expect(result.completed)
        #expect(runtime.root.ownProperty("ready")?.value == .boolean(true))
    }
}
