// Which key fires which game action. Defaults come from the install's
// controlmap.txt (docs/formats/controlmap.md), then OpenSky's own overrides for a
// Mac keyboard, then the player's remaps from the settings store.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyMenusInterface

/// The input context an action belongs to. A key can mean one thing per context.
nonisolated public enum InputContext: String, CaseIterable, Sendable {
    case gameplay = "Main Gameplay"
    case menu = "Menu Mode"
    /// OpenSky actions vanilla does not have, such as flying up and down.
    case opensky = "OpenSky"
}

/// An input code: a DirectInput scan code below 256, and a mouse button above it. Mouse
/// button `n` is `256 + n`, as SKSE's `Input.psc` numbers them; 0 is the left button.
nonisolated public enum InputCode {
    public static let mouseBase: UInt32 = 256
    /// The mouse buttons the control map's mouse column can name for a button.
    static let mouseButtons: ClosedRange<UInt32> = 0 ... 7

    public static func mouse(_ button: Int) -> UInt32 {
        mouseBase + UInt32(button)
    }

    /// The mouse button of a code, or nil for a keyboard key.
    public static func mouseButton(_ code: UInt32) -> Int? {
        code >= mouseBase ? Int(code - mouseBase) : nil
    }

    /// The button art symbol for a mouse code: `Mouse1` is the left button.
    static func mouseName(_ code: UInt32) -> String? {
        mouseButton(code).map { "Mouse\($0 + 1)" }
    }
}

/// One remappable row: the action, its controlmap event, and its default key.
nonisolated public struct InputBindingSlot: Equatable, Sendable {
    public let action: GameInputAction
    public let context: InputContext
    public let event: String
    let remappable: Bool

    public var key: String {
        "\(context.rawValue)|\(event)"
    }
}

nonisolated enum InputRebindResult: Equatable, Sendable {
    case bound
    /// The key was taken in the same context; that action got the old key.
    case swapped(with: GameInputAction)
    case notRemappable
    case unknownKey
}

