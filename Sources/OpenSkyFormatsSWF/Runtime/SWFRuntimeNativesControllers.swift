// Scaleform's multi-controller focus API. CLIK's `UIComponent.focused` setter loops over
// `Selection.numFocusGroups` and `System.capabilities.numControllers` before it calls
// `Selection.setFocus`, so without them no CLIK control ever takes focus. OpenSky has
// one controller in one focus group. See docs/engine/as2-input.md.

import Foundation

nonisolated extension SWFRuntimeNatives {
    /// One keyboard and mouse: controller 0, focus group 0.
    public static let controllerCount = 1

    /// `System.capabilities`: the GFx fields vanilla menus read.
    public static func installSystem(_ runtime: AS2Runtime) {
        let capabilities = runtime.makeObject()
        capabilities.define(
            .integer(controllerCount), for: "numControllers", flags: .dontEnumerate
        )
        capabilities.define(.string("MAC"), for: "os", flags: .dontEnumerate)
        capabilities.define(.string("MAC 10,0,0,0"), for: "version", flags: .dontEnumerate)
        let system = runtime.makeObject()
        system.define(.object(capabilities), for: "capabilities", flags: .dontEnumerate)
        runtime.globalObject.define(.object(system), for: "System", flags: .dontEnumerate)
    }

    /// The controller half of `Selection`, added beside `setFocus` and `getFocus`.
    static func installSelectionControllers(_ runtime: AS2Runtime, on selection: AS2Object) {
        selection.define(.integer(controllerCount), for: "numFocusGroups", flags: .dontEnumerate)
        AS2Natives.method(runtime, on: selection, name: "getControllerMaskByFocusGroup") { _ in
            .integer(1)
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
