// Input injection for a running movie (milestone 8.3.2 phase 3). Pointer and
// key events are handed to the runtime explicitly — nothing here reads a clock,
// an `NSEvent`, or any global — so a test, the offscreen render path, and the
// app all drive the same code and produce the same result.
//
// Coordinates arrive in *movie stage pixels*, the same space `Stage.width`,
// `Stage.height`, and `_xmouse` are expressed in. `SWFInputMapping` converts a
// viewport pixel into that space by inverting the letterbox transform
// `SWFViewportMapping.twipsToPixels` builds, so the pointer lands on the object
// the user is actually looking at. Internally everything is twips, because the
// display list is.
//
// Where an event goes is decided by the 8.3.1 clip-event measurement: every
// mouse and key CLIPACTIONS event is zero across all 53 vanilla movies, so
// input cannot be delivered through clip events alone. A pointer event goes to
// the hit-tested display object's handler members (`onPress`, `onRollOver`, and
// the rest, which is what CLIK's `Button` assigns) and to the `Mouse`
// broadcaster; a key event goes to the `Key` broadcaster, which is where CLIK's
// `gfx.managers.InputDelegate` registers itself and from where the framework's
// own focus and navigation path takes over.

import Foundation
import simd

/// One injected input event. Pointer coordinates are movie stage pixels.
nonisolated enum SWFInputEvent: Equatable {
    case pointerMoved(x: Double, y: Double)
    case pointerPressed(x: Double, y: Double)
    case pointerReleased(x: Double, y: Double)
    case pointerWheel(delta: Double)
    /// `ascii` is the character the key produced, or 0 when it produced none.
    case keyDown(code: Int, ascii: Int)
    case keyUp(code: Int)
}

/// Live pointer, key, and focus state. A class so the runtime can hold it
/// without growing its own type body, and so the natives can read it back
/// through the host.
nonisolated final class SWFRuntimeInputState {
    /// Pointer position in stage twips.
    var pointer = SIMD2<Float>.zero
    var isPointerDown = false
    /// `Key.getCode()` / `Key.getAscii()`: the most recent key event.
    var lastKeyCode = 0
    var lastKeyAscii = 0
    /// Codes currently held, for `Key.isDown`.
    private(set) var downKeys: Set<Int> = []
    /// Node under the pointer, for rollover and rollout transitions.
    weak var hoverTarget: SWFDisplayObject?
    /// Node the press started on, for release and release-outside routing.
    weak var pressTarget: SWFDisplayObject?
    /// Events accepted, reported by the UI Lab readout.
    private(set) var pointerEvents = 0
    private(set) var keyEvents = 0

    /// Held keys kept. A stuck key from a dropped key-up must not grow the set
    /// without bound; the AS2 key domain is a byte anyway.
    static let maximumHeldKeys = 256

    func notePointerEvent() {
        pointerEvents += 1
    }

    func noteKeyEvent() {
        keyEvents += 1
    }

    func hold(_ code: Int) {
        guard downKeys.count < SWFRuntimeInputState.maximumHeldKeys else {
            return
        }
        downKeys.insert(code)
    }

    func release(_ code: Int) {
        downKeys.remove(code)
    }

    func isDown(_ code: Int) -> Bool {
        downKeys.contains(code)
    }
}

