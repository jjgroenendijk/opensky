// Where a Play session starts: the normal start, a cell by name, or a grid cell
// in a worldspace. The launcher validates the choice and remembers it.

import Foundation
import OpenSkyGameData

nonisolated public enum LaunchStart: Equatable, Sendable {
    /// The title screen, as the original game starts.
    case normal
    /// A cell by editor ID, as the console's `coc` takes it.
    case cell(String)
    /// An exterior cell by its grid coordinates.
    case exterior(worldspace: String, x: Int32, y: Int32)

    /// `normal`, `cell:WhiterunBanneredMare`, or `exterior:Tamriel:6:-2`.
    public var storedValue: String {
        switch self {
        case .normal: "normal"
        case let .cell(editorID): "cell:\(editorID)"
        case let .exterior(worldspace, x, y): "exterior:\(worldspace):\(x):\(y)"
        }
    }

    /// Nil for text this version cannot read, so a bad saved value starts normally.
    public init?(storedValue: String) {
        let parts = storedValue.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        switch (parts.first, parts.count) {
        case ("normal", 1):
            self = .normal
        case ("cell", 2):
            guard case let .success(start) = LaunchStartForm(kind: .cell, cell: parts[1]).validate()
            else { return nil }
            self = start
        case ("exterior", 4):
            let form = LaunchStartForm(
                kind: .exterior,
                worldspace: parts[1],
                x: parts[2],
                y: parts[3]
            )
            guard case let .success(start) = form.validate() else { return nil }
            self = start
        default:
            return nil
        }
    }
}

/// What the launcher's start fields hold, before validation.
nonisolated public struct LaunchStartForm: Equatable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case normal
        case cell
        case exterior
    }

    /// A grid bound wide enough for Tamriel, with room to spare.
    public static let gridRange: ClosedRange<Int32> = -64 ... 64

    public var kind: Kind
    public var cell: String
    public var worldspace: String
    public var x: String
    public var y: String

    public init(
        kind: Kind = .normal, cell: String = "", worldspace: String = "Tamriel",
        x: String = "", y: String = ""
    ) {
        self.kind = kind
        self.cell = cell
        self.worldspace = worldspace
        self.x = x
        self.y = y
    }

    public init(_ start: LaunchStart) {
        switch start {
        case .normal:
            self.init()
        case let .cell(editorID):
            self.init(kind: .cell, cell: editorID)
        case let .exterior(worldspace, x, y):
            self.init(kind: .exterior, worldspace: worldspace, x: String(x), y: String(y))
        }
    }

    /// The start, or the one-line reason it cannot be used.
    public func validate() -> Result<LaunchStart, LaunchStartProblem> {
        switch kind {
        case .normal:
            return .success(.normal)
        case .cell:
            let name = cell.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(.emptyCell) }
            guard name.unicodeScalars.allSatisfy(Self.isEditorIDScalar) else {
                return .failure(.badCellName)
            }
            return .success(.cell(name))
        case .exterior:
            let name = worldspace.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(.emptyWorldspace) }
            guard name.unicodeScalars.allSatisfy(Self.isEditorIDScalar) else {
                return .failure(.badWorldspaceName)
            }
            guard let gridX = coordinate(x) else { return .failure(.badCoordinate("X")) }
            guard let gridY = coordinate(y) else { return .failure(.badCoordinate("Y")) }
            return .success(.exterior(worldspace: name, x: gridX, y: gridY))
        }
    }

    private func coordinate(_ text: String) -> Int32? {
        Int32(text.trimmingCharacters(in: .whitespaces)).flatMap {
            Self.gridRange.contains($0) ? $0 : nil
        }
    }

    /// Editor IDs are letters, digits, and underscores.
    private static func isEditorIDScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
    }
}

nonisolated public enum LaunchStartProblem: Error, Equatable, Sendable {
    case emptyCell
    case badCellName
    case emptyWorldspace
    case badWorldspaceName
    case badCoordinate(String)

    public var reason: String {
        switch self {
        case .emptyCell:
            "Enter the editor ID of a cell, such as WhiterunBanneredMare"
        case .badCellName:
            "A cell editor ID has only letters, digits, and underscores"
        case .emptyWorldspace:
            "Enter the editor ID of a worldspace, such as DLC2SolstheimWorld"
        case .badWorldspaceName:
            "A worldspace editor ID has only letters, digits, and underscores"
        case let .badCoordinate(axis):
            "\(axis) must be a whole number from \(LaunchStartForm.gridRange.lowerBound) "
                + "to \(LaunchStartForm.gridRange.upperBound)"
        }
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
