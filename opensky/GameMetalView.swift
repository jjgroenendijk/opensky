// MTKView subclass owning free-fly input capture (todo 2.8). Translates AppKit
// key/pointer events into logical state on a shared `CameraInputState`; the
// renderer drains that state each frame. Pointer capture: click to grab (hide
// cursor, freeze it via CGAssociateMouseAndMouseCursorPosition so we read raw
// deltas), Esc / focus loss releases. Kept thin — all camera math is in the
// AppKit-free `FreeFlyCamera` / `CameraInputState`. See
// docs/engine/free-fly-camera.md.

import AppKit
import MetalKit

final class GameMetalView: MTKView {
    /// Shared with the renderer; nil before wiring (renderer then stays on its
    /// seeded pose).
    var input: CameraInputState?

    private var captured = false

    /// US ANSI virtual key codes (Carbon `kVK_*`). Physical layout, not
    /// characters — WASD stay under the left hand on any keyboard layout.
    private enum KeyCode {
        static let keyW: UInt16 = 13
        static let keyA: UInt16 = 0
        static let keyS: UInt16 = 1
        static let keyD: UInt16 = 2
        static let keyQ: UInt16 = 12
        static let keyE: UInt16 = 14
        static let escape: UInt16 = 53
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Ignore autorepeat: the pressed-key set already holds the key, and a
        // repeat carries no new state.
        if event.isARepeat {
            return
        }
        if event.keyCode == KeyCode.escape {
            releaseCapture()
            return
        }
        guard let key = Self.moveKey(for: event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        input?.press(key)
    }

    override func keyUp(with event: NSEvent) {
        guard let key = Self.moveKey(for: event.keyCode) else {
            super.keyUp(with: event)
            return
        }
        input?.release(key)
    }

    override func flagsChanged(with event: NSEvent) {
        input?.setBoost(event.modifierFlags.contains(.shift))
        super.flagsChanged(with: event)
    }

    private static func moveKey(for code: UInt16) -> CameraInputState.MoveKey? {
        switch code {
        case KeyCode.keyW: .forward
        case KeyCode.keyS: .back
        case KeyCode.keyA: .left
        case KeyCode.keyD: .right
        case KeyCode.keyE: .up
        case KeyCode.keyQ: .down
        default: nil
        }
    }

    // MARK: - Pointer

    override func mouseDown(with event: NSEvent) {
        if captured {
            handleLook(event)
        } else {
            captureCursor()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        handleLook(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleLook(event)
    }

    private func handleLook(_ event: NSEvent) {
        guard captured else { return }
        // NSEvent.deltaY is positive when the pointer moves down (top-left
        // origin); negate so pointer-up -> look up.
        input?.addLook(right: Float(event.deltaX), up: Float(-event.deltaY))
    }

    // MARK: - Capture

    private func captureCursor() {
        guard !captured else { return }
        captured = true
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
        NSCursor.hide()
        // Detach the hardware cursor from the pointer so we read pure deltas
        // and the cursor cannot leave the window.
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func releaseCapture() {
        guard captured else { return }
        captured = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        window?.acceptsMouseMovedEvents = false
        // Drop held keys/deltas so nothing sticks while uncaptured.
        input?.releaseAll()
    }

    override func resignFirstResponder() -> Bool {
        releaseCapture()
        return super.resignFirstResponder()
    }
}
