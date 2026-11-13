// The button words of a yes or no question the engine asks itself.

public import OpenSkyGameData

nonisolated public enum MessageBoxText: String, GameSettingTextKey {
    case yes = "sYesText"
    case no = "sNoText"
    case ok = "sOk"

    public var fallback: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .ok: "Ok"
        }
    }
}
