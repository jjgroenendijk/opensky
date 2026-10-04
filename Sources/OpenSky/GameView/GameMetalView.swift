// MTKView subclass that turns AppKit key and pointer events into game actions
// through `GameInputDispatcher`. Click captures the pointer; Esc or focus loss releases it.
// Camera math lives in `FreeFlyCamera` (docs/engine/free-fly-camera.md).

import AppKit
import MetalKit
import OpenSkyMenus
import OpenSkyRendering

final class GameMetalView: MTKView {
    /// Shared with the renderer; nil before wiring (renderer then stays on its
    /// seeded pose).
    var input: CameraInputState?

    /// Menu-mode source of truth. When it reports menu mode, this
    /// view stops feeding world input and forwards the mapped menu events
    /// instead. nil (before wiring / tests) leaves every event on the world
    /// path, exactly as before menu mode existed.
    var menuMode: MenuModeController?

    /// World-mode journal key. Nil leaves J unmapped. It is an accelerator for
    /// `World > Quests & Journal > Page > Open journal`, so the app-ui rule
    /// against unadvertised keystrokes holds.
    var onJournalKey: (() -> Void)?

    /// The input event name of a world key, such as "Jump", for help messages.
    var onInputEvent: ((String) -> Void)?

    /// The cursor side effects of pointer capture. A headless route swaps in
    /// `.none` so its clicks take the `mouseDown` path without freezing the
    /// machine's own cursor.
    struct PointerCapture {
        let engage: () -> Void
        let release: () -> Void

        /// Hide the cursor and read raw deltas — what a captured window does.
        static let system = PointerCapture(
            engage: {
                NSCursor.hide()
                CGAssociateMouseAndMouseCursorPosition(0)
            },
            release: {
                CGAssociateMouseAndMouseCursorPosition(1)
                NSCursor.unhide()
            }
        )

        /// Track capture state and leave the cursor alone.
        static let none = PointerCapture(engage: {}, release: {})
    }

    var pointerCapture = PointerCapture.system

    private var captured = false

    /// World-mode inventory key, an accelerator like `onJournalKey` for
    /// `World > Menus > Inventory Menu > Open`.
    var onInventoryKey: (() -> Void)?

    /// The install's keys plus the player's remaps; the settings coordinator sets it.
    var bindings = InputBindings()
    /// Map, quicksave, quickload, and pause.
    var onCommand: ((GameInputAction) -> Void)?
    /// The Controls page waiting for a key; true when it took the key.
    var onCapturedKey: ((UInt32) -> Bool)?
    /// A menu that takes typed text, such as the race menu name; true when it did.
    var onTypedText: ((String) -> Bool)?

    /// The path every key press takes, shared with the agent control server.
    var dispatcher: GameInputDispatcher {
        GameInputDispatcher(
            input: input,
            menuMode: menuMode,
            openJournal: onJournalKey,
            openInventory: onInventoryKey,
            onCommand: onCommand
        )
    }

    /// US ANSI virtual key codes (Carbon `kVK_*`). Physical layout, not
    /// characters, so the keys stay in place on any keyboard layout.
    private enum KeyCode {
        static let escape: UInt16 = 53
        static let textKeysExcluded: Set<UInt16> = [36, 76, 53]
    }

    private var inMenu: Bool {
        menuMode?.isMenuMode == true
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
        if inMenu, takeMenuKey(event) {
            return
        }
        // Outside a menu, the first Esc releases a captured pointer.
        if event.keyCode == KeyCode.escape, !inMenu, captured {
            releaseCapture()
            return
        }
        guard let action = bindings.action(forMacKey: event.keyCode, inMenu: inMenu) else {
            // A menu swallows unbound keys so none reaches the world.
            if !inMenu {
                super.keyDown(with: event)
            }
            return
        }
        if !inMenu, let name = Self.helpEvents[action] {
            onInputEvent?(name)
        }
        dispatcher.apply(action, .press)
    }

    /// Key capture for the Controls page, then typed text for a name field.
    private func takeMenuKey(_ event: NSEvent) -> Bool {
        if let code = DirectInputKeyCodes.scanCode(event.keyCode), onCapturedKey?(code) == true {
            return true
        }
        guard
            !KeyCode.textKeysExcluded.contains(event.keyCode),
            let text = event.characters, !text.isEmpty
        else { return false }
        return onTypedText?(text) == true
    }

    /// The input event names a help message can wait for.
    private static let helpEvents: [GameInputAction: String] = [
        .activate: "Activate", .jump: "Jump", .sneak: "Sneak"
    ]

    override func keyUp(with event: NSEvent) {
        // Menus act on key-down; a held direction's key-up reaches a menu that
        // reads held keys. One-shot actions have no key-up.
        guard
            let action = bindings.action(forMacKey: event.keyCode, inMenu: inMenu),
            action.isHeld || inMenu
        else {
            if !inMenu {
                super.keyUp(with: event)
            }
            return
        }
        dispatcher.apply(action, .release)
    }

    /// A modifier key bound to an action, such as Shift for run and Option for
    /// sprint, presses while its flag is set.
    override func flagsChanged(with event: NSEvent) {
        if
            !inMenu, DirectInputKeyCodes.modifierKeyCodes.contains(event.keyCode),
            let action = bindings.action(forMacKey: event.keyCode, inMenu: false),
            let flag = Self.modifierFlags[event.keyCode]
        {
            dispatcher.apply(action, event.modifierFlags.contains(flag) ? .press : .release)
        }
        super.flagsChanged(with: event)
    }

    private static let modifierFlags: [UInt16: NSEvent.ModifierFlags] = [
        56: .shift, 60: .shift, 58: .option, 61: .option, 59: .control, 62: .control,
        55: .command, 54: .command, 57: .capsLock
    ]

    // MARK: - Pointer

    override func mouseDown(with event: NSEvent) {
        // Menu mode keeps the pointer free (a menu wants a visible cursor); a
        // click is the accept button for the menu layer.
        if menuMode?.isMenuMode == true {
            menuMode?.routeMenuInput(.button(.accept))
            return
        }
        // The first click captures the cursor; every later click attacks, as
        // in vanilla. Look follows pointer motion, so the button is free.
        if captured {
            dispatcher.apply(.attack, .press)
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
        dispatcher.apply(.block, .press)
    }

    override func rightMouseUp(with event: NSEvent) {
        dispatcher.apply(.block, .release)
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
        // Hides the cursor and detaches it from the pointer so we read pure
        // deltas and the cursor cannot leave the window.
        pointerCapture.engage()
    }

    private func releaseCapture() {
        guard captured else { return }
        captured = false
        pointerCapture.release()
        window?.acceptsMouseMovedEvents = false
        // Drop held keys/deltas so nothing sticks while uncaptured.
        input?.releaseAll()
    }

    override func resignFirstResponder() -> Bool {
        releaseCapture()
        return super.resignFirstResponder()
    }
}
