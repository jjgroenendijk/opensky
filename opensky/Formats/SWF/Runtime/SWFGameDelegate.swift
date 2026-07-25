// The engine<->movie bridge (milestone 8.3.2 phase 3). `gfx.io.GameDelegate` is
// Scaleform's host channel and the one the vanilla install actually uses: 1,520
// references across 38 of the 53 movies. OpenSky adopts its shape rather than
// inventing a bridge, because the movies are unmodified and a different bridge
// would mean they call into nothing.
//
// The delegate itself is ActionScript that ships *inside* each movie — the
// probe over `startmenu.swf` reads back `call`, `receiveResponse`, `addCallBack`,
// `removeCallBack`, `receiveCall`, `initialize`, `responseHash`, `callBackHash`,
// and `nextID` on `_global.gfx.io.GameDelegate` — so the engine does not
// reimplement it. It supplies the two ends the delegate reaches for:
//
//   * movie -> engine: `GameDelegate.call(command, callback, thisRef, ...)`
//     appends the command name and a response id and hands them to
//     `ExternalInterface.call`, which is a player built-in and therefore the
//     engine's to provide. A registered Swift handler answers; an unregistered
//     name is a logged no-op plus a tally entry, per the binding rule in the
//     AS2 scope decision. A handler that returns a value and a call that asked
//     for one are joined back up through `GameDelegate.receiveResponse(id, …)`.
//
//   * engine -> movie: the movie registers named callbacks with
//     `addCallBack(command, thisRef, function)`, and the engine invokes one by
//     name through `receiveCall`. A movie without a delegate falls back to a
//     direct function call on the root clip.
//
// Both directions land in a bounded invoke log, which is what milestone 8.3.3
// asks `Developer > UI Lab` to show.
//
// There is no public specification for the Scaleform GFx object model, so the
// argument convention above is recorded as observed from the vanilla bytecode,
// not cited.

import Foundation

/// One call across the bridge, in either direction.
nonisolated struct SWFInvokeEntry: Equatable {
    enum Direction: String, Equatable {
        case movieToEngine = "movie->engine"
        case engineToMovie = "engine->movie"
    }

    let direction: Direction
    let name: String
    /// Comma-separated argument summary, clipped per `SWFInvokeLog.textLimit`.
    let arguments: String
    /// The value handed back, summarized the same way.
    let result: String
    /// False when nothing answered the call — an unregistered host function or
    /// a callback the movie never defined.
    let isHandled: Bool
}

/// A bounded record of both bridge directions. Oldest entries drop first and
/// `total` keeps counting, so a truncated log still reports how much it stopped
/// recording — the same posture as `AS2TraceLog`.
nonisolated struct SWFInvokeLog: Equatable {
    let entryLimit: Int
    let textLimit: Int

    private(set) var entries: [SWFInvokeEntry] = []
    private(set) var total = 0
    /// Calls that nothing answered, including ones already dropped.
    private(set) var unhandled = 0

    static let defaultEntryLimit = 256
    static let defaultTextLimit = 240

    init(
        entryLimit: Int = SWFInvokeLog.defaultEntryLimit,
        textLimit: Int = SWFInvokeLog.defaultTextLimit
    ) {
        self.entryLimit = max(1, entryLimit)
        self.textLimit = max(8, textLimit)
    }

    /// Entries dropped to stay inside `entryLimit`.
    var dropped: Int {
        max(0, total - entries.count)
    }

    mutating func append(_ entry: SWFInvokeEntry) {
        total += 1
        if !entry.isHandled {
            unhandled += 1
        }
        entries.append(entry)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }
    }

    mutating func clear() {
        entries.removeAll()
        total = 0
        unhandled = 0
    }

    /// One-line summary of a value list, clipped to `textLimit`.
    func summary(_ values: [AS2Value]) -> String {
        clip(values.map(SWFInvokeLog.describe).joined(separator: ", "))
    }

    func summary(_ value: AS2Value) -> String {
        clip(SWFInvokeLog.describe(value))
    }

    private func clip(_ text: String) -> String {
        text.count > textLimit ? String(text.prefix(textLimit)) : text
    }

    /// A short, stable rendering of a value. Objects are named by kind rather
    /// than walked, because the log must not depend on an object graph that may
    /// be cyclic.
    static func describe(_ value: AS2Value) -> String {
        switch value {
        case .undefined: "undefined"
        case .null: "null"
        case let .boolean(flag): flag ? "true" : "false"
        case let .number(number): AS2Coercion.numberToString(number)
        case let .string(text): "\"\(text)\""
        case let .object(object):
            object.isFunction ? "[function]" : (object.isArray ? "[array]" : "[object]")
        }
    }
}

