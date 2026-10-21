// Parser-eye info text for the preview detail pane — the same summaries the
// CLI nif/dds commands print, shaped as one string for the GUI and unit
// tests (docs/tools/preview-gui.md). A parse that fails here reproduces a
// renderer skip exactly (same code paths).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh

nonisolated public enum AssetInfoText: Sendable {
    /// NIF container stats + flattened engine-model view (drawable meshes,
    /// resolved materials).
    public static func nif(file: NIFFile) -> String {
        let header = file.header
        var lines = [
            "\(header.versionLine), user version \(header.userVersion), "
                + "BS stream \(header.bsStream.map { String($0.version) } ?? "-")"
        ]
        let counts = file.blockTypeCounts().sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        lines.append(
            "blocks: \(file.blocks.count) — "
                + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        )
        lines.append(contentsOf: modelLines(file: file))
        lines.append(contentsOf: decodedBlockLines(file: file))
        return lines.joined(separator: "\n")
    }

    /// Every block a whole-block decoder reads, with its decoded fields. Unknown
    /// types are listed in the block counts above and not here.
    private static func decodedBlockLines(file: NIFFile) -> [String] {
        var lines: [String] = []
        for (index, block) in file.blocks.enumerated() {
            do {
                guard let value = try NIFBlockDecoders.decode(block, header: file.header)
                else { continue }
                lines.append("block \(index) \(block.typeName):")
                lines += DecodedValueDump.lines(value) { $0.description }.map { "  " + $0 }
            } catch {
                lines
                    .append(
                        "[WARNING] block \(index) \(block.typeName): \(String(describing: error))"
                    )
            }
            guard lines.count < DecodedValueDump.lineCap else {
                lines.append("[INFO] decoded blocks cut at \(DecodedValueDump.lineCap) lines")
                break
            }
        }
        return lines.isEmpty ? [] : ["decoded blocks:"] + lines
    }

    private static func modelLines(file: NIFFile) -> [String] {
        let model: Model
        do {
            model = try file.model()
        } catch {
            return ["[WARNING] scene graph flatten failed: \(String(describing: error))"]
        }
        let vertexCount = model.meshes.reduce(0) { $0 + $1.positions.count }
        let triangleCount = model.meshes.reduce(0) { $0 + $1.indices.count / 3 }
        var lines = [
            "model: \(model.meshes.count) drawable meshes "
                + "(\(model.skippedShapeCount) skipped), \(vertexCount) vertices, "
                + "\(triangleCount) triangles"
        ]
        if let bounds = ModelBounds.containing(model: model) {
            lines.append(
                "bounds: min (\(bounds.min.x), \(bounds.min.y), \(bounds.min.z)) "
                    + "max (\(bounds.max.x), \(bounds.max.y), \(bounds.max.z))"
            )
        }
        for (index, material) in model.materials.enumerated() {
            lines.append(
                "material \(index): diffuse \(material.diffuseTexture ?? "-"), "
                    + "normal \(material.normalTexture ?? "-")"
                    + (material.alphaTestThreshold != nil ? ", alpha-test" : "")
                    + (material.doubleSided ? ", double-sided" : "")
            )
        }
        return lines
    }

    /// DDS header + mip chain.
    public static func dds(file: DDSFile, byteCount: Int) -> String {
        var lines = [
            "\(file.width)x\(file.height)" + (file.depth > 1 ? "x\(file.depth) volume" : "")
                + " \(file.format), "
                + "\(file.mipCount) mips, declares sRGB: \(file.declaresSRGB), "
                + "\(byteCount) bytes total"
        ]
        for level in 0 ..< file.mipCount {
            lines.append(
                "  mip \(level): \(file.width(level: level))x\(file.height(level: level))"
                    + (file.depth > 1 ? "x\(file.depth(level: level))" : "") + ", "
                    + "\(file.mipData(level: level).count) bytes"
            )
        }
        return lines.joined(separator: "\n")
    }
}