nonisolated public struct InputBindings: Equatable, Sendable {
    /// Actions in the control map's order, which the Controls page sorts by. Right
    /// Attack/Block is the weapon hand's attack, Left Attack/Block the off hand's block.
    public static let slots: [InputBindingSlot] = [
        slot(.forward, .gameplay, "Forward"), slot(.back, .gameplay, "Back"),
        slot(.left, .gameplay, "Strafe Left"), slot(.right, .gameplay, "Strafe Right"),
        slot(.block, .gameplay, "Left Attack/Block"),
        slot(.attack, .gameplay, "Right Attack/Block"),
        slot(.activate, .gameplay, "Activate"), slot(.readyWeapon, .gameplay, "Ready Weapon"),
        slot(.tweenMenu, .gameplay, "Tween Menu"),
        slot(.cameraMode, .gameplay, "Toggle POV"), slot(.jump, .gameplay, "Jump"),
        slot(.sprint, .gameplay, "Sprint"), slot(.shout, .gameplay, "Shout"),
        slot(.sneak, .gameplay, "Sneak"), slot(.run, .gameplay, "Run"),
        slot(.toggleAlwaysRun, .gameplay, "Toggle Always Run"),
        slot(.autoMove, .gameplay, "Auto-Move"), slot(.favorites, .gameplay, "Favorites"),
        slot(.journal, .gameplay, "Journal"),
        slot(.inventory, .gameplay, "Quick Inventory"), slot(.map, .gameplay, "Quick Map"),
        slot(.skills, .gameplay, "Quick Stats"), slot(.magic, .gameplay, "Quick Magic"),
        slot(.wait, .gameplay, "Wait"),
        slot(.quicksave, .gameplay, "Quicksave"), slot(.quickload, .gameplay, "Quickload"),
        slot(.pause, .gameplay, "Pause"),
        slot(.hotkey1, .gameplay, "Hotkey1"), slot(.hotkey2, .gameplay, "Hotkey2"),
        slot(.hotkey3, .gameplay, "Hotkey3"), slot(.hotkey4, .gameplay, "Hotkey4"),
        slot(.hotkey5, .gameplay, "Hotkey5"), slot(.hotkey6, .gameplay, "Hotkey6"),
        slot(.hotkey7, .gameplay, "Hotkey7"), slot(.hotkey8, .gameplay, "Hotkey8"),
        slot(.up, .opensky, "Fly Up"), slot(.down, .opensky, "Fly Down")
    ]

    /// Keys that differ from the PC file on a Mac. Control-click is a right click on
    /// macOS, so Sneak moves from Left Control to C, which leaves Auto-Move unbound.
    public static let macOverrides: [String: UInt32] = [
        "Main Gameplay|Sneak": 0x2E,
        "OpenSky|Fly Up": 0x2D,
        "OpenSky|Fly Down": 0x2F
    ]
    static let macUnbound: Set = ["Main Gameplay|Auto-Move"]

    /// Vanilla keys, used when the install's controlmap.txt cannot be read.
    public static let builtInDefaults: [String: UInt32] = [
        "Main Gameplay|Forward": 0x11, "Main Gameplay|Back": 0x1F,
        "Main Gameplay|Strafe Left": 0x1E, "Main Gameplay|Strafe Right": 0x20,
        "Main Gameplay|Activate": 0x12, "Main Gameplay|Ready Weapon": 0x13,
        "Main Gameplay|Toggle POV": 0x21, "Main Gameplay|Jump": 0x39,
        "Main Gameplay|Sprint": 0x38, "Main Gameplay|Sneak": 0x1D, "Main Gameplay|Run": 0x2A,
        "Main Gameplay|Shout": 0x2C,
        "Main Gameplay|Left Attack/Block": InputCode.mouseBase + 1,
        "Main Gameplay|Right Attack/Block": InputCode.mouseBase,
        "Main Gameplay|Tween Menu": 0x0F, "Main Gameplay|Toggle Always Run": 0x3A,
        "Main Gameplay|Auto-Move": 0x2E, "Main Gameplay|Favorites": 0x10,
        "Main Gameplay|Journal": 0x24, "Main Gameplay|Quick Inventory": 0x17,
        "Main Gameplay|Quick Map": 0x32, "Main Gameplay|Quick Stats": 0x35,
        "Main Gameplay|Quick Magic": 0x19, "Main Gameplay|Wait": 0x14,
        "Main Gameplay|Quicksave": 0x3F,
        "Main Gameplay|Quickload": 0x43, "Main Gameplay|Pause": 0x01,
        "Main Gameplay|Hotkey1": 0x02, "Main Gameplay|Hotkey2": 0x03,
        "Main Gameplay|Hotkey3": 0x04, "Main Gameplay|Hotkey4": 0x05,
        "Main Gameplay|Hotkey5": 0x06, "Main Gameplay|Hotkey6": 0x07,
        "Main Gameplay|Hotkey7": 0x08, "Main Gameplay|Hotkey8": 0x09
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
    /// Slots the file lets the player bind to a mouse button. Vanilla allows every
    /// gameplay row with a keyboard key but the hotkeys and the saves.
    public private(set) var mouseKeys: Set<String> = Self.vanillaMouseKeys
    /// Gamepad buttons by slot, from the file's gamepad column; a slot can have two.
    public private(set) var gamepadDefaults: [String: [UInt32]] = Self.vanillaGamepad
    var gamepadOverrides: [String: UInt32] = [:]
    /// Slots the file lets the player bind to a gamepad button.
    public private(set) var gamepadKeys: Set<String> = Set(Self.vanillaGamepad.keys)
    /// Keys only the map reads, by scan code, from the file's `Map Menu` context.
    public private(set) var mapMenuKeys: [UInt32: GameInputAction] = Self.vanillaMapMenuKeys

    /// P places the custom marker, as the vanilla file's `PlacePlayerMarker` says.
    static let vanillaMapMenuKeys: [UInt32: GameInputAction] = [0x19: .placeMarker]
    static let mapMenuContext = "Map Menu"

    public init(controlMap: ControlMapFile? = nil) {
        var defaults = Self.builtInDefaults
        var references = Self.vanillaMenuReferences
        if
            let controlMap, let gameplay = controlMap.contexts.firstIndex(where: {
                $0.name == InputContext.gameplay.rawValue
            })
        {
            let events = controlMap.contexts[gameplay].events
            let context = InputContext.gameplay.rawValue
            fixedKeys = Set(events.filter { !$0.remappableKeyboard }
                .map { "\(context)|\($0.name)" })
            mouseKeys = Set(events.filter(\.remappableMouse).map { "\(context)|\($0.name)" })
            gamepadKeys = Set(events.filter(\.remappableGamepad).map { "\(context)|\($0.name)" })
            gamepadDefaults = [:]
            for slot in Self.slots where slot.context == .gameplay {
                let keyboard = controlMap.codes(of: slot.event, in: gameplay, device: .keyboard)
                let mouse = controlMap.codes(of: slot.event, in: gameplay, device: .mouse)
                    .filter { InputCode.mouseButtons.contains($0) }
                if let code = keyboard.first {
                    defaults[slot.key] = code
                } else if let button = mouse.first {
                    defaults[slot.key] = InputCode.mouseBase + button
                }
                let pad = controlMap.codes(of: slot.event, in: gameplay, device: .gamepad)
                    .filter { GamepadButton(controlMapCode: $0) != nil }
                if !pad.isEmpty {
                    gamepadDefaults[slot.key] = pad
                }
            }
            references = Self.menuReferences(in: controlMap) ?? references
            mapMenuKeys = Self.mapMenuKeys(in: controlMap) ?? mapMenuKeys
        }
        defaults.merge(Self.macOverrides) { _, mac in mac }
        for key in Self.macUnbound {
            defaults[key] = nil
        }
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

    /// The action a mouse button fires outside menus, such as attack for the left one.
    public func action(forMouseButton button: Int) -> GameInputAction? {
        let code = InputCode.mouse(button)
        return Self.slots.first { $0.context == .gameplay && scanCode(for: $0.action) == code }?
            .action
    }

    func isRemapped(_ action: GameInputAction) -> Bool {
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
        if let map = mapMenuKeys[code] {
            return map
        }
        return world == .pause ? .menuCancel : nil
    }

    /// Binds `scanCode` to `action`. A key already used in the same context moves
    /// to the action's old key, so no action is left without one.
    @discardableResult
    mutating func rebind(
        _ action: GameInputAction,
        to scanCode: UInt32
    ) -> InputRebindResult {
        guard
            let slot = Self.slot(for: action), slot.remappable,
            !fixedKeys.contains(slot.key) else { return .notRemappable }
        if let button = InputCode.mouseButton(scanCode) {
            guard mouseKeys.contains(slot.key) else { return .notRemappable }
            guard InputCode.mouseButtons.contains(UInt32(button)) else { return .unknownKey }
        } else if DirectInputKeyCodes.macKeyCode(scanCode) == nil {
            return .unknownKey
        }
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

    mutating func reset() {
        overrides = [:]
        gamepadOverrides = [:]
    }

    /// Restores remaps saved by key, dropping any for an unknown event.
    public mutating func restore(_ saved: [String: Int]) {
        let known = Set(Self.slots.map(\.key))
        gamepadOverrides = Self.gamepadEntries(saved, known: known)
        overrides = saved.reduce(into: [:]) { result, pair in
            guard known.contains(pair.key), pair.value >= 0, Self.isKnown(UInt32(pair.value)) else {
                return
            }
            result[pair.key] = UInt32(pair.value)
        }
    }

    private static func isKnown(_ code: UInt32) -> Bool {
        if let button = InputCode.mouseButton(code) {
            return InputCode.mouseButtons.contains(UInt32(button))
        }
        return DirectInputKeyCodes.macKeyCode(code) != nil
    }

    /// From the vanilla file's mouse column, for when it cannot be read.
    static let vanillaMouseKeys: Set<String> = Set([
        "Forward", "Back", "Strafe Left", "Strafe Right", "Left Attack/Block",
        "Right Attack/Block", "Activate", "Ready Weapon", "Tween Menu", "Toggle POV", "Jump",
        "Sprint", "Shout", "Sneak", "Run", "Toggle Always Run", "Auto-Move", "Favorites",
        "Wait", "Journal", "Pause", "Quick Inventory", "Quick Magic", "Quick Stats", "Quick Map"
    ].map { "\(InputContext.gameplay.rawValue)|\($0)" })

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
    /// The `XButton` user event, such as the race menu's Done, sits in this context.
    static let itemMenusContext = "Item Menus"

    static let vanillaMenuReferences: [GameInputAction: [String]] = [
        .menuAccept: ["Activate"], .menuCancel: ["Tween Menu", "Pause"],
        .menuUp: ["Forward"], .menuDown: ["Back"], .menuLeft: ["Strafe Left"],
        .menuRight: ["Strafe Right"], .readyWeapon: ["Ready Weapon"], .jump: ["Jump"]
    ]

    /// The skills menu reads Jump for Make Legendary, but no menu event in the file names it.
    private static func menuReferences(in file: ControlMapFile) -> [GameInputAction: [String]]? {
        guard let menu = file.context(named: InputContext.menu.rawValue) else { return nil }
        var result: [GameInputAction: [String]] = [.jump: ["Jump"]]
        for (event, action) in menuEvents {
            result[action] = references(menu.event(named: event))
        }
        result[.readyWeapon] = file.context(named: itemMenusContext)
            .map { references($0.event(named: "XButton")) } ?? ["Ready Weapon"]
        return result
    }

    private static func mapMenuKeys(in file: ControlMapFile) -> [UInt32: GameInputAction]? {
        guard let map = file.contexts.firstIndex(where: { $0.name == mapMenuContext }) else {
            return nil
        }
        let codes = file.codes(of: "PlacePlayerMarker", in: map, device: .keyboard)
        return Dictionary(codes.map { ($0, GameInputAction.placeMarker) }) { first, _ in first }
    }

    private static func references(_ event: ControlMapEvent?) -> [String] {
        event?.keyboard.compactMap { input -> String? in
            if case let .reference(_, name) = input {
                return name
            }
            return nil
        } ?? []
    }
}