/// A host function the movie may call by name. Returning `nil` means the
/// handler ran but produced no response value; the engine then sends nothing
/// back through `receiveResponse`.
typealias SWFHostFunction = @Sendable (SWFHostCall) -> AS2Value?

/// One movie-to-engine call as a handler sees it.
nonisolated struct SWFHostCall {
    let name: String
    let arguments: [AS2Value]

    func argument(_ index: Int) -> AS2Value {
        arguments.indices.contains(index) ? arguments[index] : .undefined
    }
}

nonisolated extension SWFMovieRuntime {
    /// Registers the Swift side of a movie-to-engine call. Registering the same
    /// name twice replaces the handler, which is what a menu reopening expects.
    func registerHostFunction(_ name: String, _ body: @escaping SWFHostFunction) {
        hostFunctions[name] = body
    }

    func removeHostFunction(_ name: String) {
        hostFunctions[name] = nil
    }

    /// Registered names, sorted so a report is stable.
    var hostFunctionNames: [String] {
        hostFunctions.keys.sorted()
    }

    // MARK: - Movie to engine

    /// `ExternalInterface.call(command, responseId, …)` as `GameDelegate.call`
    /// spells it. An unregistered command is a logged no-op plus a tally entry,
    /// never an error — the degradation rule the scope decision fixed.
    @discardableResult
    func receiveExternalCall(_ values: [AS2Value]) -> AS2Value {
        guard case let .string(name) = values.first ?? .undefined else {
            runtime.noteMissing("ExternalInterface.call")
            return .undefined
        }
        let responseId = responseId(values)
        let arguments = Array(values.dropFirst(responseId == nil ? 1 : 2))
        let result = callHost(name, arguments: arguments)
        if let responseId, responseId >= 0, let result {
            respond(to: responseId, with: result)
        }
        return result ?? .undefined
    }

    /// Dispatches to a registered handler and logs the call either way.
    @discardableResult
    func callHost(_ name: String, arguments: [AS2Value]) -> AS2Value? {
        guard let handler = hostFunctions[name] else {
            runtime.noteMissing(name)
            noteInvoke(
                SWFInvokeEntry(
                    direction: .movieToEngine, name: name,
                    arguments: invokeLog.summary(arguments),
                    result: "undefined", isHandled: false
                )
            )
            return nil
        }
        let result = handler(SWFHostCall(name: name, arguments: arguments))
        noteInvoke(
            SWFInvokeEntry(
                direction: .movieToEngine, name: name,
                arguments: invokeLog.summary(arguments),
                result: invokeLog.summary(result ?? .undefined), isHandled: true
            )
        )
        return result
    }

    /// The response id `GameDelegate.call` inserts after the command name, or
    /// nil when the second value is an ordinary argument.
    ///
    /// Telling the two apart cannot be done by shape, and guessing is a real
    /// failure mode: `tweenmenu.swf` calls `HighlightMenu(3)` with the 3 as its
    /// only argument, and a rule that treated any leading number as an id would
    /// silently drop it. So the delegate's own bookkeeping decides. It writes
    /// `responseHash[id]` immediately before the call when the movie passed a
    /// callback, and passes the literal -1 when it did not, so an id is a number
    /// that is either -1 or a live `responseHash` key — and only a movie that
    /// ships a delegate can produce either.
    private func responseId(_ values: [AS2Value]) -> Int? {
        guard
            values.count > 1, case let .number(number) = values[1],
            number.isFinite, number > Double(Int32.min), number < Double(Int32.max),
            let delegate = gameDelegate
        else {
            return nil
        }
        let identifier = Int(number)
        if identifier == -1 {
            return identifier
        }
        guard
            identifier >= 0,
            delegate.lookup("responseHash")?.property.value.objectValue?
                .hasOwnProperty(String(identifier)) == true
        else {
            return nil
        }
        return identifier
    }

    private func respond(to responseId: Int, with value: AS2Value) {
        guard let delegate = gameDelegate else {
            return
        }
        invokeMember("receiveResponse", of: delegate, arguments: [.integer(responseId), value])
    }

    // MARK: - Engine to movie

    /// Invokes a callback the movie registered with
    /// `GameDelegate.addCallBack(command, thisRef, function)`. Falls back to a
    /// direct call on the root clip for a movie that ships no delegate, so the
    /// engine has one entry point either way.
    @discardableResult
    func callMovie(_ name: String, arguments: [AS2Value] = []) -> AS2Value {
        var result = AS2Value.undefined
        var handled = false
        if let delegate = gameDelegate, hasCallback(name, on: delegate) {
            result = invokeMember(
                "receiveCall", of: delegate, arguments: [.string(name)] + arguments
            )
            handled = true
        } else if root.object.lookup(name)?.property.value.functionValue != nil {
            result = invoke(name, arguments: arguments).value
            handled = true
        } else {
            runtime.noteMissing(name)
        }
        noteInvoke(
            SWFInvokeEntry(
                direction: .engineToMovie, name: name,
                arguments: invokeLog.summary(arguments),
                result: invokeLog.summary(result), isHandled: handled
            )
        )
        return result
    }

    /// `_global.gfx.io.GameDelegate`, or nil for a movie that does not ship the
    /// CLIK library.
    var gameDelegate: AS2Object? {
        ["gfx", "io", "GameDelegate"].reduce(runtime.globalObject) { object, name in
            object?.lookup(name)?.property.value.objectValue
        }
    }

    /// Callback names the movie registered, sorted. Reading `callBackHash`
    /// directly is what makes the log show which engine-to-movie calls a menu is
    /// actually prepared for.
    var movieCallbackNames: [String] {
        guard
            let hash = gameDelegate?.lookup("callBackHash")?.property.value.objectValue
        else {
            return []
        }
        return hash.ownPropertyNames.sorted()
    }

    private func hasCallback(_ name: String, on delegate: AS2Object) -> Bool {
        guard let hash = delegate.lookup("callBackHash")?.property.value.objectValue else {
            return false
        }
        return hash.hasOwnProperty(name)
    }

    @discardableResult
    private func invokeMember(
        _ name: String,
        of object: AS2Object,
        arguments: [AS2Value]
    ) -> AS2Value {
        guard let function = object.lookup(name)?.property.value.functionValue else {
            runtime.noteMissing(name)
            return .undefined
        }
        markDirty()
        return runtime.invoke(
            .object(function), thisValue: .object(object), arguments: arguments
        ).value
    }
}

