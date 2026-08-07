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

    /// Menu-mode source of truth (todo 8.1.2). When it reports menu mode, this
    /// view stops feeding world input and forwards the mapped menu events
    /// instead. nil (before wiring / tests) leaves every event on the world
    /// path, exactly as before menu mode existed.
    var menuMode: MenuModeController?

    /// World-mode journal key (issue #184). Set by `GameViewController`; nil
    /// leaves J unmapped, exactly as it was before the journal existed.
    ///
    /// This is the first key that opens a menu from gameplay. It is an
    /// accelerator for `World > Quests & Journal > Page > Open journal` rather
    /// than a behaviour of its own, which is what keeps it inside the app-ui
    /// rule against unadvertised keystrokes.
    var onJournalKey: (() -> Void)?

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
        static let keyF: UInt16 = 3
        static let keyG: UInt16 = 5
        static let keyJ: UInt16 = 38
        static let keyC: UInt16 = 8
        static let keyR: UInt16 = 15
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let arrowLeft: UInt16 = 123
        static let arrowRight: UInt16 = 124
        static let arrowDown: UInt16 = 125
        static let arrowUp: UInt16 = 126
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
        // Menu mode is the input-capture switch: world movement/look keys are
        // suppressed and mapped to menu events for the menu layer (todo 8.1.2).
        if menuMode?.isMenuMode == true {
            routeMenuKey(event)
            return
        }
        if event.keyCode == KeyCode.escape {
            releaseCapture()
            return
        }
        if event.keyCode == KeyCode.keyF {
            input?.requestActivation()
            return
        }
        if event.keyCode == KeyCode.keyG {
            input?.requestCameraModeCycle()
            return
        }
        if event.keyCode == KeyCode.keyJ {
            onJournalKey?()
            return
        }
        // Locomotion keys (issue #188). Space is the vanilla jump binding; C
        // stands in for the vanilla sneak toggle because macOS reserves
        // Control-click as the secondary click. Both are walk-mode gameplay
        // input rather than dev configuration, and both are listed on the
        // `World > Player & Locomotion` panel.
        if event.keyCode == KeyCode.space {
            input?.requestJump()
            return
        }
        if event.keyCode == KeyCode.keyC {
            input?.toggleSneak()
            return
        }
        // Melee keys (issue #195). R is the vanilla draw/sheath binding and is
        // free on macOS; the mouse buttons below carry attack and block, which
        // is also where vanilla puts them. All three are listed on the
        // `World > Player & Locomotion > Melee` section.
        if event.keyCode == KeyCode.keyR {
            input?.requestWeaponToggle()
            return
        }
        guard let key = Self.moveKey(for: event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        input?.press(key)
    }

    override func keyUp(with event: NSEvent) {
        // Menus act on key-down; swallow key-up so it never reaches world input.
        if menuMode?.isMenuMode == true {
            return
        }
        guard let key = Self.moveKey(for: event.keyCode) else {
            super.keyUp(with: event)
            return
        }
        input?.release(key)
    }

    /// Maps a key-down to a toolkit-free menu event and routes it while menu
    /// mode is active. Unmapped keys are swallowed (still suppressed from the
    /// world) rather than passed on.
    private func routeMenuKey(_ event: NSEvent) {
        let menuEvent: MenuInputEvent? = switch event.keyCode {
        case KeyCode.keyW, KeyCode.arrowUp: .move(.up)
        case KeyCode.keyS, KeyCode.arrowDown: .move(.down)
        case KeyCode.keyA, KeyCode.arrowLeft: .move(.left)
        case KeyCode.keyD, KeyCode.arrowRight: .move(.right)
        case KeyCode.returnKey, KeyCode.keypadEnter: .button(.accept)
        case KeyCode.escape: .button(.cancel)
        default: nil
        }
        if let menuEvent {
            menuMode?.routeMenuInput(menuEvent)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        input?.setBoost(event.modifierFlags.contains(.shift))
        // Option is the vanilla sprint modifier (Alt on a PC keyboard).
        input?.setSprint(event.modifierFlags.contains(.option))
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
        // Menu mode keeps the pointer free (a menu wants a visible cursor); a
        // click is the accept button for the menu layer.
        if menuMode?.isMenuMode == true {
            menuMode?.routeMenuInput(.button(.accept))
            return
        }
        // The first click captures the cursor; every click after that is the
        // attack binding (issue #195), which is where vanilla puts it. Look is
        // driven by pointer motion rather than by the button, so nothing is
        // lost by giving the button to combat.
        if captured {
            // Both signals from one press: melee latches on the edge, archery
            // draws for as long as the level stays up (issue #196).
            input?.requestAttack()
            input?.setAttackHeld(true)
        } else {
            captureCursor()
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Dropped unconditionally rather than only while captured: a button
        // that went down inside the view and came up outside it must not leave
        // a bow drawn forever.
        input?.setAttackHeld(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Block is held, so it is a button-down/up pair rather than a latch.
        // Menu mode swallows it; a menu has no guard to raise.
        guard menuMode?.isMenuMode != true, captured else {
            super.rightMouseDown(with: event)
            return
        }
        input?.setBlocking(true)
    }

    override func rightMouseUp(with event: NSEvent) {
        input?.setBlocking(false)
    }

    override func mouseMoved(with event: NSEvent) {
        handleLook(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleLook(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handleLook(event)
    }

    private func handleLook(_ event: NSEvent) {
        // Menu mode routes pointer motion to the menu layer instead of camera
        // look; capture state is irrelevant there.
        if menuMode?.isMenuMode == true {
            menuMode?.routeMenuInput(
                .pointer(deltaX: Float(event.deltaX), deltaY: Float(event.deltaY))
            )
            return
        }
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