nonisolated extension SWFMovieRuntime {
    /// Injects one input event. Returns true when something in the movie
    /// consumed it — a handler member ran, a broadcaster listener ran, or a
    /// CLIPACTIONS handler ran. A false answer is normal and never a fault; it
    /// is what lets the engine give an unconsumed key to the world instead.
    @discardableResult
    func handle(_ event: SWFInputEvent) -> Bool {
        guard isStarted else {
            return false
        }
        switch event {
        case let .pointerMoved(pointX, pointY):
            return movePointer(to: stageTwips(pointX, pointY))
        case let .pointerPressed(pointX, pointY):
            return pressPointer(at: stageTwips(pointX, pointY))
        case let .pointerReleased(pointX, pointY):
            return releasePointer(at: stageTwips(pointX, pointY))
        case let .pointerWheel(delta):
            return wheelPointer(delta: delta)
        case let .keyDown(code, ascii):
            return keyDown(code: code, ascii: ascii)
        case let .keyUp(code):
            return keyUp(code: code)
        }
    }

    /// The pointer in a node's local space, in pixels — `_xmouse` / `_ymouse`.
    func mousePosition(in node: SWFDisplayObject) -> SIMD2<Float> {
        guard let inverse = transform(of: node)?.inverted else {
            return input.pointer / Self.twipsPerPixel
        }
        return inverse.apply(input.pointer) / Self.twipsPerPixel
    }

    /// A node's accumulated matrix from the root, or nil when the node is not in
    /// this tree.
    func transform(of node: SWFDisplayObject) -> SWFTransform? {
        var chain: [SWFDisplayObject] = []
        var current: SWFDisplayObject? = node
        var steps = 0
        while let walked = current, steps <= SWFDisplayObject.maximumTreeDepth {
            if walked === root {
                return chain.reversed().reduce(SWFTransform.identity) {
                    $0.concatenating(SWFTransform(matrix: $1.matrix))
                }
            }
            chain.append(walked)
            current = walked.parent
            steps += 1
        }
        return nil
    }

    private func stageTwips(_ pointX: Double, _ pointY: Double) -> SIMD2<Float> {
        SIMD2(
            Float(Self.twips(pointX)) + Float(movie.frameSize.xMin),
            Float(Self.twips(pointY)) + Float(movie.frameSize.yMin)
        )
    }

    // MARK: - Pointer

    private func movePointer(to point: SIMD2<Float>) -> Bool {
        input.pointer = point
        input.notePointerEvent()
        markDirty()
        var handled = retargetHover()
        handled = dispatchGlobalMouse(.mouseMove) || handled
        handled = broadcastMouse("onMouseMove") > 0 || handled
        return handled
    }

    /// `onMouseDown`, `onMouseUp`, and `onMouseMove` are *global* in Flash: every
    /// clip that defines one is called wherever the pointer is, unlike
    /// `onPress`, which only reaches the object under it. Vanilla depends on the
    /// distinction — `tweenmenu.swf` wires each of its four input rectangles
    /// with an `onRollOver` for highlighting and an `onMouseDown` for
    /// activation, and the second would never fire on a hit-target-only route.
    @discardableResult
    private func dispatchGlobalMouse(_ event: SWFClipEventFlags) -> Bool {
        var handled = false
        forEachClip { node in
            handled = dispatchClipEvent(event, to: node) || handled
        }
        return handled
    }

    /// Rollover, rollout, and the drag variants Flash sends while a button is
    /// held: leaving the pressed object is `onDragOut`, re-entering it is
    /// `onDragOver`.
    private func retargetHover() -> Bool {
        let target = hitTest(stageTwips: input.pointer).target
        guard target !== input.hoverTarget else {
            return false
        }
        var handled = false
        if let previous = input.hoverTarget {
            let event: SWFClipEventFlags =
                input.isPointerDown && previous === input.pressTarget ? .dragOut : .rollOut
            handled = dispatchClipEvent(event, to: previous)
        }
        input.hoverTarget = target
        if let target {
            let event: SWFClipEventFlags =
                input.isPointerDown && target === input.pressTarget ? .dragOver : .rollOver
            handled = dispatchClipEvent(event, to: target) || handled
        }
        return handled
    }

    private func pressPointer(at point: SIMD2<Float>) -> Bool {
        input.pointer = point
        input.notePointerEvent()
        markDirty()
        _ = retargetHover()
        input.isPointerDown = true
        let target = input.hoverTarget
        input.pressTarget = target
        var handled = broadcastMouse("onMouseDown") > 0
        handled = dispatchGlobalMouse(.mouseDown) || handled
        if let target {
            handled = dispatchClipEvent(.press, to: target) || handled
        }
        return handled
    }

    /// A release over the pressed object is `onRelease`; a release anywhere else
    /// is `onReleaseOutside` on the object the press started on, which is what
    /// lets a CLIK button cancel cleanly.
    private func releasePointer(at point: SIMD2<Float>) -> Bool {
        input.pointer = point
        input.notePointerEvent()
        markDirty()
        _ = retargetHover()
        input.isPointerDown = false
        let pressed = input.pressTarget
        input.pressTarget = nil
        var handled = broadcastMouse("onMouseUp") > 0
        handled = dispatchGlobalMouse(.mouseUp) || handled
        guard let pressed else {
            return handled
        }
        let event: SWFClipEventFlags = pressed === input.hoverTarget ? .release : .releaseOutside
        handled = dispatchClipEvent(event, to: pressed) || handled
        return handled
    }

    private func wheelPointer(delta: Double) -> Bool {
        input.notePointerEvent()
        var handled = false
        if let hover = input.hoverTarget {
            handled = dispatch("onMouseWheel", to: hover, arguments: [.number(delta)])
        }
        let arguments: [AS2Value] = [.number(delta)]
        return broadcastMouse("onMouseWheel", arguments: arguments) > 0 || handled
    }

    @discardableResult
    private func broadcastMouse(_ message: String, arguments: [AS2Value] = []) -> Int {
        guard let mouse = globalBroadcaster("Mouse") else {
            return 0
        }
        return broadcast(message, from: mouse, arguments: arguments)
    }

    // MARK: - Keys

    /// A key down reaches the `Key` broadcaster first, because that is where
    /// CLIK's `InputDelegate` listens, and then the menu's own `handleInput`.
    ///
    /// A broadcaster listener is an *observer*, not a consumer: only
    /// `handleInput` answers whether it took the event, and vanilla movies
    /// register unrelated `Key` listeners — `Shared.GlobalFunc.IsKeyPressed` in
    /// `tweenmenu.swf` is one — that would otherwise swallow every keystroke
    /// before the menu saw it. Delivery is therefore unconditional and only the
    /// returned flag is an OR.
    private func keyDown(code: Int, ascii: Int) -> Bool {
        input.lastKeyCode = code
        input.lastKeyAscii = ascii
        input.hold(code)
        input.noteKeyEvent()
        markDirty()
        let observed = broadcastKey("onKeyDown") > 0
        var handled = dispatchKeyClipEvent(.keyDown, code: code)
        handled = routeToMenuHandler(code: code, value: "keyDown") || handled
        if !handled {
            handled = routeToFocusHandler(code: code, value: "keyDown")
        }
        if !handled, let focus = focusTarget {
            handled = dispatch("onKeyDown", to: focus)
        }
        return handled || observed
    }

    /// A key release reaches the broadcaster, the clip events, and the focused
    /// object, but *not* `handleInput`. A vanilla menu's `handleInput` acts on
    /// the event rather than on its phase — `tweenmenu.swf` moves its selection
    /// on any `InputDetails` it is handed — so routing both edges of one
    /// keystroke would move the selection twice and land back where it started.
    /// The engine therefore delivers one navigation event per press.
    private func keyUp(code: Int) -> Bool {
        input.lastKeyCode = code
        input.release(code)
        input.noteKeyEvent()
        markDirty()
        let observed = broadcastKey("onKeyUp") > 0
        var handled = dispatchKeyClipEvent(.keyUp, code: code)
        if !handled, let focus = focusTarget {
            handled = dispatch("onKeyUp", to: focus)
        }
        return handled || observed
    }

    @discardableResult
    private func broadcastKey(_ message: String) -> Int {
        guard let key = globalBroadcaster("Key") else {
            return 0
        }
        return broadcast(message, from: key)
    }

    /// Key CLIPACTIONS handlers, walked only when a placement actually attached
    /// one. No vanilla movie does — all nineteen key clip events measure zero —
    /// so this costs one integer comparison on the real install.
    private func dispatchKeyClipEvent(_ event: SWFClipEventFlags, code: Int) -> Bool {
        guard keyClipHandlers > 0 else {
            return false
        }
        let trapped = UInt8(exactly: code)
        var handled = false
        forEachClip { node in
            handled = dispatchClipEvent(event, to: node) || handled
            if event == .keyDown {
                handled = dispatchClipEvent(.keyPress, to: node, keyCode: trapped) || handled
            }
        }
        return handled
    }

    /// Bounded walk over every clip in the tree.
    func forEachClip(_ body: (SWFDisplayObject) -> Void) {
        var stack: [(node: SWFDisplayObject, depth: Int)] = [(root, 0)]
        while let entry = stack.popLast() {
            guard entry.depth < SWFDisplayObject.maximumTreeDepth else {
                continue
            }
            if entry.node !== root {
                body(entry.node)
            }
            for child in entry.node.children where child.isClip {
                stack.append((child, entry.depth + 1))
            }
        }
    }
}

