// Scaleform's multi-controller focus API. CLIK's `UIComponent.focused` setter loops over
// `Selection.numFocusGroups` and `System.capabilities.numControllers` before it calls
// `Selection.setFocus`, so without them no CLIK control ever takes focus. Keyboard and
// mouse are controller 0, each gamepad adds one, and all share focus group 0.
// See docs/engine/as2-input.md.

import Foundation

/// One `SetPlatform` call into a movie, kept so a new platform can be sent again.
nonisolated struct SWFPlatformCall {
    let path: String?
    let arguments: [AS2Value]
}

nonisolated extension SWFMovieRuntime {
    /// One focus group holds every controller, so one focus serves them all.
    public static let focusGroupCount = 1
    /// GFx reports at most four controllers.
    public static let maximumGamepads = 3
    /// `Shared.ButtonChange.PLATFORM_PC` and `PLATFORM_PC_GAMEPAD`, as the movies set them.
    public static let keyboardPlatform = 0.0
    public static let gamepadPlatform = 1.0
    static let setPlatformName = "SetPlatform"

    /// Keyboard and mouse plus each connected gamepad.
    public var controllerCount: Int {
        1 + gamepadCount
    }

    /// The platform the movie draws its button art for.
    public var inputPlatform: Double {
        gamepadCount > 0 ? Self.gamepadPlatform : Self.keyboardPlatform
    }

    /// The controllers in focus group 0, one bit each.
    public var focusGroupControllerMask: Int {
        (1 << controllerCount) - 1
    }

    /// Updates `System.capabilities.numControllers` and sends the movie's last
    /// `SetPlatform` call again with the new platform, so its button art follows.
    public func setGamepadCount(_ count: Int) {
        let clamped = min(max(count, 0), Self.maximumGamepads)
        guard clamped != gamepadCount else { return }
        gamepadCount = clamped
        runtime.globalObject.lookup("System")?.property.value.objectValue?
            .lookup("capabilities")?.property.value.objectValue?
            .define(.integer(controllerCount), for: "numControllers", flags: .dontEnumerate)
        if let call = platformCall {
            sendPlatform(call)
        }
    }

    /// A `SetPlatform` call carries the runtime's platform in place of the bridge's.
    func platformArguments(_ name: String, _ arguments: [AS2Value], path: String?) -> [AS2Value] {
        guard name == Self.setPlatformName, !arguments.isEmpty else { return arguments }
        var replaced = arguments
        replaced[0] = .number(inputPlatform)
        platformCall = SWFPlatformCall(path: path, arguments: replaced)
        return replaced
    }

    private func sendPlatform(_ call: SWFPlatformCall) {
        if let path = call.path {
            callMovie(Self.setPlatformName, atPath: path, arguments: call.arguments)
        } else {
            callMovie(Self.setPlatformName, arguments: call.arguments)
        }
    }
}

nonisolated extension SWFRuntimeNatives {
    /// `System.capabilities`: the GFx fields vanilla menus read.
    public static func installSystem(_ runtime: AS2Runtime) {
        let capabilities = runtime.makeObject()
        capabilities.define(.integer(1), for: "numControllers", flags: .dontEnumerate)
        capabilities.define(.string("MAC"), for: "os", flags: .dontEnumerate)
        capabilities.define(.string("MAC 10,0,0,0"), for: "version", flags: .dontEnumerate)
        let system = runtime.makeObject()
        system.define(.object(capabilities), for: "capabilities", flags: .dontEnumerate)
        runtime.globalObject.define(.object(system), for: "System", flags: .dontEnumerate)
    }

    /// The controller half of `Selection`, added beside `setFocus` and `getFocus`.
    static func installSelectionControllers(_ runtime: AS2Runtime, on selection: AS2Object) {
        selection.define(
            .integer(SWFMovieRuntime.focusGroupCount), for: "numFocusGroups",
            flags: .dontEnumerate
        )
        AS2Natives.method(runtime, on: selection, name: "getControllerMaskByFocusGroup") {
            .integer(movieRuntime($0)?.focusGroupControllerMask ?? 1)
        }
        AS2Natives.method(runtime, on: selection, name: "getControllerFocusGroup") { _ in
            .integer(0)
        }
        AS2Natives.method(runtime, on: selection, name: "setControllerFocusGroup") { _ in
            .boolean(true)
        }
        AS2Natives.method(runtime, on: selection, name: "getFocusBitmask") { context in
            guard
                let owner = movieRuntime(context),
                let object = context.argument(0).objectValue,
                let node = SWFDisplayObject.resolve(object)
            else { return .integer(0) }
            return .integer(owner.focusTarget === node ? 1 : 0)
        }
    }
}

nonisolated extension SWFMovieRuntime {
    /// Flash tells `Selection` listeners about each focus move; GFx adds the controller.
    func announceFocusChange(from old: SWFDisplayObject?) {
        guard
            old !== focusTarget,
            let selection = runtime.globalObject.lookup("Selection")?.property.value.objectValue
        else { return }
        let value: (SWFDisplayObject?) -> AS2Value = { node in
            node.map { .object($0.object) } ?? .null
        }
        broadcast(
            "onSetFocus", from: selection,
            arguments: [value(old), value(focusTarget), .integer(0)]
        )
    }
}
