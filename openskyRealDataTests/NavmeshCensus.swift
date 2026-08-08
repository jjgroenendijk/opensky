// Tally + report for the NAVM census probe (issue #199). Counts only —
// nothing game-derived leaves the run (openskyRealDataTests/AGENTS.md, Legal
// boundary).

import Foundation
@testable import opensky

/// Running totals over every NAVM decoded in the target area.
struct NavmeshCensus {
    var records = 0
    var vertices = 0
    var triangles = 0
    var edgeLinks = 0
    var doorLinks = 0
    /// Cover triangles: decoded, range-checked and dropped.
    var coverTriangles = 0
    /// Triangle indices across every navmesh-grid square: same treatment.
    var gridTriangleIndices = 0
    /// Navmeshes whose grid divisor is outside 0...12, so no grid follows.
    var gridlessMeshes = 0
    var interiorMeshes = 0
    var exteriorMeshes = 0
    /// NVNM version values seen; 12 is the only one vanilla writes.
    var versions: Set<UInt32> = []
    /// Edge-link type -> how many links carry it. An unnamed raw value is
    /// keyed by its number, which is how an undocumented type would surface.
    var edgeLinkTypes: [String: Int] = [:]
    /// Triangles carrying each named flag bit.
    var triangleFlags: [String: Int] = [:]
    /// Navmeshes whose NVNM parent disagrees with the CELL they were found
    /// under. Zero is the claim that xEdit's parent rule is the right one.
    var locationMismatches: [String] = []
    /// Navmeshes with no NVMI entry in NAVI.
    var missingFromIndex: [String] = []
    /// Navmeshes whose NVMI entry names a different location than NVNM does.
    var indexLocationMismatches: [String] = []
    var failures: [String] = []

    mutating func accumulate(_ navmesh: Navmesh) {
        let geometry = navmesh.geometry
        records += 1
        vertices += geometry.vertices.count
        triangles += geometry.triangles.count
        edgeLinks += geometry.edgeLinks.count
        doorLinks += geometry.doorLinks.count
        coverTriangles += geometry.coverTriangleCount
        gridTriangleIndices += geometry.gridTriangleIndexCount
        if geometry.gridDivisor > 12 {
            gridlessMeshes += 1
        }
        versions.insert(geometry.version)
        switch geometry.location {
        case .interior: interiorMeshes += 1
        case .exterior: exteriorMeshes += 1
        }
        for link in geometry.edgeLinks {
            let name = link.type.map(String.init(describing:)) ?? "raw \(link.rawType)"
            edgeLinkTypes[name, default: 0] += 1
        }
        for triangle in geometry.triangles {
            for named in Self.namedTriangleFlags where triangle.flags.contains(named.flag) {
                triangleFlags[named.name, default: 0] += 1
            }
        }
    }

    /// The flag bits xEdit names, in bit order.
    private static let namedTriangleFlags: [(name: String, flag: NavmeshGeometry.TriangleFlags)] = [
        ("edge01Link", .edge01Link),
        ("edge12Link", .edge12Link),
        ("edge20Link", .edge20Link),
        ("deleted", .deleted),
        ("noLargeCreatures", .noLargeCreatures),
        ("overlapping", .overlapping),
        ("preferred", .preferred),
        ("water", .water),
        ("door", .door),
        ("found", .found)
    ]
}

/// The NAVI half of the census: what the plugin-wide index carries.
struct NavmeshIndexCensus {
    var infos = 0
    var islands = 0
    var withEdgeLinks = 0
    var withDoors = 0
    var deleted = 0
    var malformedInfos = 0
    var precomputedPaths = 0
    var roadMarkers = 0
    var version: UInt32 = 0

    init(map: NavmeshInfoMap) {
        infos = map.infos.count
        islands = map.infos.count { $0.flags.contains(.isIsland) }
        withEdgeLinks = map.infos.count { !$0.edgeLinks.isEmpty }
        withDoors = map.infos.count { !$0.doors.isEmpty }
        deleted = map.deletedNavmeshes.count
        malformedInfos = map.malformedInfoCount
        precomputedPaths = map.precomputedPathCount
        roadMarkers = map.roadMarkerCount
        version = map.version
    }
}

enum NavmeshCensusReport {
    static func text(area: NavmeshCensus, index: NavmeshIndexCensus, cells: Int) -> String {
        """
        [INFO] Whiterun-area NAVM sweep: \(area.records) records decoded from \(cells) cells, \
        \(area.failures.count) failures
        [INFO] geometry: \(area.vertices) vertices, \(area.triangles) triangles, \
        \(area.edgeLinks) edge links, \(area.doorLinks) door links
        [INFO] location split: \(area.interiorMeshes) interior, \(area.exteriorMeshes) exterior; \
        NVNM versions seen: \(area.versions.sorted())
        [INFO] edge-link types (type:count): \(histogram(area.edgeLinkTypes))
        [INFO] triangle flags (flag:count): \(histogram(area.triangleFlags))
        [INFO] skipped subrecords, decoded then dropped: \(area.coverTriangles) cover \
        triangles, \(area.gridTriangleIndices) navmesh-grid triangle indices \
        (\(area.gridlessMeshes) meshes carry no grid)
        [INFO] parent-cell agreement: \(area.locationMismatches.count) NVNM/CELL mismatches, \
        \(area.indexLocationMismatches.count) NVNM/NVMI mismatches, \
        \(area.missingFromIndex.count) navmeshes absent from NAVI
        [INFO] NAVI index: version \(index.version), \(index.infos) NVMI entries \
        (\(index.malformedInfos) malformed), \(index.islands) islands, \
        \(index.withEdgeLinks) with edge links, \(index.withDoors) with doors, \
        \(index.deleted) NVSI deletions
        [INFO] NVPP skipped, tallied only: \(index.precomputedPaths) precomputed paths, \
        \(index.roadMarkers) road markers
        """
    }

    private static func histogram(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " ")
    }
}
