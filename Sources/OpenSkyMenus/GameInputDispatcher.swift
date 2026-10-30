// Logical game actions and the one place they turn into game input. The
// keyboard and the agent control server both call it, so the game cannot tell
// a key press from an injected one (docs/tools/agent-control.md).

import OpenSkyRendering
import OpenSkyScriptingInterface

/// One logical action. The raw value is the name `openskycli game input` takes.
nonisolated public enum GameInputAction: String, CaseIterable, Sendable {
    case forward, back, left, right, up, down
    case run, sprint, sneak, jump, activate, attack, block, shout
    case readyWeapon, cameraMode, journal, inventory, skills
    case map, magic, wait, quicksave, quickload, pause
    case menuUp, menuDown, menuLeft, menuRight, menuAccept, menuCancel
    case hotkey1, hotkey2, hotkey3, hotkey4, hotkey5, hotkey6, hotkey7, hotkey8

    /// A held action stays down until released; the rest fire once on press.
    public var isHeld: Bool {
        switch self {
        case .forward, .back, .left, .right, .up, .down, .run, .sprint, .attack, .block, .shout:
            true
        default: false
        }
    }

    /// A beast form cannot open the character menus or the map, switch the camera, or
    /// use favourites (UESP "Skyrim:Lycanthropy", "Skyrim:Vampire Lord").
    public var isBlockedInBeastForm: Bool {
        switch self {
        case .inventory, .magic, .map, .skills, .cameraMode: true
        default: hotkeySlot != nil
        }
    }

    /// The `DisablePlayerControls` group that locks this action, or nil when none does.
    /// The wait key and the favourites open menus, so the menu group locks them.
    public var controlGroup: PlayerControlGroup? {
        switch self {
        case .forward, .back, .left, .right, .up, .down, .run, .sprint, .jump: .movement
        case .attack, .block, .shout, .readyWeapon: .fighting
        case .cameraMode: .camSwitch
        case .sneak: .sneaking
        case .activate: .activate
        case .journal: .journal
        case .inventory, .magic, .map, .skills, .wait: .menu
        default: hotkeySlot != nil ? .menu : nil
        }
    }

    /// Map, magic, wait, saves, pause, skills, and the hotkeys: the app carries these out.
    var isAppCommand: Bool {
        [.map, .magic, .wait, .quicksave, .quickload, .pause, .skills].contains(self)
            || hotkeySlot != nil
    }

    /// The favourites slot, 1 to 8, a hotkey action uses.
    public var hotkeySlot: Int? {
        let hotkeys: [Self] = [
            .hotkey1, .hotkey2, .hotkey3, .hotkey4, .hotkey5, .hotkey6, .hotkey7, .hotkey8
        ]
        return hotkeys.firstIndex(of: self).map { $0 + 1 }
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
    /// Map, magic, wait, saves, pause, and skills: commands the app carries out.
    public let onCommand: ((GameInputAction) -> Void)?
    /// What scripts and a beast form have locked; a locked action does nothing.
    public let locks: PlayerControlLocks
    /// A locked action the player pressed, so the shell can show the game's text.
    public let onRefused: ((PlayerControlRefusal) -> Void)?

    public init(
        input: CameraInputState?,
        menuMode: MenuModeController?,
        openJournal: (() -> Void)? = nil,
        openInventory: (() -> Void)? = nil,
        onCommand: ((GameInputAction) -> Void)? = nil,
        locks: PlayerControlLocks = .none,
        onRefused: ((PlayerControlRefusal) -> Void)? = nil
    ) {
        self.input = input
        self.menuMode = menuMode
        self.openJournal = openJournal
        self.openInventory = openInventory
        self.onCommand = onCommand
        self.locks = locks
        self.onRefused = onRefused
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
        if phase == .press, action == .quicksave || action == .quickload {
            onRefused?(action == .quicksave ? .quickSaveWhilePaused : .quickLoadWhilePaused)
            return .swallowed
        }
        let event: MenuInputEvent? = switch (action, phase) {
        case (.menuAccept, .press): .button(.accept)
        case (.menuCancel, .press): .button(.cancel)
        case (.readyWeapon, .press): .button(.xButton)
        case (.jump, .press): .button(.yButton)
        case (_, .press): action.menuDirection.map { .move($0) }
        case (_, .release): action.menuDirection.map { .release($0) }
        }
        guard let event else { return .swallowed }
        menuMode?.routeMenuInput(event)
        return .menu(event)
    }

    private func applyToWorld(_ action: GameInputAction, pressed: Bool) {
        if pressed, let refusal = refusal(of: action) {
            onRefused?(refusal)
            return
        }
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
        default:
            if action.isAppCommand {
                onCommand?(action)
            }
        }
    }

    private func refusal(of action: GameInputAction) -> PlayerControlRefusal? {
        guard let group = action.controlGroup else { return nil }
        return locks.refusal(for: group, beastLocked: action.isBlockedInBeastForm)
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
        case .shout: input?.setShouting(pressed)
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
