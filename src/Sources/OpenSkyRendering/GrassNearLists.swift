// Each grass group keeps the instances near the camera: inside the draw distance plus a
// margin, after the density test. The per-frame tests then walk that list only. A list is
// built again after the camera moves part of the margin; each group uses its own part,
// so the rebuilds spread over frames. See docs/engine/update-bands.md.

import OpenSkyGameData
import simd

/// The near instance list of each grass group, by group index.
nonisolated struct GrassNearLists {
    /// Units past the draw distance a list still holds. A list is valid while the camera
    /// stays within this distance of where the list was built.
    static let margin: Float = 1024

    /// Where the camera stands and which instances the frame may draw.
    struct Reach: Equatable {
        let viewer: SIMD3<Float>
        let density: Float
        let drawDistance: Float
    }

    struct List {
        let mesh: ObjectIdentifier
        let instanceCount: Int
        let reach: Reach
        /// Indices into the group's instances, in their order.
        let indices: [Int32]
        let densityCulled: Int
        let outside: Int

        /// True when the list was built for these instances and these limits.
        func matches(mesh: ObjectIdentifier, count: Int, reach: Reach) -> Bool {
            self.mesh == mesh && instanceCount == count && self.reach.density == reach.density
                && self.reach.drawDistance == reach.drawDistance
        }
    }

    private var lists: [List?] = []
    /// Lists built in the last frame, for `openskycli game state frame`.
    private(set) var rebuiltLastFrame = 0

    mutating func beginFrame(groupCount: Int) {
        rebuiltLastFrame = 0
        if lists.count > groupCount {
            lists.removeLast(lists.count - groupCount)
        } else if lists.count < groupCount {
            lists += Array(repeating: nil, count: groupCount - lists.count)
        }
    }

    /// The near list of group `index`, built again when it is missing, stale, or moved past.
    mutating func list(
        of instances: [GrassDrawInstance], mesh: ObjectIdentifier, index: Int, reach: Reach
    ) -> List {
        if
            let list = lists[index], list.matches(mesh: mesh, count: instances.count, reach: reach),
            simd_distance(list.reach.viewer, reach.viewer) < Self.reuseDistance(index: index)
        {
            return list
        }
        let list = Self.build(instances, mesh: mesh, reach: reach)
        lists[index] = list
        rebuiltLastFrame += 1
        return list
    }

    /// How far the camera may move before the list of group `index` is built again:
    /// half the margin to all of it, so groups rebuild in different frames.
    static func reuseDistance(index: Int) -> Float {
        margin * (0.5 + 0.5 * UpdateBandClock.phase(of: UInt64(index)))
    }

    static func build(
        _ instances: [GrassDrawInstance], mesh: ObjectIdentifier, reach: Reach
    ) -> List {
        let farthest = reach.drawDistance + margin
        let farthestSquared = farthest * farthest
        var indices: [Int32] = []
        var densityCulled = 0
        var outside = 0
        for (index, instance) in instances.enumerated() {
            guard instance.densityKey < reach.density else {
                densityCulled += 1
                continue
            }
            guard simd_length_squared(instance.position - reach.viewer) <= farthestSquared else {
                outside += 1
                continue
            }
            indices.append(Int32(index))
        }
        return List(
            mesh: mesh, instanceCount: instances.count, reach: reach, indices: indices,
            densityCulled: densityCulled, outside: outside
        )
    }
}
