// NAVM records from a cell's children groups. They sit beside the REFRs but are
// not placements, so this walk picks them out of the same groups. It runs with
// the rest of the cell geometry on the build queue.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellReferenceBuilder {
    /// The cell's NAVM records of every plugin in the load order.
    nonisolated public func collectNavmeshes(in cell: FoundCell) -> [Navmesh] {
        let base = Self.collectNavmeshes(in: cell.children)
        return owner.recordIndex.mergingLater(
            (base, owner.recordIndex.laterChildren(of: FormID(cell.formID), type: "NAVM")),
            formID: \.formID
        ) {
            try $0.record.decode(Navmesh.init(record:))
        } failed: { child in
            let id = child.record.formID.description
            CellSceneBuilder.logger.warning("malformed NAVM \(id, privacy: .public) skipped")
        }
    }

    /// Live NAVM records from the persistent and temporary children groups. A
    /// record that fails to decode is logged and skipped. Static, so a test can
    /// decode a synthetic cell without a mesh library or device.
    nonisolated public static func collectNavmeshes(in cellChildren: ESMGroup?) -> [Navmesh] {
        guard
            let cellChildren,
            let children = CellSceneBuilder.loggedChildren(cellChildren) else { return [] }
        var navmeshes: [Navmesh] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = CellSceneBuilder.loggedChildren(group)
            else { continue }
            for case let .record(record) in records where record.type == "NAVM" {
                guard !record.isDeleted else { continue }
                do {
                    try navmeshes.append(Navmesh(record: record))
                } catch {
                    let id = FormID(record.formID).description
                    CellSceneBuilder.logger
                        .warning("malformed NAVM \(id, privacy: .public) skipped")
                }
            }
        }
        return navmeshes
    }
}
