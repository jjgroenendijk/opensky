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

    public init(
        cart: Bool = false, movementDisabled: Bool = false, sneaking: Bool = false,
        swimming: Bool = false, ridingHorse: Bool = false, weaponDrawn: Bool = false
    ) {
        self.cart = cart
        self.movementDisabled = movementDisabled
        self.sneaking = sneaking
        self.swimming = swimming
        self.ridingHorse = ridingHorse
        self.weaponDrawn = weaponDrawn
    }
}

nonisolated public enum HUDModeRules {
    /// The mode stack, bottom first; the movie shows the top mode. A disabled
    /// movement sits above cart mode, as the Creation Kit wiki notes for `SetHudCartMode`.
    public static func modes(_ inputs: HUDModeInputs) -> [HUDMode] {
        var modes: [HUDMode] = []
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
        return modes
    }

    /// Whether the top mode lets `clip` show.
    public static func shows(_ clip: HUDModeClip, under modes: [HUDMode]) -> Bool {
        modes.last?.hiddenClips.contains(clip) != true
    }
}
