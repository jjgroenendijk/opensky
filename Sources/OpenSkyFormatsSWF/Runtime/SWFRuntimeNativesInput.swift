// The `Key` and `Mouse` broadcaster globals. CLIK's `InputDelegate` listens on
// `Key` and does the rest of input routing in the movie's own AS2, so the
// broadcaster is all the engine owes it. Behavior and key codes come from
// public ActionScript 2 docs. See docs/engine/as2-input.md.

import Foundation

/// The ActionScript 2 `Key` constants, named so Swift callers do not spell raw
/// numbers. Values are the Flash key codes, which follow the Windows virtual
/// key codes for the keys that have one.
nonisolated public enum SWFKeyCode: Sendable {
    public static let backspace = 8
    public static let tab = 9
    public static let enter = 13
    public static let shift = 16
    public static let control = 17
    public static let alt = 18
    public static let capsLock = 20
    public static let escape = 27
    public static let space = 32
    public static let pageUp = 33
    public static let pageDown = 34
    public static let end = 35
    public static let home = 36
    public static let left = 37
    public static let up = 38
    public static let right = 39
    public static let down = 40
    public static let insert = 45
    public static let delete = 46

    /// Name to value, exactly as the `Key` class exposes them.
    public static let constants: [(name: String, value: Int)] = [
        ("BACKSPACE", backspace), ("TAB", tab), ("ENTER", enter), ("SHIFT", shift),
        ("CONTROL", control), ("ALT", alt), ("CAPSLOCK", capsLock), ("ESCAPE", escape),
        ("SPACE", space), ("PGUP", pageUp), ("PGDN", pageDown), ("END", end),
        ("HOME", home), ("LEFT", left), ("UP", up), ("RIGHT", right),
        ("DOWN", down), ("INSERT", insert), ("DELETEKEY", delete)
    ]
}

nonisolated extension SWFRuntimeNatives {
    /// `Key`: a broadcaster plus the query methods a listener calls back into.
    public static func installKey(_ runtime: AS2Runtime) {
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
    public static func installMouse(_ runtime: AS2Runtime) {
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
