// The engine<->movie bridge and its invoke log (milestone 8.3.2 phase 3).
// Device-free, synthetic fixtures only — no test reads a real `.swf`
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFGameDelegateTests {
    typealias Action = AS2Fixture.Action

    /// `ExternalInterface.call("Report", -1, "hello")` — the shape
    /// `gfx.io.GameDelegate.call` produces once it has appended the command name
    /// and its response id.
    private static func externalCall(
        _ command: String,
        _ values: [SWFActionFixture.PushValue]
    ) -> [Action] {
        SWFRuntimeFixture.call(
            method: "call",
            on: "ExternalInterface",
            arguments: [[AS2Fixture.push([.string(command)])]]
                + values.map { [AS2Fixture.push([$0])] }
        )
    }

    private static func movie(_ actions: [Action]) -> [SWFFixture.Tag] {
        [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFRuntimeFixture.place(1, depth: 1),
            SWFActionFixture.doActionTag(actions),
            SWFDisplayFixture.showFrameTag
        ]
    }

    /// A reference box a `@Sendable` host handler can write into.
    final class CallLog: @unchecked Sendable {
        private(set) var calls: [[AS2Value]] = []

        func append(_ arguments: [AS2Value]) {
            calls.append(arguments)
        }
    }

    // MARK: - Movie to engine

    @Test func aRegisteredHostFunctionReceivesTheMoviesCall() throws {
        let runtime = try SWFRuntimeFixture.runtime(tags: Self.movie(Self.externalCall(
            "Report",
            [.string("hello")]
        )))
        let log = CallLog()
        runtime.registerHostFunction("Report") { call in
            log.append(call.arguments)
            return .string("ok")
        }
        runtime.start()
        #expect(log.calls.count == 1)
        #expect(log.calls.first?.first == .string("hello"))
        #expect(runtime.hostFunctionNames == ["Report"])
        let entry = try #require(runtime.invokeLog.entries.first)
        #expect(entry.direction == .movieToEngine)
        #expect(entry.name == "Report")
        #expect(entry.arguments == "\"hello\"")
        #expect(entry.result == "\"ok\"")
        #expect(entry.isHandled)
    }

    /// The binding rule from the AS2 scope decision: an unregistered name is a
    /// logged no-op plus a tally entry, never an error.
    @Test func anUnregisteredHostFunctionIsTalliedAndLogged() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.movie(Self.externalCall("Missing", [.string("x")]))
        )
        #expect(runtime.tally.missingNames["Missing"] == 1)
        #expect(runtime.tally.faultTotal == 0)
        let entry = try #require(runtime.invokeLog.entries.first)
        #expect(entry.isHandled == false)
        #expect(runtime.invokeLog.unhandled == 1)
    }

    /// A non-negative response id means the movie passed a callback, so the
    /// handler's value goes back through `GameDelegate.receiveResponse`.
    @Test func aResponseIdRoutesTheResultBackToTheDelegate() throws {
        let runtime = try SWFRuntimeFixture.runtime(
            tags: Self.movie(Self.externalCall("Ask", [.integer(7), .string("question")]))
        )
        let delegate = runtime.runtime.makeObject()
        let hash = runtime.runtime.makeObject()
        hash.define(.boolean(true), for: "7")
        delegate.define(.object(hash), for: "responseHash")
        let responses = CallLog()
        AS2Natives.method(runtime.runtime, on: delegate, name: "receiveResponse") { context in
            responses.append(context.arguments)
            return .undefined
        }
        Self.installDelegate(delegate, in: runtime)
        runtime.registerHostFunction("Ask") { _ in .number(42) }
        runtime.start()
        #expect(responses.calls.count == 1)
        #expect(responses.calls.first?.first == .number(7))
        #expect(responses.calls.first?.last == .number(42))
    }

    /// -1 is the delegate's "no callback" marker: it is consumed as an id and
    /// nothing is sent back, so the handler never sees it as an argument.
    @Test func aNegativeResponseIdSendsNothingBack() throws {
        let runtime = try SWFRuntimeFixture.runtime(
            tags: Self.movie(Self.externalCall("Tell", [.integer(-1), .string("payload")]))
        )
        let delegate = runtime.runtime.makeObject()
        let responses = CallLog()
        AS2Natives.method(runtime.runtime, on: delegate, name: "receiveResponse") { context in
            responses.append(context.arguments)
            return .undefined
        }
        Self.installDelegate(delegate, in: runtime)
        let log = CallLog()
        runtime.registerHostFunction("Tell") { call in
            log.append(call.arguments)
            return .number(1)
        }
        runtime.start()
        #expect(responses.calls.isEmpty)
        #expect(log.calls.first?.count == 1)
        #expect(log.calls.first?.first == .string("payload"))
    }

    /// The counter-example that rules out sniffing by shape: a movie that ships
    /// a delegate but calls the host directly keeps its numeric argument,
    /// because the number is neither -1 nor a live `responseHash` key. This is
    /// exactly what `tweenmenu.swf` does with `HighlightMenu(3)`.
    @Test func aNumericArgumentThatIsNotAResponseIdIsPreserved() throws {
        let runtime = try SWFRuntimeFixture.runtime(
            tags: Self.movie(Self.externalCall("HighlightMenu", [.integer(3)]))
        )
        let delegate = runtime.runtime.makeObject()
        delegate.define(.object(runtime.runtime.makeObject()), for: "responseHash")
        Self.installDelegate(delegate, in: runtime)
        let log = CallLog()
        runtime.registerHostFunction("HighlightMenu") { call in
            log.append(call.arguments)
            return nil
        }
        runtime.start()
        #expect(log.calls.first == [.number(3)])
        #expect(runtime.invokeLog.entries.first?.arguments == "3")
    }

    // MARK: - Engine to movie

    @Test func aRegisteredCallbackIsInvokedThroughReceiveCall() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.movie([]))
        let delegate = runtime.runtime.makeObject()
        let hash = runtime.runtime.makeObject()
        hash.define(.boolean(true), for: "Refresh")
        delegate.define(.object(hash), for: "callBackHash")
        let received = CallLog()
        AS2Natives.method(runtime.runtime, on: delegate, name: "receiveCall") { context in
            received.append(context.arguments)
            return .string("done")
        }
        Self.installDelegate(delegate, in: runtime)
        #expect(runtime.movieCallbackNames == ["Refresh"])
        #expect(runtime.callMovie("Refresh", arguments: [.integer(3)]) == .string("done"))
        #expect(received.calls.first?.first == .string("Refresh"))
        #expect(received.calls.first?.last == .number(3))
        let entry = try #require(runtime.invokeLog.entries.last)
        #expect(entry.direction == .engineToMovie)
        #expect(entry.isHandled)
    }

    /// A movie without a delegate still has one entry point: a function on the
    /// root clip.
    @Test func aMovieWithoutADelegateFallsBackToTheRootFunction() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.movie([]))
        let log = CallLog()
        AS2Natives.method(runtime.runtime, on: runtime.root.object, name: "OnOpen") { context in
            log.append(context.arguments)
            return .boolean(true)
        }
        #expect(runtime.callMovie("OnOpen", arguments: [.string("x")]) == .boolean(true))
        #expect(log.calls.count == 1)
        #expect(runtime.gameDelegate == nil)
        #expect(runtime.movieCallbackNames.isEmpty)
    }

    @Test func aCallbackTheMovieNeverDefinedIsTalliedAndLoggedUnhandled() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.movie([]))
        #expect(runtime.callMovie("Nothing") == .undefined)
        #expect(runtime.tally.missingNames["Nothing"] == 1)
        let entry = try #require(runtime.invokeLog.entries.last)
        #expect(entry.isHandled == false)
    }

    // MARK: - Invoke log

    /// Bounded, oldest first, with the total still counting past the bound.
    @Test func theInvokeLogIsBoundedAndCountsPastItsBound() {
        var log = SWFInvokeLog(entryLimit: 4)
        for index in 0 ..< 10 {
            log.append(
                SWFInvokeEntry(
                    direction: .engineToMovie, name: "call\(index)",
                    arguments: "", result: "", isHandled: index.isMultiple(of: 2)
                )
            )
        }
        #expect(log.entries.count == 4)
        #expect(log.total == 10)
        #expect(log.dropped == 6)
        #expect(log.unhandled == 5)
        #expect(log.entries.first?.name == "call6")
        #expect(log.entries.last?.name == "call9")
        log.clear()
        #expect(log.total == 0)
        #expect(log.entries.isEmpty)
    }

    @Test func longArgumentSummariesAreClipped() {
        let log = SWFInvokeLog(entryLimit: 4, textLimit: 8)
        #expect(log.summary(.string("abcdefghijklmnop")) == "\"abcdefg")
        #expect(log.summary([.number(1), .boolean(true), .null]) == "1, true,")
        #expect(SWFInvokeLog.describe(.undefined) == "undefined")
    }

    @Test func clearingTheLogLeavesTheRuntimeUsable() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.movie(Self.externalCall("Missing", [.string("x")]))
        )
        #expect(runtime.invokeLog.total == 1)
        runtime.clearInvokeLog()
        #expect(runtime.invokeLog.total == 0)
        runtime.callMovie("Nothing")
        #expect(runtime.invokeLog.total == 1)
    }

    /// Installs `_global.gfx.io.GameDelegate`, the path the bridge resolves.
    private static func installDelegate(_ delegate: AS2Object, in runtime: SWFMovieRuntime) {
        let io = runtime.runtime.makeObject()
        io.define(.object(delegate), for: "GameDelegate")
        let gfx = runtime.runtime.globalObject.lookup("gfx")?.property.value.objectValue
            ?? runtime.runtime.makeObject()
        gfx.define(.object(io), for: "io")
        runtime.runtime.globalObject.define(.object(gfx), for: "gfx")
    }
}
