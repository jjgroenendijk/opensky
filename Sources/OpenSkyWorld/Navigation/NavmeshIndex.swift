// The plugin-wide NAVI lookup: which navmeshes belong to a location, and which
// ones a navmesh links to. NAVM geometry is decoded per cell by
// `CellSceneBuilder.collectNavmeshes`; this index works before a cell streams in.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OSLog

nonisolated public struct NavmeshIndex: Sendable {
    public static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Navmesh"
    )

    /// Every NVMI entry, by the NAVM FormID it describes.
    public let infos: [UInt32: NavmeshInfo]
    /// Navmeshes this plugin deletes from its masters; they have no `infos` entry.
    public let deletedNavmeshes: Set<UInt32>
    /// NAVI records that failed to decode.
    public private(set) var skippedRecords = SkippedRecords()
    /// An array, because island meshes share a square with the ground mesh.
    private let byLocation: [NavmeshLocation: [FormID]]

    public static let empty = NavmeshIndex(infos: [], deletedNavmeshes: [])

    public init(file: ESMFile) {
        var infos: [NavmeshInfo] = []
        var deleted: [FormID] = []
        var skipped = SkippedRecords()
        if let group = file.topGroup(of: "NAVI"), let children = try? group.children() {
            for case let .record(record) in children where record.type == "NAVI" {
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
    public init(infos: [NavmeshInfo], deletedNavmeshes: [FormID]) {
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

    public var isEmpty: Bool {
        infos.isEmpty
    }

    public var count: Int {
        infos.count
    }

    public func info(_ navmesh: FormID) -> NavmeshInfo? {
        infos[navmesh.rawValue]
    }

    /// The navmeshes authored at a location, in record order.
    public func navmeshes(at location: NavmeshLocation) -> [FormID] {
        byLocation[location] ?? []
    }

    /// Navmeshes across a shared edge. Empty for an unknown FormID.
    public func edgeLinks(from navmesh: FormID) -> [FormID] {
        info(navmesh)?.edgeLinks ?? []
    }

    /// Every location the index knows about. The order is unspecified.
    public var locations: [NavmeshLocation] {
        Array(byLocation.keys)
    }
}
