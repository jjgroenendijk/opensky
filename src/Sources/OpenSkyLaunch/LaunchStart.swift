// Where a Play session starts: the normal start, a cell by name, a grid cell
// in a worldspace, or a map marker. The launcher remembers the last choice.

public import Foundation
public import OpenSkyGameData

nonisolated public enum LaunchStart: Equatable, Sendable {
    /// The title screen, as the original game starts.
    case normal
    /// A cell by editor ID, as the console's `coc` takes it.
    case cell(String)
    /// An exterior cell by its grid coordinates.
    case exterior(worldspace: String, x: Int32, y: Int32)
    /// A map marker: its worldspace, and its reference as a plugin name and an object ID.
    case marker(worldspace: String, plugin: String, objectID: UInt32)

    /// `normal`, `cell:WhiterunBanneredMare`, `exterior:Tamriel:6:-2`, or
    /// `marker:Tamriel:Skyrim.esm:01A2B3`.
    public var storedValue: String {
        switch self {
        case .normal: "normal"
        case let .cell(editorID): "cell:\(editorID)"
        case let .exterior(worldspace, x, y): "exterior:\(worldspace):\(x):\(y)"
        case let .marker(worldspace, plugin, objectID):
            "marker:\(worldspace):\(plugin):" + Self.hex(objectID)
        }
    }

    static func hex(_ objectID: UInt32) -> String {
        let digits = String(objectID, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    /// Nil for text this version cannot read, so a bad saved value starts normally.
    public init?(storedValue: String) {
        let parts = storedValue.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        switch (parts.first, parts.count) {
        case ("normal", 1):
            self = .normal
        case ("cell", 2):
            guard Self.isEditorID(parts[1]) else { return nil }
            self = .cell(parts[1])
        case ("exterior", 4):
            guard
                Self.isEditorID(parts[1]), let x = Self.coordinate(parts[2]),
                let y = Self.coordinate(parts[3])
            else { return nil }
            self = .exterior(worldspace: parts[1], x: x, y: y)
        case ("marker", 4):
            guard
                Self.isEditorID(parts[1]), !parts[2].isEmpty,
                let objectID = UInt32(parts[3], radix: 16), objectID <= 0xFFFFFF
            else { return nil }
            self = .marker(worldspace: parts[1], plugin: parts[2], objectID: objectID)
        default:
            return nil
        }
    }

    /// A grid bound wide enough for Tamriel, with room to spare.
    static let gridRange: ClosedRange<Int32> = -64 ... 64

    /// Editor IDs are letters, digits, and underscores.
    static func isEditorID(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
    }

    private static func coordinate(_ text: String) -> Int32? {
        Int32(text).flatMap { gridRange.contains($0) ? $0 : nil }
    }
}

nonisolated extension LaunchPreferences {
    public static let startKey = "OpenSkyLaunchStart"

    public static let startSetting = SettingKey(startKey, default: LaunchStart.normal.storedValue)

    public static func savedStart(
        userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> LaunchStart {
        LaunchStart(storedValue: SettingsStore(defaults: userDefaults).value(startSetting))
            ?? .normal
    }

    public static func remember(
        _ start: LaunchStart, userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        SettingsStore(defaults: userDefaults).set(start.storedValue, for: startSetting)
    }
}
