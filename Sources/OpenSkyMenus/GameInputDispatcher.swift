// Logical game actions and the one place they turn into game input. The
// keyboard and the agent control server both call it, so the game cannot tell
// a key press from an injected one (docs/tools/agent-control.md).

import OpenSkyRendering

/// One logical action. The raw value is the name `openskycli game input` takes.
nonisolated public enum GameInputAction: String, CaseIterable, Sendable {
    case forward, back, left, right, up, down
    case run, sprint, sneak, jump, activate, attack, block
    case readyWeapon, cameraMode, journal, inventory
    case menuUp, menuDown, menuLeft, menuRight, menuAccept, menuCancel

    /// A held action stays down until released; the rest fire once on press.
    public var isHeld: Bool {
        switch self {
        case .forward, .back, .left, .right, .up, .down, .run, .sprint, .attack, .block: true
        default: false
        }
    }

    var moveKey: CameraInputState.MoveKey? {
        switch self {
        case .forward: .forward
        case .back: .back
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        default: nil
        }
    }

    /// The menu event this action sends while a menu owns input. W, A, S and D
    /// steer a menu as the arrow keys do.
    var menuDirection: MenuInputEvent.Direction? {
        switch self {
        case .forward, .menuUp: .up
        case .back, .menuDown: .down
        case .left, .menuLeft: .left
        case .right, .menuRight: .right
        default: nil
        }
    }
}

public enum GameInputPhase: Sendable {
    case press
    case release
}

/// Applies actions to the camera input and the menu layer. A value: the view
/// and the agent each build one over the same shared state.
public struct GameInputDispatcher {
    public enum Outcome: Equatable {
        /// The world input took it.
        case world
        /// A menu got this event.
        case menu(MenuInputEvent)
        /// A menu owns input and has no use for this action.
        case swallowed
        /// No menu is open, so a menu action does nothing.
        case noMenu
    }

    public let input: CameraInputState?
    public let menuMode: MenuModeController?
    public let openJournal: (() -> Void)?
    public let openInventory: (() -> Void)?

    public init(
        input: CameraInputState?,
        menuMode: MenuModeController?,
        openJournal: (() -> Void)? = nil,
        openInventory: (() -> Void)? = nil
    ) {
        self.input = input
        self.menuMode = menuMode
        self.openJournal = openJournal
        self.openInventory = openInventory
    }

    @discardableResult
    public func apply(_ action: GameInputAction, _ phase: GameInputPhase) -> Outcome {
        if menuMode?.isMenuMode == true {
            return applyToMenu(action, phase)
        }
        switch action {
        case .menuUp, .menuDown, .menuLeft, .menuRight, .menuAccept, .menuCancel:
            return .noMenu
        default:
            applyToWorld(action, pressed: phase == .press)
            return .world
        }
    }

    private func applyToMenu(_ action: GameInputAction, _ phase: GameInputPhase) -> Outcome {
        let event: MenuInputEvent? = switch (action, phase) {
        case (.menuAccept, .press): .button(.accept)
        case (.menuCancel, .press): .button(.cancel)
        case (_, .press): action.menuDirection.map { .move($0) }
        case (_, .release): action.menuDirection.map { .release($0) }
        }
        guard let event else { return .swallowed }
        menuMode?.routeMenuInput(event)
        return .menu(event)
    }

    private func applyToWorld(_ action: GameInputAction, pressed: Bool) {
        if action.isHeld {
            applyHeld(action, pressed: pressed)
            return
        }
        guard pressed else { return }
        switch action {
        case .sneak: input?.toggleSneak()
        case .jump: input?.requestJump()
        case .activate: input?.requestActivation()
        case .readyWeapon: input?.requestWeaponToggle()
        case .cameraMode: input?.requestCameraModeCycle()
        case .journal: openJournal?()
        case .inventory: openInventory?()
        default: break
        }
    }

    private func applyHeld(_ action: GameInputAction, pressed: Bool) {
        if let move = action.moveKey {
            if pressed {
                input?.press(move)
            } else {
                input?.release(move)
            }
            return
        }
        switch action {
        case .run: input?.setBoost(pressed)
        case .sprint: input?.setSprint(pressed)
        case .block: input?.setBlocking(pressed)
        case .attack:
            // One press gives both signals: melee latches on the edge, archery
            // draws while the button stays down.
            if pressed {
                input?.requestAttack()
            }
            input?.setAttackHeld(pressed)
        default: break
        }
    }
}
