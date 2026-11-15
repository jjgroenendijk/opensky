// The places a new game can start at, read from the active plugins: every named
// interior cell and every map marker. The launcher offers only the settlements;
// `openskycli places --all` shows the whole list.

import Foundation
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
    /// The name of a marker's top worldspace, such as "Skyrim" for a marker in Whiterun;
    /// an interior has none.
    public let worldspace: String?
    public let markerType: MapMarkerType?
    let searchKey: String

    public init(
        start: LaunchStart, name: String, detail: String, editorID: String? = nil,
        worldspace: String? = nil, markerType: MapMarkerType? = nil
    ) {
        self.start = start
        self.name = name
        self.detail = detail
        self.editorID = editorID
        self.worldspace = worldspace
        self.markerType = markerType
        searchKey = [name, editorID ?? "", detail].joined(separator: " ").lowercased()
    }

    /// The marker types of a place people live in. The names are xEdit's; the choice
    /// is OpenSky's (docs/engine/unverified-values.md).
    static let settlementTypes: Set = [
        "City", "Town", "Settlement", "Orc Stronghold", "Raven Rock", "Tel Mithryn",
        "Riften Capitol", "Windhelm Capitol", "Whiterun Capitol", "Solitude Capitol",
        "Markarth Capitol", "Winterhold Capitol", "Morthal Capitol", "Falkreath Capitol",
        "Dawnstar Capitol"
    ]

    public var isSettlement: Bool {
        markerType?.name.map(Self.settlementTypes.contains) ?? false
    }
}

/// The places of one worldspace, as the launcher's start menu shows them.
nonisolated public struct StartPlaceGroup: Equatable, Sendable {
    /// The worldspace name, or "Interior" for the interiors.
    public let title: String
    public let places: [StartPlace]
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

    /// The map markers of hold capitals, towns, villages, and orc strongholds.
    public var settlements: StartPlaceList {
        StartPlaceList(places: places.filter(\.isSettlement), weathers: weathers)
    }

    /// The places by worldspace; the worldspaces and the places in each are ordered by name.
    public var groups: [StartPlaceGroup] {
        Dictionary(grouping: places) { $0.worldspace ?? $0.detail }
            .map { StartPlaceGroup(title: $0.key, places: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
                    let editorID = cell.editorID, LaunchStart.isEditorID(editorID)
                else { continue }
                cells[plugin.formID(of: record).rawValue] = Interior(
                    editorID: editorID, name: cell.name
                )
            }
        }
    }

    private static func markers(in loadOrder: LoadOrderPlugins, text: Text) -> [StartPlace] {
        var skipped = SkippedRecords()
        var worlds: [ResolvedFormID: World] = [:]
        let records = loadOrder.decodeRecords(of: "WRLD", skipped: &skipped) {
            try Worldspace(record: $0, localized: $1)
        }
        for world in records {
            guard
                let editorID = world.editorID, LaunchStart.isEditorID(editorID),
                let id = loadOrder.space.resolve(world.formID)
            else { continue }
            worlds[id] = World(
                editorID: editorID, name: text(world.name, nil) ?? editorID,
                parent: world.parent.flatMap(loadOrder.space.resolve)
            )
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
                name: name, detail: world.name + type,
                worldspace: topName(of: entry.worldspace, in: worlds),
                markerType: entry.marker.type
            )
        }
    }

    private struct World {
        let editorID: String
        let name: String
        let parent: ResolvedFormID?
    }

    /// A city worldspace, such as Whiterun's, groups under its parent, such as Skyrim.
    private static func topName(
        of id: ResolvedFormID, in worlds: [ResolvedFormID: World]
    ) -> String? {
        var current = worlds[id]
        var steps = 0
        while let parent = current?.parent, let next = worlds[parent], steps < 8 {
            current = next
            steps += 1
        }
        return current?.name
    }

    private static func weatherNames(in loadOrder: LoadOrderPlugins) -> [String] {
        var skipped = SkippedRecords()
        let names: [String] = loadOrder.decodeRecords(of: "WTHR", skipped: &skipped) { record in
            ESMWalk.editorID(of: record)
        }
        return names.filter(LaunchStart.isEditorID)
    }
}
