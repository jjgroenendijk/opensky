// FormID lookup over a whole load order, numbered as the game numbers forms at
// runtime. The last plugin that holds a record wins, and a later plugin can add
// references to a cell another plugin defines. Rules: docs/formats/formid.md.

import Foundation
import OpenSkyFormatsCore

/// A record stored under a cell, such as a REFR, ACHR, NAVM, or PHZD, and the
/// children group it came from.
nonisolated public struct CellChildRecord: Sendable {
    public let record: LoadOrderRecord
    public let isPersistent: Bool
}

/// A CELL record a plugin stores in a worldspace. The persistent one sits right
/// in the world children group; the others sit in exterior cell blocks.
nonisolated public struct WorldCellRecord: Sendable {
    public let record: LoadOrderRecord
    public let isPersistent: Bool
}

nonisolated public struct LoadOrderRecordIndex: Sendable {
    /// What one later plugin stores under cells and worldspaces.
    private struct Placed: Sendable {
        /// Keyed by the load-order FormID of the owning CELL.
        var cellChildren: [UInt32: [CellChildRecord]] = [:]
        /// Keyed by the load-order FormID of the owning WRLD.
        var worldCells: [UInt32: [WorldCellRecord]] = [:]
    }

    private struct Source: Sendable {
        let plugin: LoadOrderPlugin
        let index: ESMFormIDIndex
        let placed: Placed
    }

    public let loadOrder: LoadOrderPlugins
    private let sources: [Source]

    /// The FormID space every lookup takes and returns.
    public var space: FormIDResolver {
        loadOrder.space
    }

    /// Lowest priority first.
    public var plugins: [LoadOrderPlugin] {
        loadOrder.plugins
    }

    /// The first plugin's cells are read through its own groups, so only the later
    /// plugins get a children table.
    public init(plugins: [(name: String, file: ESMFile)], space: FormIDResolver? = nil) {
        self.init(LoadOrderPlugins(plugins, space: space))
    }

    public init(_ loadOrder: LoadOrderPlugins) {
        self.loadOrder = loadOrder
        sources = loadOrder.plugins.map { plugin in
            Source(
                plugin: plugin,
                index: ESMFormIDIndex(file: plugin.file),
                placed: plugin.position == 0 ? Placed() : Self.placed(in: plugin)
            )
        }
    }

    /// The winning record: the one in the last plugin that holds `formID`. A
    /// deleted record still wins, so the caller decides what deletion means.
    public func record(withFormID formID: FormID) -> LoadOrderRecord? {
        winner(of: formID).map(\.record)
    }

    /// The load-order FormID of the CELL that holds the winning record.
    public func cellFormID(containing formID: FormID) -> FormID? {
        guard
            let found = winner(of: formID),
            let cell = found.source.index.cellFormID(containing: found.local.rawValue)
        else { return nil }
        return found.source.plugin.translation(FormID(stored: cell))
    }

    /// The records the plugins after the first store under `cell`, lowest
    /// priority first. A later record with the same FormID overrides.
    public func laterChildren(ofCell cell: FormID) -> [CellChildRecord] {
        sources.flatMap { $0.placed.cellChildren[cell.rawValue] ?? [] }
    }

    /// The CELL records the plugins after the first store in worldspace `world`,
    /// lowest priority first.
    public func laterCells(ofWorld world: FormID) -> [WorldCellRecord] {
        sources.flatMap { $0.placed.worldCells[world.rawValue] ?? [] }
    }

    private struct Winner {
        let record: LoadOrderRecord
        let source: Source
        let local: FormID
    }

    private func winner(of formID: FormID) -> Winner? {
        guard let resolved = space.resolve(formID) else { return nil }
        for source in sources.reversed() {
            guard
                let local = source.plugin.translation.source.localFormID(of: resolved),
                let record = source.index.record(withFormID: local.rawValue)
            else { continue }
            let found = LoadOrderRecord(record: record, plugin: source.plugin)
            return Winner(record: found, source: source, local: local)
        }
        return nil
    }

    private static func placed(in plugin: LoadOrderPlugin) -> Placed {
        var placed = Placed()
        for type: FourCC in ["CELL", "WRLD"] {
            guard let top = plugin.file.topGroup(of: type) else { continue }
            collect(top, world: nil, plugin: plugin, into: &placed)
        }
        return placed
    }

    /// A malformed group is skipped, as in `ESMWalk`. `world` is the load-order
    /// FormID of the worldspace the walk is in, nil for interior cells.
    private static func collect(
        _ group: ESMGroup,
        world: UInt32?,
        plugin: LoadOrderPlugin,
        into placed: inout Placed
    ) {
        guard let items = try? group.children() else { return }
        let isPersistent = group.kind == .cellPersistentChildren
        let ownsRecords = isPersistent || group.kind == .cellTemporaryChildren
        let world = group.kind == .worldChildren
            ? plugin.translation(FormID(stored: group.header.label)).rawValue : world
        for item in items {
            switch item {
            case let .record(record) where ownsRecords:
                let cell = plugin.translation(FormID(stored: group.header.label)).rawValue
                placed.cellChildren[cell, default: []].append(CellChildRecord(
                    record: LoadOrderRecord(record: record, plugin: plugin),
                    isPersistent: isPersistent
                ))
            case let .record(record) where record.type == "CELL":
                guard let world else { continue }
                placed.worldCells[world, default: []].append(WorldCellRecord(
                    record: LoadOrderRecord(record: record, plugin: plugin),
                    isPersistent: group.kind == .worldChildren
                ))
            case let .group(nested):
                collect(nested, world: world, plugin: plugin, into: &placed)
            case .record:
                continue
            }
        }
    }
}
