// The detail levels of a `BSLODTriShape`: three triangle counts over one index list.
// Level 0 is full detail. docs/formats/nif.md has the layout.

nonisolated public enum MeshLODLevels {
    /// The index count each level draws, or empty when the counts do not fit `indexCount`.
    /// Falling counts are prefixes of the list (level n draws the first `counts[n]`
    /// triangles); other counts are runs, and level n leaves out the last n runs.
    public static func indexCounts(triangleCounts counts: [UInt32], indexCount: Int) -> [Int] {
        guard counts.count == 3, indexCount > 0 else { return [] }
        let triangles = counts.map { Int($0) }
        let total = indexCount / 3
        let falling = triangles[0] >= triangles[1] && triangles[1] >= triangles[2]
        let levels = falling && triangles[0] <= total
            ? triangles
            : [triangles.reduce(0, +), triangles[0] + triangles[1], triangles[0]]
        guard
            levels.allSatisfy({ $0 > 0 && $0 <= total }),
            levels != [total, total, total]
        else { return [] }
        return levels.map { $0 * 3 }
    }
}
