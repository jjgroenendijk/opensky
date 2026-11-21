public import OpenSkyMenusInterface

// The HUD modes of `hudmenu.swf` that follow the player and the scripts. Each movie
// element names the modes it shows in; see docs/rendering/hud.md#hud-modes.

/// What the player is doing, as far as the HUD modes care.
nonisolated public struct HUDModeInputs: Equatable, Sendable {
    public var cart = false
    public var movementDisabled = false
    public var sneaking = false
    public var swimming = false
    public var ridingHorse = false
    public var weaponDrawn = false
    /// The player commands a follower.
    public var favor = false
    /// The open menus, bottom first.
    public var menus: [MenuIdentifier] = []
    /// A menu that pauses the world is open; dialogue hides under it.
    public var worldPaused = false

    public init(
        cart: Bool = false, movementDisabled: Bool = false, sneaking: Bool = false,
        swimming: Bool = false, ridingHorse: Bool = false, weaponDrawn: Bool = false,
        favor: Bool = false, menus: [MenuIdentifier] = [], worldPaused: Bool = false
    ) {
        self.cart = cart
        self.movementDisabled = movementDisabled
        self.sneaking = sneaking
        self.swimming = swimming
        self.ridingHorse = ridingHorse
        self.weaponDrawn = weaponDrawn
        self.favor = favor
        self.menus = menus
        self.worldPaused = worldPaused
    }
}

nonisolated public enum HUDModeRules {
    /// The mode stack, bottom first; the movie shows the top mode. A disabled
    /// movement sits above cart mode, as the Creation Kit wiki notes for `SetHudCartMode`.
    static func modes(_ inputs: HUDModeInputs) -> [HUDMode] {
        var modes: [HUDMode] = inputs.favor ? [.favor] : []
        if inputs.ridingHorse {
            modes.append(inputs.weaponDrawn ? .warHorse : .horse)
        } else if inputs.swimming {
            modes.append(.swimming)
        } else if inputs.sneaking {
            modes.append(.stealth)
        }
        if inputs.cart {
            modes.append(.cart)
        }
        if inputs.movementDisabled {
            modes.append(.movementDisabled)
        }
        for menu in inputs.menus {
            if menu == .dialogueMenu, inputs.worldPaused {
                continue
            }
            if let mode = menuModes[menu.name] {
                modes.append(mode)
            }
        }
        return modes
    }

    /// The mode each menu puts on while it is open (docs/rendering/hud.md#hud-under-menus).
    static let menuModes: [String: HUDMode] = [
        MenuIdentifier.dialogueMenu.name: .dialogue,
        MenuIdentifier.inventoryMenu.name: .inventory,
        MenuIdentifier.containerMenu.name: .inventory,
        MenuIdentifier.barterMenu.name: .inventory,
        "GiftMenu": .inventory, "MagicMenu": .inventory, "Crafting Menu": .inventory,
        "LockpickingMenu": .inventory,
        "Training Menu": .barter,
        "TweenMenu": .tween,
        MenuIdentifier.journalMenu.name: .journal,
        MenuIdentifier.systemMenu.name: .journal,
        "MapMenu": .worldMap,
        "Book Menu": .book,
        "Sleep/Wait Menu": .sleepWait
    ]

    /// Whether the top mode lets `clip` show.
    public static func shows(_ clip: HUDModeClip, under modes: [HUDMode]) -> Bool {
        modes.last?.hiddenClips.contains(clip) != true
    }
}
