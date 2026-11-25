// The gamepad column of the bindings: the control map's buttons for each gameplay row,
// and the player's gamepad remaps (docs/formats/controlmap.md, "The Controls list").

import Foundation
public import OpenSkyMenusInterface

nonisolated extension InputBindings {
    /// A saved gamepad remap is stored under this prefix and the slot key.
    static let gamepadPrefix = "Gamepad|"

    /// The vanilla file's gamepad column, for when it cannot be read.
    static let vanillaGamepad: [String: [UInt32]] = [
        "Left Attack/Block": [0x0009], "Right Attack/Block": [0x000A], "Activate": [0x1000],
        "Ready Weapon": [0x4000], "Tween Menu": [0x2000], "Toggle POV": [0x0080],
        "Jump": [0x8000], "Sprint": [0x0100], "Shout": [0x0200], "Sneak": [0x0040],
        "Favorites": [0x0001, 0x0002], "Hotkey1": [0x0004], "Hotkey2": [0x0008],
        "Wait": [0x0020], "Journal": [0x0010]
    ].reduce(into: [:]) { result, pair in
        result["\(InputContext.gameplay.rawValue)|\(pair.key)"] = pair.value
    }

    /// The buttons that fire `action`: the player's remap, else the file's buttons.
    public func gamepadCodes(for action: GameInputAction) -> [UInt32] {
        guard let slot = Self.slot(for: action) else { return [] }
        return gamepadOverrides[slot.key].map { [$0] } ?? gamepadDefaults[slot.key] ?? []
    }

    /// The gameplay action a gamepad button fires.
    func action(forGamepadCode code: UInt32) -> GameInputAction? {
        Self.slots.first { $0.context == .gameplay && gamepadCodes(for: $0.action).contains(code) }?
            .action
    }

    /// Binds a gamepad button, swapping with the row that had it, as a key does.
    @discardableResult
    mutating func rebindGamepad(_ action: GameInputAction, to code: UInt32) -> InputRebindResult {
        guard let slot = Self.slot(for: action), gamepadKeys.contains(slot.key) else {
            return .notRemappable
        }
        guard GamepadButton(controlMapCode: code) != nil else { return .unknownKey }
        let old = gamepadCodes(for: action).first
        let holder = Self.slots.first {
            $0.action != action && $0.context == slot.context
                && gamepadCodes(for: $0.action).contains(code)
        }
        setGamepad(slot, to: code)
        guard let holder else { return .bound }
        if let old, gamepadKeys.contains(holder.key) {
            setGamepad(holder, to: old)
        }
        return .swapped(with: holder.action)
    }

    /// Every remap to store: the keys by slot, the gamepad buttons under their prefix.
    public var savedBindings: [String: Int] {
        var saved = overrides.mapValues(Int.init)
        for (key, code) in gamepadOverrides {
            saved[Self.gamepadPrefix + key] = Int(code)
        }
        return saved
    }

    static func gamepadEntries(_ saved: [String: Int], known: Set<String>) -> [String: UInt32] {
        saved.reduce(into: [:]) { result, pair in
            guard pair.key.hasPrefix(gamepadPrefix) else { return }
            let key = String(pair.key.dropFirst(gamepadPrefix.count))
            guard
                known.contains(key), pair.value >= 0,
                GamepadButton(controlMapCode: UInt32(pair.value)) != nil
            else { return }
            result[key] = UInt32(pair.value)
        }
    }

    private mutating func setGamepad(_ slot: InputBindingSlot, to code: UInt32) {
        gamepadOverrides[slot.key] = gamepadDefaults[slot.key] == [code] ? nil : code
    }
}
