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

    /// logs/land-sweep.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
            .appending(path: "land-sweep.log")
    }
}