/// Viewport-to-stage mapping for injected pointer events.
nonisolated enum SWFInputMapping {
    /// Converts a framebuffer pixel (origin top-left, y down) into movie stage
    /// pixels, inverting the same letterbox transform the renderer uses. Returns
    /// nil for a point in the letterbox bars, which belongs to no part of the
    /// movie.
    static func stagePoint(
        viewportPoint: SIMD2<Float>,
        frameSize: SWFRect,
        viewportPixels: SIMD2<Float>
    ) -> SIMD2<Double>? {
        let toPixels = SWFViewportMapping.twipsToPixels(
            frameSize: frameSize, viewportPixels: viewportPixels
        )
        guard let inverse = toPixels.inverted else {
            return nil
        }
        let twips = inverse.apply(viewportPoint)
        guard
            twips.x >= Float(frameSize.xMin), twips.x <= Float(frameSize.xMax),
            twips.y >= Float(frameSize.yMin), twips.y <= Float(frameSize.yMax)
        else {
            return nil
        }
        return SIMD2(
            Double(twips.x - Float(frameSize.xMin)) / Double(SWFMovieRuntime.twipsPerPixel),
            Double(twips.y - Float(frameSize.yMin)) / Double(SWFMovieRuntime.twipsPerPixel)
        )
    }
}
