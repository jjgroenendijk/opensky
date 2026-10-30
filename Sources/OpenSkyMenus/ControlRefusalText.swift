// The HUD texts of a control a script or a beast form has locked, from the
// `sTweenDisabledMessage` and `sCharGenControlsDisabled` settings.

import OpenSkyGameData

/// The texts of a refused control.
nonisolated public enum ControlRefusalText: String, GameSettingTextKey {
    case menusDisabled = "sTweenDisabledMessage"
    case chargenControls = "sCharGenControlsDisabled"

    public var fallback: String {
        switch self {
        case .menusDisabled: "The character menus are not available now."
        case .chargenControls: "Your hands are bound."
        }
    }
}
