// What the rule sweep reads from every plugin in one walk: each record's type, each placed
// reference with its cell, and the cells that hold a navmesh (docs/tools/headless-sweeps.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

struct SweepRuleData {
    struct Placed {
        let base: UInt32
        let cell: UInt32?
        let world: UInt32?
        let position: SIMD3<Float>
        let isActor: Bool
        /// The door this load door leads to.
        let destination: UInt32?
    }

    struct Grid: Hashable {
        let world: UInt32, x: Int32, y: Int32
    }

    /// Load-order FormID to record type, for every record that is not deleted.
    var types: [UInt32: FourCC] = [:]
    var editorIDs: [UInt32: String] = [:]
    var placed: [UInt32: Placed] = [:]
    var navmeshCells: Set<UInt32> = []
    var interiorCells: Set<UInt32> = []
    var exteriorCells: [Grid: UInt32] = [:]

    init(plugins: LoadOrderPlugins) {
        for plugin in plugins.plugins {
            var walk = Walk(plugin: plugin)
            for group in plugin.file.topGroups {
                walk.visit(group, into: &self)
            }
        }
    }

    func name(_ id: UInt32) -> String {
        editorIDs[id] ?? Self.hex(id)
    }

    static func hex(_ id: UInt32) -> String {
        let digits = String(id, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }

    /// The cell a placed reference stands in: its own, or for a reference in a world's
    /// persistent cell, the exterior cell under it.
    func standingCell(_ reference: Placed) -> UInt32? {
        guard let cell = reference.cell else { return nil }
        guard let world = reference.world, !interiorCells.contains(cell) else { return cell }
        let size: Float = 4096
        let grid = Grid(
            world: world,
            x: Int32((reference.position.x / size).rounded(.down)),
            y: Int32((reference.position.y / size).rounded(.down))
        )
        return exteriorCells[grid] ?? cell
    }

    private struct Walk {
        let plugin: LoadOrderPlugin
        var world: UInt32?
        var cell: UInt32?

        func id(_ raw: UInt32) -> UInt32 {
            plugin.translation(FormID(stored: raw)).rawValue
        }

        mutating func visit(_ group: ESMGroup, into data: inout SweepRuleData) {
            let saved = (world, cell)
            defer { (world, cell) = saved }
            switch group.kind {
            case .worldChildren:
                world = group.parentFormID.map(id)
            case .cellChildren, .cellPersistentChildren, .cellTemporaryChildren:
                cell = group.parentFormID.map(id)
            case .interiorCellBlock:
                world = nil
            default:
                break
            }
            guard let children = attempt({ try group.children() }) else { return }
            for child in children {
                switch child {
                case let .record(record):
                    note(record, in: group, into: &data)
                case let .group(sub):
                    visit(sub, into: &data)
                }
            }
        }

        private func note(_ record: ESMRecord, in group: ESMGroup, into data: inout SweepRuleData) {
            let formID = plugin.formID(of: record).rawValue
            guard !record.isDeleted else {
                data.types[formID] = nil
                return
            }
            data.types[formID] = record.type
            switch record.type {
            case "CELL":
                noteCell(record, formID: formID, in: group, into: &data)
            case "NAVM":
                if let cell {
                    data.navmeshCells.insert(cell)
                }
            case "REFR":
                guard
                    let reference = attempt({
                        try plugin.decode { try PlacedReference(record: record) }
                    })
                else { return }
                data.placed[formID] = Placed(
                    base: reference.base.rawValue, cell: cell, world: world,
                    position: reference.placement.position, isActor: false,
                    destination: reference.teleportDestination?.door.rawValue
                )
            case "ACHR":
                guard let actor = attempt({ try plugin.decode { try PlacedActor(record: record) } })
                else { return }
                data.placed[formID] = Placed(
                    base: actor.base.rawValue, cell: cell, world: world,
                    position: .zero, isActor: true, destination: nil
                )
            case "NPC_", "LVLI", "LVLN", "LVSP", "DIAL":
                data.editorIDs[formID] = ESMWalk.editorID(of: record)
            default:
                break
            }
        }

        private func noteCell(
            _ record: ESMRecord, formID: UInt32, in group: ESMGroup, into data: inout SweepRuleData
        ) {
            guard
                let decoded = attempt({
                    try plugin.decode { try Cell(record: record, localized: plugin.localized) }
                })
            else { return }
            data.editorIDs[formID] = decoded.editorID
            if decoded.isInterior {
                data.interiorCells.insert(formID)
            } else if group.kind == .exteriorCellSubBlock, let world, let grid = decoded.grid {
                data.exteriorCells[Grid(world: world, x: grid.x, y: grid.y)] = formID
            }
        }
    }
}