nonisolated extension SWFRuntimeNatives {
    /// `ExternalInterface` and `fscommand`: the two player built-ins a movie can
    /// reach the host through. Installed under both the bare global name and
    /// `flash.external.ExternalInterface`, because AS2 code spells it either way
    /// depending on whether it imported the package.
    static func installExternalInterface(_ runtime: AS2Runtime) {
        let external = runtime.makeObject()
        external.define(.boolean(true), for: "available", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: external, name: "call") { context in
            movieRuntime(context)?.receiveExternalCall(context.arguments) ?? .undefined
        }
        // A movie may register its own AS2 handlers; recording them keeps the
        // name resolvable without the engine pretending to dispatch to them.
        AS2Natives.method(runtime, on: external, name: "addCallback") { _ in .boolean(false) }
        runtime.globalObject.define(
            .object(external), for: "ExternalInterface", flags: .dontEnumerate
        )
        let package = runtime.makeObject()
        package.define(.object(external), for: "ExternalInterface", flags: .dontEnumerate)
        let flash = runtime.makeObject()
        flash.define(.object(package), for: "external", flags: .dontEnumerate)
        runtime.globalObject.define(.object(flash), for: "flash", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: runtime.globalObject, name: "fscommand") { context in
            guard let owner = movieRuntime(context) else {
                return .undefined
            }
            let name = try context.string(0)
            return owner.callHost(name, arguments: Array(context.arguments.dropFirst()))
                ?? .undefined
        }
    }
}
