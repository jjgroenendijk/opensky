// Env-gated LAND sweep over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): walks the Tamriel
// worldspace, decodes every LAND record, and asserts the whole set parses with
// in-bounds quadrant/VTXT values. Skips automatically when OPENSKY_DATA_ROOT is
// unset/unresolvable (CI has no game data). Summary printed + written to logs/.

import Foundation
@testable import opensky
import Testing

struct LandRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryTamrielLand() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = (try? file.pluginHeader().isLocalized) ?? false

        let world = try #require(
            worldChildren(of: "Tamriel", in: file, localized: localized),
            "Tamriel worldspace not found"
        )
        let records = collectLandRecords(in: world)
        #expect(!records.isEmpty, "no LAND records under Tamriel")

        var minHeight = Float.greatestFiniteMagnitude
        var maxHeight = -Float.greatestFiniteMagnitude
        var layerHistogram: [Int: Int] = [:] // additional-layer count -> cells
        var maxVTXTPosition: UInt16 = 0
        var quadrants = Set<UInt8>()

        for record in records {
            let land = try Land(record: record)
            if let heights = land.heightField?.heights {
                for height in heights {
                    minHeight = min(minHeight, height)
                    maxHeight = max(maxHeight, height)
                }
            }
            layerHistogram[land.layers.count, default: 0] += 1
            for base in land.baseTextures {
                quadrants.insert(base.quadrant)
            }
            for layer in land.layers {
                quadrants.insert(layer.quadrant)
                for alpha in layer.alphas {
                    maxVTXTPosition = max(maxVTXTPosition, alpha.position)
                    #expect(alpha.position <= 288, "VTXT position \(alpha.position) out of range")
                }
            }
        }
        for quadrant in quadrants {
            #expect(quadrant <= 3, "quadrant \(quadrant) out of range")
        }

        let histogram = layerHistogram.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " ")
        let summary = """
        [INFO] Tamriel LAND sweep: \(records.count) records decoded, no throws
        [INFO] height range: \(minHeight) .. \(maxHeight) game units
        [INFO] additional-layer-count histogram (layers:cells): \(histogram)
        [INFO] max VTXT position: \(maxVTXTPosition) (bound 288)
        [INFO] quadrant values seen: \(quadrants.sorted())
        """
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// Verifies the spec claim that a cell's 33x33 grid overlaps its neighbors:
    /// row 32 of (x,y) equals row 0 of (x,y+1); col 32 of (x,y) equals col 0 of
    /// (x+1,y) (UESP LAND). Groundwork for cross-cell stitching (streaming, 3.2)
    /// — asserts the shared edges match on real Tamriel data, builds nothing.
    @Test(.enabled(if: Self.dataRoot != nil))
    func adjacentCellEdgesMatch() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let world = try #require(worldChildren(of: "Tamriel", in: file, localized: localized))

        let heights = landHeightsByGrid(in: world)
        // A handful of adjacent Whiterun-area pairs known to carry LAND.
        // `northward` true -> B is A's northern neighbor (x,y+1); else eastern.
        let pairs: [EdgePair] = [
            EdgePair(a: SIMD2(5, -3), b: SIMD2(5, -2), northward: true),
            EdgePair(a: SIMD2(6, -3), b: SIMD2(6, -2), northward: true),
            EdgePair(a: SIMD2(5, -3), b: SIMD2(6, -3), northward: false),
            EdgePair(a: SIMD2(5, -2), b: SIMD2(6, -2), northward: false)
        ]
        let dim = Land.dimension
        var checked = 0
        var mismatches = 0
        for pair in pairs {
            guard let a = heights[pair.a], let b = heights[pair.b] else { continue }
            checked += 1
            for index in 0 ..< dim {
                let (lhs, rhs): (Float, Float) = pair.northward
                    // Row 32 of A vs row 0 of B (columns aligned).
                    ? (a[32 * dim + index], b[0 * dim + index])
                    // Col 32 of A vs col 0 of B (rows aligned).
                    : (a[index * dim + 32], b[index * dim + 0])
                if lhs != rhs {
                    mismatches += 1
                }
            }
        }
        let finding = """
        [INFO] Tamriel edge-overlap probe: \(checked) adjacent pairs checked, \
        \(mismatches) mismatched edge vertices \
        (\(mismatches == 0 ? "edges MATCH" : "edges DIFFER"))
        """
        print(finding)
        try? finding.write(to: edgeLogURL, atomically: true, encoding: .utf8)
        #expect(checked > 0, "no adjacent LAND pairs found — install layout unexpected")
        #expect(mismatches == 0, "adjacent cell shared edges disagree")
    }

    /// Two adjacent exterior cells whose shared edge should match. `northward`
    /// selects which edge pair to compare (north vs east neighbor).
    private struct EdgePair {
        let a: SIMD2<Int32>
        let b: SIMD2<Int32>
        let northward: Bool
    }

    // MARK: - Walk helpers

    /// The world-children group for the WRLD whose editor ID matches, mirroring
    /// CellSceneBuilder's walk without reaching into its private methods.
    private func worldChildren(
        of editorID: String,
        in file: ESMFile,
        localized: Bool
    ) -> ESMGroup? {
        guard let top = file.topGroup(of: "WRLD"), let children = try? top.children() else {
            return nil
        }
        var matchedFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
                matchedFormID = world?.editorID == editorID ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                return group
            default:
                break
            }
        }
        return nil
    }

    /// Every LAND record anywhere under `group` (they live in cell
    /// temporary-children groups nested several levels down).
    private func collectLandRecords(in group: ESMGroup) -> [ESMRecord] {
        guard let children = try? group.children() else { return [] }
        var lands: [ESMRecord] = []
        for child in children {
            switch child {
            case let .record(record) where record.type == "LAND":
                lands.append(record)
            case let .group(sub):
                lands += collectLandRecords(in: sub)
            default:
                break
            }
        }
        return lands
    }

    /// Exterior-cell grid (x,y) -> its LAND height field, walking the WRLD tree
    /// like `CellSceneBuilder`: CELL record's XCLC grid paired with the LAND in
    /// the cell-children (type 6) temporary-children (type 9) group after it.
    private func landHeightsByGrid(in group: ESMGroup) -> [SIMD2<Int32>: [Float]] {
        var result: [SIMD2<Int32>: [Float]] = [:]
        collectHeights(in: group, into: &result)
        return result
    }

    private func collectHeights(in group: ESMGroup, into result: inout [SIMD2<Int32>: [Float]]) {
        guard let children = try? group.children() else { return }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: false),
                    let grid = cell.grid
                else { continue }
                let heights = landHeights(
                    following: index, in: children, cellFormID: record.formID
                )
                if let heights {
                    result[SIMD2(grid.x, grid.y)] = heights
                }
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                collectHeights(in: sub, into: &result)
            default:
                break
            }
        }
    }

    /// LAND height field inside the cell-children group following a CELL.
    private func landHeights(
        following index: Int,
        in children: [ESMGroup.Child],
        cellFormID: UInt32
    ) -> [Float]? {
        for case let .group(group) in children[(index + 1)...] {
            guard group.kind == .cellChildren, group.parentFormID == cellFormID else { continue }
            guard let inner = try? group.children() else { return nil }
            for case let .group(temporary) in inner {
                guard temporary.kind == .cellTemporaryChildren else { continue }
                guard let records = try? temporary.children() else { continue }
                for case let .record(record) in records where record.type == "LAND" {
                    if let land = try? Land(record: record) {
                        return land.heightField?.heights
                    }
                }
            }
        }
        return nil
    }

    /// logs/land-sweep.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        logsDirectory.appending(path: "land-sweep.log")
    }

    /// logs/land-edge-probe.log (gitignored) — the edge-overlap finding.
    private var edgeLogURL: URL {
        logsDirectory.appending(path: "land-edge-probe.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
