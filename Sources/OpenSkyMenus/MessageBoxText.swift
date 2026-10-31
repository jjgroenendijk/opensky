// The button words of a yes or no question the engine asks itself.

import OpenSkyGameData

nonisolated public enum MessageBoxText: String, GameSettingTextKey {
    case yes = "sYesText"
    case no = "sNoText"

    public var fallback: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        }
    }
}
