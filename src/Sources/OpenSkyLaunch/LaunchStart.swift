// Where a Play session starts: the normal start, a cell by name, a grid cell
// in a worldspace, or a map marker. The launcher validates the choice and remembers it.

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
        case ("marker", 4):
            guard
                LaunchStartForm.isEditorID(parts[1]), !parts[2].isEmpty,
                let objectID = UInt32(parts[3], radix: 16), objectID <= 0xFFFFFF
            else { return nil }
            self = .marker(worldspace: parts[1], plugin: parts[2], objectID: objectID)
        default:
            return nil
        }
    }
}

/// What the launcher's start fields hold, before validation.
nonisolated public struct LaunchStartForm: Equatable, Sendable {
    public enum Kind: Int, CaseIterable, Sendable {
        case normal
        /// A place picked from the list the install gives.
        case place
        case cell
        case exterior
    }

    /// A grid bound wide enough for Tamriel, with room to spare.
    static let gridRange: ClosedRange<Int32> = -64 ... 64

    public var kind: Kind
    public var cell: String
    public var worldspace: String
    public var x: String
    public var y: String
    /// The place picked from the list; nil until one is picked.
    public var place: LaunchStart?

    public init(
        kind: Kind = .normal, cell: String = "", worldspace: String = "Tamriel",
        x: String = "", y: String = "", place: LaunchStart? = nil
    ) {
        self.kind = kind
        self.cell = cell
        self.worldspace = worldspace
        self.x = x
        self.y = y
        self.place = place
    }

    /// - Parameter fromList: the start was picked from the place list, so the form
    ///   shows the list and not the typed fields.
    public init(_ start: LaunchStart, fromList: Bool = false) {
        if fromList, start != .normal {
            self.init(kind: .place, place: start)
            return
        }
        switch start {
        case .normal:
            self.init()
        case let .cell(editorID):
            self.init(kind: .cell, cell: editorID)
        case let .exterior(worldspace, x, y):
            self.init(kind: .exterior, worldspace: worldspace, x: String(x), y: String(y))
        case .marker:
            self.init(kind: .place, place: start)
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
        case .place:
            guard let place else { return .failure(.noPlace) }
            return .success(place)
        }
    }

    static func isEditorID(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(isEditorIDScalar)
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
    case noPlace
    /// The saved place is not in the load order any more.
    case placeMissing(String)

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
        case .noPlace:
            "Choose a place from the list"
        case let .placeMissing(name):
            "\(name) is not in the load order any more; choose another place"
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
