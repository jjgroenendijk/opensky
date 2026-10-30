// The box the game shows when the gamepad in use disconnects, from the Update.esm
// settings `sGamepadDisconnectedTitle` and `sGamepadDisconnectedMessage`.

import OpenSkyGameData

nonisolated public enum GamepadNoticeText: String, GameSettingTextKey {
    case title = "sGamepadDisconnectedTitle"
    case message = "sGamepadDisconnectedMessage"
    case confirm = "sOk"

    public var fallback: String {
        switch self {
        case .title: "Gamepad disconnected"
        case .message: "Reconnect the gamepad, or continue with the keyboard and mouse."
        case .confirm: "OK"
        }
    }
}
