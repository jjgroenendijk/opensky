// The `Key` and `Mouse` globals (milestone 8.3.2 phase 3).
//
// These two are why the phase-2 missing-API tally listed `addListener` 28 times
// across the install. They are broadcasters: a movie calls
// `Key.addListener(object)` and the player then calls `onKeyDown` and `onKeyUp`
// on every registered listener. CLIK's `gfx.managers.InputDelegate` registers
// itself on `Key` in its constructor, reads `Key.getCode()` inside `onKeyDown`,
// turns the code into a `gfx.ui.NavigationCode` string, and dispatches an
// `input` event that `gfx.managers.FocusHandler` routes to the focused
// component's `handleInput`. Implementing the broadcaster is therefore the whole
// of what the engine owes the framework — every step after it is AS2 that ships
// inside the movie.
//
// `Key` and `Mouse` are Flash built-ins, not SWF file-format structures, so the
// specification says nothing about them. Behavior and the key-code table come
// from public ActionScript 2 API documentation and from what the vanilla
// bytecode reads back.

import Foundation

/// The ActionScript 2 `Key` constants, named so Swift callers do not spell raw
/// numbers. Values are the Flash key codes, which follow the Windows virtual
/// key codes for the keys that have one.
nonisolated enum SWFKeyCode {
    static let backspace = 8
    static let tab = 9
    static let enter = 13
    static let shift = 16
    static let control = 17
    static let alt = 18
    static let capsLock = 20
    static let escape = 27
    static let space = 32
    static let pageUp = 33
    static let pageDown = 34
    static let end = 35
    static let home = 36
    static let left = 37
    static let up = 38
    static let right = 39
    static let down = 40
    static let insert = 45
    static let delete = 46

    /// Name to value, exactly as the `Key` class exposes them.
    static let constants: [(name: String, value: Int)] = [
        ("BACKSPACE", backspace), ("TAB", tab), ("ENTER", enter), ("SHIFT", shift),
        ("CONTROL", control), ("ALT", alt), ("CAPSLOCK", capsLock), ("ESCAPE", escape),
        ("SPACE", space), ("PGUP", pageUp), ("PGDN", pageDown), ("END", end),
        ("HOME", home), ("LEFT", left), ("UP", up), ("RIGHT", right),
        ("DOWN", down), ("INSERT", insert), ("DELETEKEY", delete)
    ]
}

nonisolated extension SWFRuntimeNatives {
    /// `Key`: a broadcaster plus the query methods a listener calls back into.
    static func installKey(_ runtime: AS2Runtime) {
        let key = runtime.makeObject()
        for constant in SWFKeyCode.constants {
            key.define(
                .integer(constant.value), for: constant.name, flags: [.dontEnumerate, .dontDelete]
            )
        }
        AS2Natives.method(runtime, on: key, name: "getCode") { context in
            .integer(movieRuntime(context)?.input.lastKeyCode ?? 0)
        }
        AS2Natives.method(runtime, on: key, name: "getAscii") { context in
            .integer(movieRuntime(context)?.input.lastKeyAscii ?? 0)
        }
        AS2Natives.method(runtime, on: key, name: "isDown") { context in
            guard let owner = movieRuntime(context) else {
                return .boolean(false)
            }
            let code = try context.number(0)
            return .boolean(code.isFinite && owner.input.isDown(Int(code)))
        }
        // Caps and num lock are not modelled: OpenSky injects key events, it
        // does not own a keyboard, so a toggle state would be invented.
        AS2Natives.method(runtime, on: key, name: "isToggled") { _ in .boolean(false) }
        installListenerList(runtime, on: key)
        runtime.globalObject.define(.object(key), for: "Key", flags: .dontEnumerate)
    }

    /// `Mouse`: a broadcaster plus cursor visibility, which OpenSky records
    /// rather than acts on — the engine draws no system cursor over the movie.
    static func installMouse(_ runtime: AS2Runtime) {
        let mouse = runtime.makeObject()
        mouse.define(.boolean(true), for: "_visible", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: mouse, name: "show") { context in
            setCursorVisible(context, to: true)
        }
        AS2Natives.method(runtime, on: mouse, name: "hide") { context in
            setCursorVisible(context, to: false)
        }
        installListenerList(runtime, on: mouse)
        runtime.globalObject.define(.object(mouse), for: "Mouse", flags: .dontEnumerate)
    }

    /// `Mouse.show()` / `Mouse.hide()` answer the *previous* visibility as 1 or
    /// 0, which is what the ActionScript 2 reference specifies.
    private static func setCursorVisible(_ context: AS2CallContext, to visible: Bool) -> AS2Value {
        guard let mouse = context.thisObject else {
            return .integer(0)
        }
        let previous = mouse.lookup("_visible")?.property.value
        mouse.define(.boolean(visible), for: "_visible", flags: .dontEnumerate)
        return .integer(previous == .boolean(true) ? 1 : 0)
    }
}
