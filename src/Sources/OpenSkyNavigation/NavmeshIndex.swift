// The plugin-wide NAVI lookup: which navmeshes belong to a location, and which
// ones a navmesh links to. NAVM geometry is decoded per cell by
// `CellSceneBuilder.collectNavmeshes`; this index works before a cell streams in.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated struct NavmeshIndex: Sendable {
    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Navmesh"
    )

    /// Every NVMI entry, by the NAVM FormID it describes.
    let infos: [UInt32: NavmeshInfo]
    /// Navmeshes this plugin deletes from its masters; they have no `infos` entry.
    let deletedNavmeshes: Set<UInt32>
    /// NAVI records that failed to decode.
    private(set) var skippedRecords = SkippedRecords()
    /// An array, because island meshes share a square with the ground mesh.
    private let byLocation: [NavmeshLocation: [FormID]]

    static let empty = NavmeshIndex(infos: [], deletedNavmeshes: [])

    init(file: ESMFile) {
        var infos: [NavmeshInfo] = []
        var deleted: [FormID] = []
        var skipped = SkippedRecords()
        if let group = file.topGroup(of: "NAVI") {
            for case let .record(record) in skipped.children(of: group)
                where record.type == "NAVI"
            {
                guard !record.isDeleted else { continue }
                guard let map = skipped.decode(record, using: NavmeshInfoMap.init(record:)) else {
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
        skippedRecords = skipped
    }

    /// Test seam, and the shape the file initializer funnels into.
    init(infos: [NavmeshInfo], deletedNavmeshes: [FormID]) {
        self.infos = Dictionary(
            infos.map { ($0.navmesh.rawValue, $0) },
            // Only a broken mod names one NAVM twice; record order decides.
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

    /// Navmeshes across a shared edge. Empty for an unknown FormID.
    func edgeLinks(from navmesh: FormID) -> [FormID] {
        info(navmesh)?.edgeLinks ?? []
    }

    /// Every location the index knows about. The order is unspecified.
    var locations: [NavmeshLocation] {
        Array(byLocation.keys)
    }
}
