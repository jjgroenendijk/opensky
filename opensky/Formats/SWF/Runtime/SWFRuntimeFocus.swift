// Focus and keyboard navigation (milestone 8.3.2 phase 3).
//
// Vanilla menus navigate through CLIK, not through clip events: `NavigationCode`
// is referenced 1,669 times across 34 movies and `FocusHandler` 420 times. The
// framework's own path is `gfx.managers.InputDelegate` listening on `Key`,
// translating a key code into a `gfx.ui.NavigationCode` string, wrapping it in a
// `gfx.ui.InputDetails`, and dispatching an `input` event that
// `gfx.managers.FocusHandler` routes down the focus path to the focused
// component's `handleInput`.
//
// A probe over `startmenu.swf` shows only half of that chain wakes up on its
// own: `FocusHandler._instance` exists after bring-up, while
// `InputDelegate._instance` does not, so nothing has registered on `Key` and a
// key event delivered only to the broadcaster reaches nobody. The engine
// therefore does the step the absent `InputDelegate` would have done — build the
// `InputDetails` and hand it to `FocusHandler.instance.handleInput` — using the
// movie's *own* `NavigationCode` constants rather than strings invented here.
// When a movie does register a `Key` listener, that path runs first and this one
// is never reached.
//
// None of this is specified anywhere: the Scaleform GFx component library has no
// public runtime contract. Every name below is read back from the vanilla
// bytecode the interpreter already executes.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Key code to the `gfx.ui.NavigationCode` constant that names it. The
    /// *value* of each constant is read from the movie, so a movie that spells
    /// them differently still works.
    static let navigationConstants: [Int: String] = [
        SWFKeyCode.up: "UP", SWFKeyCode.down: "DOWN",
        SWFKeyCode.left: "LEFT", SWFKeyCode.right: "RIGHT",
        SWFKeyCode.enter: "ENTER", SWFKeyCode.escape: "ESCAPE",
        SWFKeyCode.end: "END", SWFKeyCode.home: "HOME",
        SWFKeyCode.pageUp: "PAGE_UP", SWFKeyCode.pageDown: "PAGE_DOWN",
        SWFKeyCode.tab: "TAB"
    ]

    /// `gfx.ui.NavigationCode`, or nil for a movie without CLIK.
    var navigationCodes: AS2Object? {
        globalPath(["gfx", "ui", "NavigationCode"])
    }

    /// The navigation string a key code maps to, as the movie spells it.
    func navigationEquivalent(forKey code: Int) -> String? {
        guard
            let name = SWFMovieRuntime.navigationConstants[code],
            case let .string(value) = navigationCodes?.lookup(name)?.property.value ?? .undefined
        else {
            return nil
        }
        return value
    }

    /// `gfx.managers.FocusHandler.instance`. The singleton is behind a getter,
    /// so reading it means calling the accessor — and calling it is also what
    /// creates it, which is why this is not a plain property read.
    var focusHandler: AS2Object? {
        guard let handlerClass = globalPath(["gfx", "managers", "FocusHandler"]) else {
            return nil
        }
        return resolve("instance", on: handlerClass).objectValue
    }

    /// The focus path CLIK routes input along, outermost first. Empty when the
    /// movie has no focus handler or nothing has focus.
    var pathToFocus: [String] {
        guard let handler = focusHandler else {
            return []
        }
        guard
            let function = handler.lookup("getPathToFocus")?.property.value.functionValue
        else {
            return []
        }
        let result = runtime.invoke(
            .object(function), thisValue: .object(handler), arguments: [.integer(0)]
        )
        guard let list = result.value.objectValue else {
            return []
        }
        return list.elements.compactMap { element in
            SWFDisplayObject.resolve(element.objectValue)?.targetPath
        }
    }

    /// Hands a key to the CLIK focus path as `InputDelegate` would have.
    /// `value` is the framework's own spelling of the phase: `keyDown`,
    /// `keyUp`, or `keyHold`.
    @discardableResult
    func routeToFocusHandler(code: Int, value: String) -> Bool {
        guard let handler = focusHandler else {
            return false
        }
        guard
            let function = handler.lookup("handleInput")?.property.value.functionValue,
            let details = makeInputDetails(code: code, value: value)
        else {
            return false
        }
        markDirty()
        let result = runtime.invoke(
            .object(function), thisValue: .object(handler), arguments: [details]
        )
        return runtime.coercion.toBoolean(result.value)
    }

    /// Hands a key to the menu's own `handleInput(details, pathToFocus)`. Every
    /// vanilla menu class defines it — `TweenMenuObj`, `StartMenu`,
    /// `gfx.controls.Button`, `Shared.BSScrollingList`, and `FocusHandler` all
    /// carry the same two-argument shape — and it is the entry point Bethesda's
    /// menus expect the host to call, because their own routing forwards down
    /// `pathToFocus` from there.
    @discardableResult
    func routeToMenuHandler(code: Int, value: String) -> Bool {
        guard
            let node = menuInputHandler,
            let function = node.object.lookup("handleInput")?.property.value.functionValue,
            let details = makeInputDetails(code: code, value: value)
        else {
            return false
        }
        markDirty()
        let path = runtime.makeArray(focusChain(under: node).map { .object($0.object) })
        let result = runtime.invoke(
            .object(function), thisValue: .object(node.object),
            arguments: [details, .object(path)]
        )
        return runtime.coercion.toBoolean(result.value)
    }

    /// The outermost clip that defines `handleInput`, found breadth-first from
    /// the root. The depth cap keeps the search on menu roots: a vanilla menu
    /// clip sits one or two levels below `_root`, while the CLIK controls that
    /// also define `handleInput` sit deeper and are reached by the menu's own
    /// forwarding rather than by the engine.
    var menuInputHandler: SWFDisplayObject? {
        var frontier = root.children.filter(\.isClip)
        var depth = 1
        while !frontier.isEmpty, depth <= SWFMovieRuntime.maximumHandlerDepth {
            if
                let found = frontier.first(where: {
                    $0.object.lookup("handleInput")?.property.value.functionValue != nil
                })
            {
                return found
            }
            frontier = frontier.flatMap { $0.children.filter(\.isClip) }
            depth += 1
        }
        return nil
    }

    /// The clips between `node` and the focused object, outermost first. Empty
    /// when nothing has focus, which is what a menu that owns its own selection
    /// state expects.
    func focusChain(under node: SWFDisplayObject) -> [SWFDisplayObject] {
        var chain: [SWFDisplayObject] = []
        var current = focusTarget
        var steps = 0
        while let walked = current, walked !== node, steps < SWFDisplayObject.maximumTreeDepth {
            chain.append(walked)
            current = walked.parent
            steps += 1
        }
        return current === node ? chain.reversed() : []
    }

    /// A `gfx.ui.InputDetails`, constructed through the movie's own class so its
    /// field names and defaults come from the movie rather than from here. Falls
    /// back to a plain object carrying the same five fields when the class is
    /// absent, because a component only ever reads them by name.
    func makeInputDetails(code: Int, value: String) -> AS2Value? {
        let navigation = navigationEquivalent(forKey: code)
        let arguments: [AS2Value] = [
            .string("key"), .integer(code), .string(value),
            navigation.map(AS2Value.string) ?? .undefined, .integer(0)
        ]
        if
            let detailsClass = globalPath(["gfx", "ui", "InputDetails"]),
            detailsClass.isFunction
        {
            let constructed = runtime.construct(detailsClass, arguments: arguments)
            if constructed.objectValue != nil {
                return constructed
            }
        }
        let details = runtime.makeObject()
        details.define(.string("key"), for: "type")
        details.define(.integer(code), for: "code")
        details.define(.string(value), for: "value")
        details.define(navigation.map(AS2Value.string) ?? .undefined, for: "navEquivalent")
        details.define(.integer(0), for: "controllerIdx")
        return .object(details)
    }

    /// Walks a dotted `_global` path without going through the interpreter, for
    /// the framework objects the engine needs by name.
    func globalPath(_ components: [String]) -> AS2Object? {
        components.reduce(AS2Object?.some(runtime.globalObject)) { object, name in
            object?.lookup(name)?.property.value.objectValue
        }
    }

    /// Reads a property that may be an accessor, invoking the getter when it is.
    func resolve(_ name: String, on object: AS2Object) -> AS2Value {
        guard let found = object.lookup(name) else {
            return .undefined
        }
        guard found.property.isVirtual else {
            return found.property.value
        }
        guard let getter = found.property.getter else {
            return .undefined
        }
        return runtime.invoke(.object(getter), thisValue: .object(object)).value
    }
}

nonisolated extension AS2Runtime {
    /// `new constructor(arguments)` from Swift, for the engine-side halves of
    /// the framework protocol.
    func construct(_ constructor: AS2Object, arguments: [AS2Value] = []) -> AS2Value {
        guard let function = constructor.lookup("prototype") != nil ? constructor : nil else {
            return .undefined
        }
        let instance = AS2Object(
            prototype: function.lookup("prototype")?.property.value.objectValue ?? objectPrototype
        )
        instance.define(
            .object(function), for: "__constructor__", flags: [.dontEnumerate, .dontDelete]
        )
        let result = invoke(.object(function), thisValue: .object(instance), arguments: arguments)
        return result.value.objectValue.map(AS2Value.object) ?? .object(instance)
    }
}
