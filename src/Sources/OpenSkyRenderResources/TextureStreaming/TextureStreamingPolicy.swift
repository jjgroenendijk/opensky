// Which mip level each streamed texture keeps resident: a distance rule, then a memory
// budget that drops detail from the farthest textures first.
// See docs/rendering/texture-streaming.md.

import Foundation

/// One texture's wish for the next update.
nonisolated public struct TextureDemand: Equatable, Sendable {
    public let layout: SparseTextureLayout
    /// The level the distance rule asks for.
    public let wantedLevel: Int
    /// The camera distance of the closest surface that uses the texture.
    public let distance: Float

    public init(layout: SparseTextureLayout, wantedLevel: Int, distance: Float) {
        self.layout = layout
        self.wantedLevel = wantedLevel
        self.distance = distance
    }
}

/// How the camera sees the scene, for the distance rule.
nonisolated public struct TextureStreamingView: Equatable, Sendable {
    public let viewHeight: Int
    public let tanHalfFOV: Float

    public init(viewHeight: Int, tanHalfFOV: Float) {
        self.viewHeight = max(viewHeight, 1)
        self.tanHalfFOV = max(tanHalfFOV, 0.01)
    }
}

nonisolated public enum TextureStreamingPolicy {
    /// One extra level of detail, so the mip the sampler picks for a slanted surface
    /// is still resident.
    public static let marginLevels = 1

    /// The largest level whose texels still cover the surface at one texel per pixel.
    /// `uvPerUnit` is how many texture repeats one world unit of the surface holds.
    public static func neededLevel(
        textureSize: Int, uvPerUnit: Float, distance: Float, view: TextureStreamingView
    ) -> Int {
        let pixelsPerUnit = Float(view.viewHeight) / (2 * max(distance, 1) * view.tanHalfFOV)
        let texelsPerUnit = Float(max(textureSize, 1)) * uvPerUnit
        let ratio = texelsPerUnit / pixelsPerUnit
        guard ratio > 1 else { return 0 }
        return max(0, Int(log2(ratio).rounded(.down)) - marginLevels)
    }

    /// The resident level of each demand, in order. Starts at the wanted levels, then
    /// drops one level at a time from the farthest texture until the tiles fit
    /// `budgetTiles`. A texture never drops below its floor, so the result can exceed
    /// the budget when the floors alone do.
    public static func fit(_ demands: [TextureDemand], budgetTiles: Int) -> [Int] {
        var levels = demands.map { min(max($0.wantedLevel, 0), $0.layout.floorLevel) }
        var total = zip(demands, levels).reduce(0) { $0 + $1.0.layout.tiles(fromLevel: $1.1) }
        guard total > budgetTiles else { return levels }
        let farthestFirst = demands.indices.sorted { demands[$0].distance > demands[$1].distance }
        var lowered = true
        while total > budgetTiles, lowered {
            lowered = false
            for index in farthestFirst where total > budgetTiles {
                let layout = demands[index].layout
                guard levels[index] < layout.floorLevel else { continue }
                total -= layout.tiles(level: levels[index])
                levels[index] += 1
                lowered = true
            }
        }
        return levels
    }
}
