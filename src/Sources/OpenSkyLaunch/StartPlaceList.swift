// The places a new game can start at, read from the active plugins: every named
// interior cell and every map marker. The launcher and `openskycli places` show the
// list; nothing from it is stored outside the user's settings.

public import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public struct StartPlace: Equatable, Sendable {
    public let start: LaunchStart
    public let name: String
    /// "Interior", or the worldspace and the marker type, such as "Skyrim, Town".
    public let detail: String
    /// The cell's editor ID; a map marker has none.
    public let editorID: String?
    let searchKey: String

    public init(start: LaunchStart, name: String, detail: String, editorID: String? = nil) {
        self.start = start
        self.name = name
        self.detail = detail
        self.editorID = editorID
        searchKey = [name, editorID ?? "", detail].joined(separator: " ").lowercased()
    }
}

nonisolated public struct StartPlaceList: Sendable {
    /// Resolves a name; the plugin is given when the text was read outside a decode scope.
    public typealias Text = (LString?, String?) -> String?

    /// Ordered by name.
    public let places: [StartPlace]
    /// The editor IDs of the weather records, ordered by name.
    public let weathers: [String]
    private let starts: Set<String>

    public static let empty = StartPlaceList(places: [], weathers: [])

    public init(places: [StartPlace], weathers: [String]) {
        self.places = places.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.weathers = weathers.sorted {
            $0.caseInsensitiveCompare($1) == .orderedAscending
        }
        starts = Set(places.map(\.start.storedValue))
    }

    public init(loadOrder: LoadOrderPlugins, text: Text) {
        self.init(
            places: Self.interiors(in: loadOrder, text: text)
                + Self.markers(in: loadOrder, text: text),
            weathers: Self.weatherNames(in: loadOrder)
        )
    }

    /// Reads the active plugins and their string tables. Throws when `Skyrim.esm`
    /// cannot be read.
    public static func load(root: GameDataRoot) throws -> StartPlaceList {
        let loadOrder = try ActiveLoadOrder.open(root: root)
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root),
            pluginName: ActiveLoadOrder.baseFileName,
            language: LocalizationLanguageSettings.load(root: root).language
        )
        return StartPlaceList(loadOrder: loadOrder.plugins) { text, plugin in
            (plugin.map { strings.scoped(to: $0) } ?? strings).resolve(text)
        }
    }

    public func contains(_ start: LaunchStart) -> Bool {
        starts.contains(start.storedValue)
    }

    public func place(for start: LaunchStart) -> StartPlace? {
        places.first { $0.start == start }
    }

    /// The places that hold every word of `query`, in any case. A name that begins
    /// with the query comes first. An empty query gives every place.
    public func search(_ query: String) -> [StartPlace] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return places }
        let whole = words.joined(separator: " ")
        let matches = places.filter { place in
            words.allSatisfy { place.searchKey.contains($0) }
        }
        return matches.filter { $0.name.lowercased().hasPrefix(whole) }
            + matches.filter { !$0.name.lowercased().hasPrefix(whole) }
    }
}

// MARK: - Reading the plugins

nonisolated extension StartPlaceList {
    private struct Interior {
        let editorID: String
        let name: LString?
    }

    /// A later plugin's copy of a cell wins, as in the game.
    private static func interiors(in loadOrder: LoadOrderPlugins, text: Text) -> [StartPlace] {
        var cells: [UInt32: Interior] = [:]
        for plugin in loadOrder.plugins {
            guard let top = plugin.file.topGroup(of: "CELL") else { continue }
            plugin.decode { collectInteriors(in: top, plugin: plugin, into: &cells) }
        }
        return cells.values.compactMap { cell in
            guard let name = text(cell.name, nil), !name.isEmpty else { return nil }
            return StartPlace(
                start: .cell(cell.editorID), name: name, detail: "Interior",
                editorID: cell.editorID
            )
        }
    }

    private static func collectInteriors(
        in group: ESMGroup, plugin: LoadOrderPlugin, into cells: inout [UInt32: Interior]
    ) {
        guard let children = attempt({ try group.children() }) else { return }
        for child in children {
            switch child {
            case let .group(inner):
                // The other groups under a cell hold its references.
                guard inner.kind == .interiorCellBlock || inner.kind == .interiorCellSubBlock
                else { continue }
                collectInteriors(in: inner, plugin: plugin, into: &cells)
            case let .record(record):
                guard
                    record.type == "CELL", !record.isDeleted,
                    let cell = attempt({ try Cell(record: record, localized: plugin.localized) }),
                    let editorID = cell.editorID, LaunchStartForm.isEditorID(editorID)
                else { continue }
                cells[plugin.formID(of: record).rawValue] = Interior(
                    editorID: editorID, name: cell.name
                )
            }
        }
    }

    private static func markers(in loadOrder: LoadOrderPlugins, text: Text) -> [StartPlace] {
        var skipped = SkippedRecords()
        var worlds: [ResolvedFormID: (editorID: String, name: String)] = [:]
        let records = loadOrder.decodeRecords(of: "WRLD", skipped: &skipped) {
            try Worldspace(record: $0, localized: $1)
        }
        for world in records {
            guard
                let editorID = world.editorID, LaunchStartForm.isEditorID(editorID),
                let id = loadOrder.space.resolve(world.formID)
            else { continue }
            worlds[id] = (editorID, text(world.name, nil) ?? editorID)
        }
        return MapMarkerIndex(plugins: loadOrder.files).all.compactMap { entry in
            guard
                let world = worlds[entry.worldspace],
                let name = text(entry.name, entry.sourcePlugin), !name.isEmpty
            else { return nil }
            let type = entry.marker.type?.name.map { ", \($0)" } ?? ""
            return StartPlace(
                start: .marker(
                    worldspace: world.editorID, plugin: entry.reference.plugin,
                    objectID: entry.reference.objectID
                ),
                name: name, detail: world.name + type
            )
        }
    }

    private static func weatherNames(in loadOrder: LoadOrderPlugins) -> [String] {
        var skipped = SkippedRecords()
        let names: [String] = loadOrder.decodeRecords(of: "WTHR", skipped: &skipped) { record in
            ESMWalk.editorID(of: record)
        }
        return names.filter(LaunchStartForm.isEditorID)
    }
}

// MARK: - The places used last

nonisolated public struct LaunchRecentPlace: Equatable, Sendable {
    public let start: LaunchStart
    public let name: String

    public init(start: LaunchStart, name: String) {
        self.start = start
        self.name = name
    }
}

nonisolated extension LaunchPreferences {
    public static let recentPlacesSetting = SettingKey("OpenSkyLaunchRecentPlaces", default: "")
    public static let recentPlaceLimit = 8

    /// Newest first. One place per line: the stored start, a tab, and the name.
    public static func savedRecentPlaces(
        userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) -> [LaunchRecentPlace] {
        SettingsStore(defaults: userDefaults).value(recentPlacesSetting)
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2, let start = LaunchStart(storedValue: parts[0]) else {
                    return nil
                }
                return LaunchRecentPlace(start: start, name: parts[1])
            }
    }

    /// Puts `place` first and drops the oldest past the limit.
    public static func rememberRecent(
        _ place: LaunchRecentPlace,
        userDefaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        let others = savedRecentPlaces(userDefaults: userDefaults).filter {
            $0.start != place.start
        }
        let lines = ([place] + others).prefix(recentPlaceLimit).map { recent in
            let name = recent.name.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            return "\(recent.start.storedValue)\t\(name)"
        }
        SettingsStore(defaults: userDefaults)
            .set(lines.joined(separator: "\n"), for: recentPlacesSetting)
    }
}
