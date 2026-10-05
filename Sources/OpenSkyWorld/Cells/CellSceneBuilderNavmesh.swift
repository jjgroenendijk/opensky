// NAVM records from a cell's children groups. They sit beside the REFRs but are
// not placements, so this walk picks them out of the same groups. It runs with
// the rest of the cell geometry on the build queue.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellSceneBuilder {
    /// Live NAVM records from the persistent and temporary children groups. A
    /// record that fails to decode is logged and skipped. Static, so a test can
    /// decode a synthetic cell without a mesh library or device.
    nonisolated public static func collectNavmeshes(in cellChildren: ESMGroup?) -> [Navmesh] {
        guard let cellChildren, let children = loggedChildren(cellChildren) else { return [] }
        var navmeshes: [Navmesh] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = Self.loggedChildren(group)
            else { continue }
            for case let .record(record) in records where record.type == "NAVM" {
                guard !record.isDeleted else { continue }
                do {
                    try navmeshes.append(Navmesh(record: record))
                } catch {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed NAVM \(id, privacy: .public) skipped")
                }
            }
        }
        return navmeshes
    }
}
