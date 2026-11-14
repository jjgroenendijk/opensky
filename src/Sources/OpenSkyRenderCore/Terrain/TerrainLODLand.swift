// One cell's land as the terrain LOD generator reads it: heights, normals, and colours
// on the 33 x 33 vertex grid, and the texture layers of each quadrant
// (docs/engine/distant-lod.md#generated-terrain).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

nonisolated public struct TerrainLODLand: Sendable {
    /// One quadrant's base texture and its layers in blend order, each with dense
    /// 17 x 17 opacities.
    public struct Quadrant: Sendable {
        public let base: FormID
        public let layers: [(texture: FormID, opacities: [Float])]

        public init(base: FormID, layers: [(texture: FormID, opacities: [Float])]) {
            self.base = base
            self.layers = layers
        }
    }

    /// World heights, row-major from the south-west corner.
    public let heights: [Float]
    /// Unit normals; up where the record has none.
    public let normals: [SIMD3<Float>]
    /// `VCLR` from 0 to 1 in gamma; white where the record has none.
    public let colours: [SIMD3<Float>]
    /// Quadrants 0 to 3: south-west, south-east, north-west, north-east.
    public let quadrants: [Quadrant]

    public init(
        heights: [Float],
        normals: [SIMD3<Float>],
        colours: [SIMD3<Float>],
        quadrants: [Quadrant]
    ) {
        self.heights = heights
        self.normals = normals
        self.colours = colours
        self.quadrants = quadrants
    }

    /// Nil for a record without heights.
    public init?(land: Land) {
        guard let heights = land.heightField?.heights, heights.count == Land.vertexCount else {
            return nil
        }
        let count = Land.vertexCount
        let normals = (0 ..< count).map { index -> SIMD3<Float> in
            guard let raw = land.normals, index < raw.count else { return SIMD3(0, 0, 1) }
            let vector = SIMD3<Float>(Float(raw[index].x), Float(raw[index].y), Float(raw[index].z))
            let length = simd_length(vector)
            return length > 0 ? vector / length : SIMD3(0, 0, 1)
        }
        let colours = (0 ..< count).map { index -> SIMD3<Float> in
            guard let raw = land.colors, index < raw.count else { return SIMD3(1, 1, 1) }
            return SIMD3<Float>(Float(raw[index].x), Float(raw[index].y), Float(raw[index].z)) / 255
        }
        let quadrants = (UInt8(0) ..< 4).map { quadrant in
            Quadrant(
                base: land.baseTexture(quadrant: quadrant),
                layers: land.layers.filter { $0.quadrant == quadrant }
                    .sorted { $0.layer < $1.layer }
                    .map { ($0.texture, TerrainMeshBuilder.denseOpacities($0.alphas)) }
            )
        }
        self.init(heights: heights, normals: normals, colours: colours, quadrants: quadrants)
    }

    /// Bilinear on the vertex grid; `x` and `y` in quads from the south-west corner.
    func height(x: Float, y: Float) -> Float {
        Self.bilinear(x: x, y: y) { heights[$0] }
    }

    func normal(x: Float, y: Float) -> SIMD3<Float> {
        simd_normalize(Self.bilinear(x: x, y: y) { normals[$0] })
    }

    static func bilinear<Value: SIMDOrFloat>(
        x: Float,
        y: Float,
        _ value: (Int) -> Value
    ) -> Value {
        let last = Float(Land.dimension - 1)
        let clampedX = min(max(x, 0), last)
        let clampedY = min(max(y, 0), last)
        let column = min(Int(clampedX), Land.dimension - 2)
        let row = min(Int(clampedY), Land.dimension - 2)
        let fx = clampedX - Float(column)
        let fy = clampedY - Float(row)
        let index = row * Land.dimension + column
        let south = value(index).mixed(with: value(index + 1), by: fx)
        let north = value(index + Land.dimension).mixed(
            with: value(index + Land.dimension + 1),
            by: fx
        )
        return south.mixed(with: north, by: fy)
    }
}

/// A value the bilinear sample can blend.
nonisolated protocol SIMDOrFloat {
    func mixed(with other: Self, by amount: Float) -> Self
}

nonisolated extension Float: SIMDOrFloat {
    func mixed(with other: Float, by amount: Float) -> Float {
        self + (other - self) * amount
    }
}

nonisolated extension SIMD3<Float>: SIMDOrFloat {
    func mixed(with other: SIMD3<Float>, by amount: Float) -> SIMD3<Float> {
        simd_mix(self, other, SIMD3(repeating: amount))
    }
}
