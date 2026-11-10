// The eight corners and twelve triangles of an axis-aligned box around the origin.

nonisolated public enum CollisionBox {
    public static let indices: [UInt32] = [
        0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
        0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
        2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7
    ]

    public static func vertices(_ half: SIMD3<Float>) -> [SIMD3<Float>] {
        [
            SIMD3(-half.x, -half.y, -half.z), SIMD3(half.x, -half.y, -half.z),
            SIMD3(half.x, half.y, -half.z), SIMD3(-half.x, half.y, -half.z),
            SIMD3(-half.x, -half.y, half.z), SIMD3(half.x, -half.y, half.z),
            SIMD3(half.x, half.y, half.z), SIMD3(-half.x, half.y, half.z)
        ]
    }
}
