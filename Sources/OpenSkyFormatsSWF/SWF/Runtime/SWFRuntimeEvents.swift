// Event dispatch: handler members (`clip.onPress`, used by CLIK), CLIPACTIONS
// handlers, and broadcaster listeners (`Key`, `Mouse`, `Stage`, `Selection`).
// Vanilla movies use CLIPACTIONS almost only for `construct`.
// Spec: SWF v19 chapter 3, PlaceObject2. See docs/formats/swf-actions.md.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Calls a handler member on a node — the `clip.onPress` convention. Looks
    /// the name up through the ordinary prototype chain, so a handler inherited
    /// from a registered class works exactly like one assigned on the instance.
    /// Returns false when the node has no such handler, which is the normal
    /// case and never a fault.
    @discardableResult
    public func dispatch(
        _ handler: String,
        to node: SWFDisplayObject,
        arguments: [AS2Value] = []
    ) -> Bool {
        guard let function = node.object.lookup(handler)?.property.value.functionValue else {
            return false
        }
        runtime.invoke(
            .object(function), thisValue: .object(node.object), arguments: arguments
        )
        markDirty()
        return true
    }

    /// Dispatches one clip event to a node: its CLIPACTIONS handlers for that
    /// event first, then the matching handler member. Flash runs both, and a
    /// movie may define either.
    @discardableResult
    public func dispatchClipEvent(
        _ event: SWFClipEventFlags,
        to node: SWFDisplayObject,
        keyCode: UInt8? = nil
    ) -> Bool {
        var handled = runClipActions(event, on: node, keyCode: keyCode)
        if let name = SWFClipEventFlags.handlerName(for: event) {
            handled = dispatch(name, to: node) || handled
        }
        return handled
    }

    /// Runs every CLIPACTIONS record whose flags include `event`, with the node
    /// as the execution target so `this` and the timeline both point at it.
    /// A `keyPress` record additionally matches on its trapped key code.
    private func runClipActions(
        _ event: SWFClipEventFlags,
        on node: SWFDisplayObject,
        keyCode: UInt8?
    ) -> Bool {
        guard let records = node.clipActions?.records, !records.isEmpty else {
            return false
        }
        var ran = false
        for record in records where record.events.contains(event) {
            if event == .keyPress, let trapped = record.keyCode, trapped != keyCode {
                continue
            }
            runtime.execute(record.actions, target: node.object)
            ran = true
        }
        if ran {
            markDirty()
        }
        return ran
    }

    /// The lifecycle a newly placed instance runs through, in the order the
    /// `ClipEventFlags` table implies: `initialize` before the registered
    /// class's constructor, then `construct`, then `load`.
    public func dispatchPlacementLifecycle(_ node: SWFDisplayObject, phase: SWFClipLifecycle) {
        switch phase {
        case .initialize:
            dispatchClipEvent(.initialize, to: node)
        case .constructed:
            dispatchClipEvent(.construct, to: node)
            dispatchClipEvent(.load, to: node)
        case .unloaded:
            dispatchClipEvent(.unload, to: node)
        }
    }

    /// `enterFrame` for one tick: the CLIPACTIONS handler plus the
    /// `onEnterFrame` member. Vanilla menus set `onEnterFrame` on the instance —
    /// `startmenu.swf` does it on both `Menu_mc` and `BottomButtons_mc` — so the
    /// member path is the one that matters.
    public func dispatchEnterFrame(of node: SWFDisplayObject, remainingDepth: Int) {
        guard remainingDepth > 0 else {
            return
        }
        if node !== root {
            dispatchClipEvent(.enterFrame, to: node)
        }
        for child in node.children where child.isClip {
            dispatchEnterFrame(of: child, remainingDepth: remainingDepth - 1)
        }
    }

    // MARK: - Broadcasters

    /// Sends a message to every listener a broadcaster object recorded, and
    /// answers how many listeners actually had a handler for it. This is the
    /// `addListener`/`removeListener` convention `Key`, `Mouse`, `Stage`, and
    /// `Selection` share; CLIK's `gfx.managers.InputDelegate` registers itself
    /// on `Key` this way, which is how a vanilla menu sees a keystroke at all.
    @discardableResult
    public func broadcast(
        _ message: String,
        from broadcaster: AS2Object,
        arguments: [AS2Value] = []
    ) -> Int {
        guard let listeners = broadcaster.lookup("_listeners")?.property.value.objectValue else {
            return 0
        }
        var delivered = 0
        for element in listeners.elements {
            guard
                let listener = element.objectValue,
                let function = listener.lookup(message)?.property.value.functionValue
            else {
                continue
            }
            runtime.invoke(.object(function), thisValue: .object(listener), arguments: arguments)
            delivered += 1
        }
        if delivered > 0 {
            markDirty()
        }
        return delivered
    }

    /// A `_global` broadcaster by name (`Key`, `Mouse`, `Stage`, `Selection`).
    public func globalBroadcaster(_ name: String) -> AS2Object? {
        runtime.globalObject.lookup(name)?.property.value.objectValue
    }
}

/// Where a placed instance is in its bring-up, for `dispatchPlacementLifecycle`.
nonisolated public enum SWFClipLifecycle: Equatable, Sendable {
    /// The instance exists and its own frame 1 is built; the registered class
    /// constructor has not run yet.
    case initialize
    /// The constructor has run.
    case constructed
    /// The instance left the display list.
    case unloaded
}

nonisolated extension SWFClipEventFlags {
    /// The handler-member name Flash gives each clip event. `initialize`,
    /// `construct`, and `keyPress` are absent because they have no member form:
    /// the first two are CLIPACTIONS-only and the third traps a specific key.
    private static let handlerNames: [UInt32: String] = [
        load.rawValue: "onLoad", enterFrame.rawValue: "onEnterFrame",
        unload.rawValue: "onUnload", mouseMove.rawValue: "onMouseMove",
        mouseDown.rawValue: "onMouseDown", mouseUp.rawValue: "onMouseUp",
        keyDown.rawValue: "onKeyDown", keyUp.rawValue: "onKeyUp",
        data.rawValue: "onData", press.rawValue: "onPress",
        release.rawValue: "onRelease", releaseOutside.rawValue: "onReleaseOutside",
        rollOver.rawValue: "onRollOver", rollOut.rawValue: "onRollOut",
        dragOver.rawValue: "onDragOver", dragOut.rawValue: "onDragOut"
    ]

    public static func handlerName(for event: SWFClipEventFlags) -> String? {
        handlerNames[event.rawValue]
    }
}
