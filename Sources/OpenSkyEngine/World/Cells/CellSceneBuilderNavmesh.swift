// NAVM collection from a cell's children groups (issue #199).
//
// Navmeshes are stored beside the placements — a cell's temporary-children
// group holds them next to its REFRs — but they are not placements, so
// `collectTaggedReferences` skips them by type. This is the other half of that
// skip: the walk that picks NAVM out of the same group and decodes it.
//
// Decoded beside the rest of the cell's immutable geometry. That keeps NAVM
// I/O on the existing off-main build queue and gives the streamer the same
// scene-owned lifetime it already reconciles for collision and rigid bodies.

import Foundation
import OSLog

nonisolated extension CellSceneBuilder {
    /// Decoded NAVM records from the cell's persistent and temporary children
    /// groups. Deleted records place no surface and are skipped; a record that
    /// fails to decode is logged and skipped, so one bad navmesh does not cost
    /// the cell its others.
    ///
    /// Static because it reads nothing but the group handed to it; tests and
    /// probes can decode a synthetic cell without a mesh library or device.
    nonisolated static func collectNavmeshes(in cellChildren: ESMGroup?) -> [Navmesh] {
        guard let cellChildren, let children = try? cellChildren.children() else {
            if cellChildren != nil {
                logger.warning("malformed cell-children group skipped")
            }
            return []
        }
        var navmeshes: [Navmesh] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
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
