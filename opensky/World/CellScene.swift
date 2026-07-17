// Cell scene build output (todo 2.7 scene build): the drawable RenderScene
// plus what the app layer needs around it — a load summary (one-line report,
// AGENTS.md robustness rule) and a world AABB for camera placement.

import Foundation
import simd

/// One built exterior cell, ready to render.
nonisolated struct CellScene {
    let renderScene: RenderScene
    let summary: CellLoadSummary
    /// World-space AABB over every drawn instance — nil when nothing drew.
    /// Downstream camera placement frames this box.
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
}

/// Load accounting for one cell build. Per-ref failures never abort the build
/// (AGENTS.md mod-quirk rule) — each lands in a skip bucket instead. Skip
/// taxonomy: docs/engine/cell-scene.md.
nonisolated struct CellLoadSummary: Equatable {
    /// Cell editor ID when present, else "cell <FormID>".
    let cellName: String
    let gridX: Int32
    let gridY: Int32
    /// Non-deleted REFR records seen in the cell's persistent + temporary
    /// children groups.
    let totalRefCount: Int
    let drawnRefCount: Int
    /// REFR whose base FormID resolves to no STAT record (other base types —
    /// ACTI, TREE, ... — are out of 2.7 scope).
    let nonSTATSkipCount: Int
    /// Base STAT carries no MODL — editor marker, nothing to draw.
    let markerSkipCount: Int
    /// Mesh load failed: missing file, parse error, or empty model.
    let modelFailureSkipCount: Int
    /// The REFR record itself failed to decode.
    let malformedRefSkipCount: Int
    /// Distinct models loaded (MeshLibrary.loadedCount).
    let modelCount: Int
    /// Distinct texture paths loaded / unresolved (TextureLibrary counters).
    let textureCount: Int
    let missingTextureCount: Int

    var skippedRefCount: Int {
        nonSTATSkipCount + markerSkipCount + modelFailureSkipCount + malformedRefSkipCount
    }

    /// One-line load report (AGENTS.md bracket-tag style), e.g.
    /// "[INFO] WhiterunExterior06 (6,-2): 16 refs, 15 drawn, 1 skipped
    /// (1 non-STAT), 8 models, 24 textures (0 missing)". The parenthetical
    /// lists only non-zero skip reasons and disappears when nothing skipped.
    var summaryLine: String {
        var reasons: [String] = []
        if nonSTATSkipCount > 0 { reasons.append("\(nonSTATSkipCount) non-STAT") }
        if markerSkipCount > 0 { reasons.append("\(markerSkipCount) marker") }
        if modelFailureSkipCount > 0 { reasons.append("\(modelFailureSkipCount) load-failed") }
        if malformedRefSkipCount > 0 { reasons.append("\(malformedRefSkipCount) malformed") }
        let skipped = reasons.isEmpty
            ? "\(skippedRefCount) skipped"
            : "\(skippedRefCount) skipped (\(reasons.joined(separator: ", ")))"
        return "[INFO] \(cellName) (\(gridX),\(gridY)): \(totalRefCount) refs, "
            + "\(drawnRefCount) drawn, \(skipped), \(modelCount) models, "
            + "\(textureCount) textures (\(missingTextureCount) missing)"
    }
}
