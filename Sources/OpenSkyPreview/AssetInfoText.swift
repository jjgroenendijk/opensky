// Parser-eye info text for the preview detail pane — the same summaries the
// CLI nif/dds commands print, shaped as one string for the GUI and unit
// tests (docs/tools/preview-gui.md). A parse that fails here reproduces a
// renderer skip exactly (same code paths).

import Foundation
import OpenSkyFormatsMesh

nonisolated public enum AssetInfoText: Sendable {
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
