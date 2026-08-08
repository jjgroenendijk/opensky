// The plugin-wide navmesh lookup (issue #199): NAVI decoded once and turned
// into the two questions cross-cell pathing asks (16.2, issue #200) — which
// navmeshes belong to a cell, and which navmeshes a given one links to.
//
// The geometry itself is deliberately not here. A NAVM record lives in its
// cell's temporary-children group and is decoded when that cell is built
// (`CellSceneBuilder.collectNavmeshes`); this index only says which navmeshes
// exist and where, which is what a route leaving the current cell needs to
// know before that cell has ever been streamed in.
//
// Built once per plugin and read from the build queue like the other record
// indexes, so it is an immutable value rather than a cache — the same shape
// `MaterialTypeIndex` uses.

import OSLog

nonisolated struct NavmeshIndex: Sendable {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Navmesh"
    )

    /// Every NVMI entry, by the NAVM FormID it describes.
    let infos: [UInt32: NavmeshInfo]
    /// Navmeshes this plugin deletes from its masters. Kept separate from
    /// `infos` because a deleted navmesh has no entry to look up.
    let deletedNavmeshes: Set<UInt32>
    /// Location -> the navmeshes authored there. An exterior square usually
    /// holds one, but the array is the honest shape: nothing in the format
    /// forbids more, and island meshes share a square with the ground mesh.
    private let byLocation: [NavmeshLocation: [FormID]]

    static let empty = NavmeshIndex(infos: [], deletedNavmeshes: [])

    init(file: ESMFile) {
        var infos: [NavmeshInfo] = []
        var deleted: [FormID] = []
        if let group = file.topGroup(of: "NAVI"), let children = try? group.children() {
            for case let .record(record) in children where record.type == "NAVI" {
                guard !record.isDeleted else { continue }
                guard let map = try? NavmeshInfoMap(record: record) else {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed NAVI \(id, privacy: .public) skipped")
                    continue
                }
                infos += map.infos
                deleted += map.deletedNavmeshes
                if map.malformedInfoCount > 0 {
                    let count = map.malformedInfoCount
                    Self.logger.warning("\(count, privacy: .public) malformed NVMI entries skipped")
                }
            }
        }
        self.init(infos: infos, deletedNavmeshes: deleted)
    }

    /// Test seam, and the shape the file initializer funnels into.
    init(infos: [NavmeshInfo], deletedNavmeshes: [FormID]) {
        self.infos = Dictionary(
            infos.map { ($0.navmesh.rawValue, $0) },
            // Two NVMI entries cannot name the same NAVM in a well-formed
            // plugin; if a modded one does, record order decides.
            uniquingKeysWith: { first, _ in first }
        )
        self.deletedNavmeshes = Set(deletedNavmeshes.map(\.rawValue))
        byLocation = infos.reduce(into: [:]) { result, info in
            result[info.location, default: []].append(info.navmesh)
        }
    }

    var isEmpty: Bool {
        infos.isEmpty
    }

    var count: Int {
        infos.count
    }

    func info(_ navmesh: FormID) -> NavmeshInfo? {
        infos[navmesh.rawValue]
    }

    /// The navmeshes authored at a location, in record order.
    func navmeshes(at location: NavmeshLocation) -> [FormID] {
        byLocation[location] ?? []
    }

    /// Navmeshes reachable across a shared edge from `navmesh`. Empty for an
    /// unknown FormID, which is the same answer as "links nowhere" — a route
    /// that cannot name its start has nowhere to continue to either.
    func edgeLinks(from navmesh: FormID) -> [FormID] {
        info(navmesh)?.edgeLinks ?? []
    }

    /// Every location the index knows about. The order is unspecified.
    var locations: [NavmeshLocation] {
        Array(byLocation.keys)
    }
}
