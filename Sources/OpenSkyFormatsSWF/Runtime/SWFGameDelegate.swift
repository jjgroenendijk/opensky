// The engine<->movie bridge through `gfx.io.GameDelegate`, the Scaleform channel
// vanilla movies ship and call. Movie to engine: `ExternalInterface.call` reaches
// a registered Swift handler; an unknown name is a logged no-op. Engine to movie:
// `receiveCall` invokes a registered callback. Observed, not specified:
// docs/engine/as2-game-delegate.md.

import Foundation

/// One call across the bridge, in either direction.
nonisolated public struct SWFInvokeEntry: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case movieToEngine = "movie->engine"
        case engineToMovie = "engine->movie"
    }

    public let direction: Direction
    public let name: String
    /// Comma-separated argument summary, clipped per `SWFInvokeLog.textLimit`.
    public let arguments: String
    /// The value handed back, summarized the same way.
    public let result: String
    /// False when nothing answered the call — an unregistered host function or
    /// a callback the movie never defined.
    public let isHandled: Bool
}

/// A bounded record of both bridge directions. Oldest entries drop first and
/// `total` keeps counting, so a truncated log still reports how much it stopped
/// recording — the same posture as `AS2TraceLog`.
nonisolated public struct SWFInvokeLog: Equatable, Sendable {
    public let entryLimit: Int
    public let textLimit: Int

    public private(set) var entries: [SWFInvokeEntry] = []
    public private(set) var total = 0
    /// Calls that nothing answered, including ones already dropped.
    public private(set) var unhandled = 0

    public static let defaultEntryLimit = 256
    public static let defaultTextLimit = 240

    public init(
        entryLimit: Int = SWFInvokeLog.defaultEntryLimit,
        textLimit: Int = SWFInvokeLog.defaultTextLimit
    ) {
        self.entryLimit = max(1, entryLimit)
        self.textLimit = max(8, textLimit)
    }

    /// Entries dropped to stay inside `entryLimit`.
    public var dropped: Int {
        max(0, total - entries.count)
    }

    public mutating func append(_ entry: SWFInvokeEntry) {
        total += 1
        if !entry.isHandled {
            unhandled += 1
        }
        entries.append(entry)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }
    }

    public mutating func clear() {
        entries.removeAll()
        total = 0
        unhandled = 0
    }

    /// One-line summary of a value list, clipped to `textLimit`.
    public func summary(_ values: [AS2Value]) -> String {
        clip(values.map(SWFInvokeLog.describe).joined(separator: ", "))
    }

    public func summary(_ value: AS2Value) -> String {
        clip(SWFInvokeLog.describe(value))
    }

    private func clip(_ text: String) -> String {
        text.count > textLimit ? String(text.prefix(textLimit)) : text
    }

    /// A short, stable rendering of a value. Objects are named by kind rather
    /// than walked, because the log must not depend on an object graph that may
    /// be cyclic.
    public static func describe(_ value: AS2Value) -> String {
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
public typealias SWFHostFunction = @Sendable (SWFHostCall) -> AS2Value?

/// One movie-to-engine call as a handler sees it.
nonisolated public struct SWFHostCall {
    public let arguments: [AS2Value]
}

nonisolated extension SWFMovieRuntime {
    /// Registers the Swift side of a movie-to-engine call. Registering the same
    /// name twice replaces the handler, which is what a menu reopening expects.
    public func registerHostFunction(_ name: String, _ body: @escaping SWFHostFunction) {
        hostFunctions[name] = body
    }

    /// Registered names, sorted so a report is stable.
    public var hostFunctionNames: [String] {
        hostFunctions.keys.sorted()
    }

    // MARK: - Movie to engine

    /// `ExternalInterface.call(command, responseId, …)` as `GameDelegate.call`
    /// spells it. An unregistered command is a logged no-op plus a tally entry,
    /// never an error — the degradation rule the scope decision fixed.
    @discardableResult
    public func receiveExternalCall(_ values: [AS2Value]) -> AS2Value {
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
    public func callHost(_ name: String, arguments: [AS2Value]) -> AS2Value? {
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
        lastHostArguments[name] = arguments
        let result = handler(SWFHostCall(arguments: arguments))
        noteInvoke(
            SWFInvokeEntry(
                direction: .movieToEngine, name: name,
                arguments: invokeLog.summary(arguments),
                result: invokeLog.summary(result ?? .undefined), isHandled: true
            )
        )
        return result
    }

    /// The response id `GameDelegate.call` inserts after the command name, or nil.
    /// Shape cannot tell an id from an argument (`HighlightMenu(3)`), so an id is
    /// -1 or a live `responseHash` key, which only a delegate writes.
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
    public func callMovie(_ name: String, arguments: [AS2Value] = []) -> AS2Value {
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

    /// Invokes a function on a named display object. HUD movies expose their
    /// engine entry points on `/HUDMovieBaseInstance` rather than registering
    /// `GameDelegate` callbacks, so the engine-to-movie bridge needs a precise
    /// target path as well as the root/delegate entry point above.
    @discardableResult
    public func callMovie(
        _ name: String,
        atPath path: String,
        arguments: [AS2Value] = []
    ) -> AS2Value {
        guard
            let target = node(atPath: path, from: root),
            let function = target.object.lookup(name)?.property.value.functionValue
        else {
            runtime.noteMissing(name)
            noteMovieCall(name, arguments: arguments, result: .undefined, handled: false)
            return .undefined
        }
        markDirty()
        let result = runtime.invoke(
            .object(function),
            thisValue: .object(target.object),
            arguments: arguments
        ).value
        noteMovieCall(name, arguments: arguments, result: result, handled: true)
        return result
    }

    /// `_global.gfx.io.GameDelegate`, or nil for a movie that does not ship the
    /// CLIK library.
    public var gameDelegate: AS2Object? {
        ["gfx", "io", "GameDelegate"].reduce(runtime.globalObject) { object, name in
            object?.lookup(name)?.property.value.objectValue
        }
    }

    /// Callback names the movie registered, sorted. Reading `callBackHash`
    /// directly is what makes the log show which engine-to-movie calls a menu is
    /// actually prepared for.
    public var movieCallbackNames: [String] {
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

    private func noteMovieCall(
        _ name: String,
        arguments: [AS2Value],
        result: AS2Value,
        handled: Bool
    ) {
        noteInvoke(
            SWFInvokeEntry(
                direction: .engineToMovie,
                name: name,
                arguments: invokeLog.summary(arguments),
                result: invokeLog.summary(result),
                isHandled: handled
            )
        )
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
    public static func installExternalInterface(_ runtime: AS2Runtime) {
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
