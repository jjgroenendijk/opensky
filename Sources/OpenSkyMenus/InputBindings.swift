// Which key fires which game action. Defaults come from the install's
// controlmap.txt (docs/formats/controlmap.md), then OpenSky's own overrides for a
// Mac keyboard, then the player's remaps from the settings store.

import Foundation
import OpenSkyFormatsCore

/// The input context an action belongs to. A key can mean one thing per context.
nonisolated public enum InputContext: String, CaseIterable, Sendable {
    case gameplay = "Main Gameplay"
    case menu = "Menu Mode"
    /// OpenSky actions vanilla does not have, such as flying up and down.
    case opensky = "OpenSky"
}

/// One remappable row: the action, its controlmap event, and its default key.
nonisolated public struct InputBindingSlot: Equatable, Sendable {
    public let action: GameInputAction
    public let context: InputContext
    public let event: String
    public let remappable: Bool

    public var key: String {
        "\(context.rawValue)|\(event)"
    }
}

nonisolated public enum InputRebindResult: Equatable, Sendable {
    case bound
    /// The key was taken in the same context; that action got the old key.
    case swapped(with: GameInputAction)
    case notRemappable
    case unknownKey
}

nonisolated public struct InputBindings: Equatable, Sendable {
    /// Keyboard actions in the Controls page order. Attack and block stay on the mouse.
    public static let slots: [InputBindingSlot] = [
        slot(.forward, .gameplay, "Forward"), slot(.back, .gameplay, "Back"),
        slot(.left, .gameplay, "Strafe Left"), slot(.right, .gameplay, "Strafe Right"),
        slot(.activate, .gameplay, "Activate"), slot(.readyWeapon, .gameplay, "Ready Weapon"),
        slot(.cameraMode, .gameplay, "Toggle POV"), slot(.jump, .gameplay, "Jump"),
        slot(.sprint, .gameplay, "Sprint"), slot(.sneak, .gameplay, "Sneak"),
        slot(.run, .gameplay, "Run"), slot(.journal, .gameplay, "Journal"),
        slot(.inventory, .gameplay, "Quick Inventory"), slot(.map, .gameplay, "Quick Map"),
        slot(.quicksave, .gameplay, "Quicksave"), slot(.quickload, .gameplay, "Quickload"),
        slot(.pause, .gameplay, "Pause"),
        slot(.up, .opensky, "Fly Up"), slot(.down, .opensky, "Fly Down")
    ]

    /// Keys that differ from the PC file on a Mac. Control-click is a right click on
    /// macOS, so Sneak moves from Left Control to C, which leaves Auto-Move unbound.
    public static let macOverrides: [String: UInt32] = [
        "Main Gameplay|Sneak": 0x2E,
        "OpenSky|Fly Up": 0x2D,
        "OpenSky|Fly Down": 0x2F
    ]

    /// Vanilla keys, used when the install's controlmap.txt cannot be read.
    public static let builtInDefaults: [String: UInt32] = [
        "Main Gameplay|Forward": 0x11, "Main Gameplay|Back": 0x1F,
        "Main Gameplay|Strafe Left": 0x1E, "Main Gameplay|Strafe Right": 0x20,
        "Main Gameplay|Activate": 0x12, "Main Gameplay|Ready Weapon": 0x13,
        "Main Gameplay|Toggle POV": 0x21, "Main Gameplay|Jump": 0x39,
        "Main Gameplay|Sprint": 0x38, "Main Gameplay|Sneak": 0x1D, "Main Gameplay|Run": 0x2A,
        "Main Gameplay|Journal": 0x24, "Main Gameplay|Quick Inventory": 0x17,
        "Main Gameplay|Quick Map": 0x32, "Main Gameplay|Quicksave": 0x3F,
        "Main Gameplay|Quickload": 0x43, "Main Gameplay|Pause": 0x01
    ]

    /// Menu keys OpenSky adds to the controlmap's: Return, keypad Enter, the arrows,
    /// and Tab, which vanilla gives to the Tween Menu.
    public static let menuExtras: [UInt16: GameInputAction] = [
        36: .menuAccept, 76: .menuAccept, 48: .menuCancel, 126: .menuUp, 125: .menuDown,
        123: .menuLeft, 124: .menuRight
    ]

    public private(set) var defaults: [String: UInt32]
    public private(set) var overrides: [String: UInt32] = [:]
    /// Menu Mode events and the gameplay events they point at, from the file.
    public private(set) var menuReferences: [GameInputAction: [String]]
    /// Slots the file marks as not remappable on the keyboard.
    public private(set) var fixedKeys: Set<String> = []

    public init(controlMap: ControlMapFile? = nil) {
        var defaults = Self.builtInDefaults
        var references = Self.vanillaMenuReferences
        if
            let controlMap, let gameplay = controlMap.contexts.firstIndex(where: {
                $0.name == InputContext.gameplay.rawValue
            })
        {
            fixedKeys = Set(controlMap.contexts[gameplay].events.filter { !$0.remappableKeyboard }
                .map { "\(InputContext.gameplay.rawValue)|\($0.name)" })
            for slot in Self.slots where slot.context == .gameplay {
                if
                    let code = controlMap.codes(of: slot.event, in: gameplay, device: .keyboard)
                        .first
                {
                    defaults[slot.key] = code
                }
            }
            references = Self.menuReferences(in: controlMap) ?? references
        }
        defaults.merge(Self.macOverrides) { _, mac in mac }
        self.defaults = defaults
        menuReferences = references
    }

    public static func slot(for action: GameInputAction) -> InputBindingSlot? {
        slots.first { $0.action == action }
    }

    public func scanCode(for action: GameInputAction) -> UInt32? {
        guard let slot = Self.slot(for: action) else { return nil }
        return overrides[slot.key] ?? defaults[slot.key]
    }

    public func isRemapped(_ action: GameInputAction) -> Bool {
        Self.slot(for: action).map { overrides[$0.key] != nil } ?? false
    }

    /// The action a Mac key fires. In a menu the gameplay keys the controlmap names
    /// steer the menu, and so do the extras.
    public func action(forMacKey keyCode: UInt16, inMenu: Bool) -> GameInputAction? {
        if inMenu, let extra = Self.menuExtras[keyCode] {
            return extra
        }
        guard let code = DirectInputKeyCodes.scanCode(keyCode) else { return nil }
        let world = Self.slots.first { scanCode(for: $0.action) == code }?.action
        guard inMenu else { return world }
        if
            let world, let menu = menuReferences.first(where: {
                $0.value.contains(Self.slot(for: world)?.event ?? "")
            })?.key
        {
            return menu
        }
        return world == .pause ? .menuCancel : nil
    }

    /// Binds `scanCode` to `action`. A key already used in the same context moves
    /// to the action's old key, so no action is left without one.
    @discardableResult
    public mutating func rebind(
        _ action: GameInputAction,
        to scanCode: UInt32
    ) -> InputRebindResult {
        guard let slot = Self.slot(for: action) else { return .notRemappable }
        guard slot.remappable, !fixedKeys.contains(slot.key) else { return .notRemappable }
        guard DirectInputKeyCodes.macKeyCode(scanCode) != nil else { return .unknownKey }
        let old = self.scanCode(for: action)
        let holder = Self.slots.first {
            $0.action != action && $0.context == slot.context && self
                .scanCode(for: $0.action) == scanCode
        }
        set(slot, to: scanCode)
        guard let holder else { return .bound }
        if let old {
            set(holder, to: old)
        }
        return .swapped(with: holder.action)
    }

    public mutating func reset() {
        overrides = [:]
    }

    /// Restores remaps saved by key, dropping any for an unknown event.
    public mutating func restore(_ saved: [String: Int]) {
        let known = Set(Self.slots.map(\.key))
        overrides = saved.reduce(into: [:]) { result, pair in
            guard
                known.contains(pair.key), pair.value >= 0,
                DirectInputKeyCodes.macKeyCode(UInt32(pair.value)) != nil
            else { return }
            result[pair.key] = UInt32(pair.value)
        }
    }

    private mutating func set(_ slot: InputBindingSlot, to scanCode: UInt32) {
        overrides[slot.key] = defaults[slot.key] == scanCode ? nil : scanCode
    }

    private static func slot(
        _ action: GameInputAction, _ context: InputContext, _ event: String
    ) -> InputBindingSlot {
        InputBindingSlot(action: action, context: context, event: event, remappable: true)
    }

    private static let menuEvents: [(String, GameInputAction)] = [
        ("Accept", .menuAccept), ("Cancel", .menuCancel), ("Up", .menuUp),
        ("Down", .menuDown), ("Left", .menuLeft), ("Right", .menuRight)
    ]

    static let vanillaMenuReferences: [GameInputAction: [String]] = [
        .menuAccept: ["Activate"], .menuCancel: ["Tween Menu", "Pause"],
        .menuUp: ["Forward"], .menuDown: ["Back"], .menuLeft: ["Strafe Left"],
        .menuRight: ["Strafe Right"]
    ]

    private static func menuReferences(in file: ControlMapFile) -> [GameInputAction: [String]]? {
        guard let menu = file.context(named: InputContext.menu.rawValue) else { return nil }
        var result: [GameInputAction: [String]] = [:]
        for (event, action) in menuEvents {
            let names = menu.event(named: event)?.keyboard.compactMap { input -> String? in
                if case let .reference(_, name) = input {
                    return name
                }
                return nil
            } ?? []
            result[action] = names
        }
        return result
    }
}
