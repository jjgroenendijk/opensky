// Interior occlusion: room boxes joined by portal boxes, and the walk that finds
// the rooms the camera can see. An OpenSky policy; see
// docs/rendering/room-portal-culling.md.

import OpenSkyFormatsCore
import simd

/// A local `[-halfExtents, halfExtents]` box placed by `transform`.
nonisolated public struct OrientedBox: Equatable, Sendable {
    public let transform: float4x4
    public let halfExtents: SIMD3<Float>
    private let inverse: float4x4

    /// Nil for a box with no volume or a transform that cannot be inverted.
    public init?(transform: float4x4, halfExtents: SIMD3<Float>) {
        guard
            all(halfExtents .> 0), all(halfExtents .< .infinity),
            abs(transform.determinant) > .ulpOfOne
        else { return nil }
        self.transform = transform
        self.halfExtents = halfExtents
        inverse = transform.inverse
    }

    public func contains(_ point: SIMD3<Float>) -> Bool {
        let local = inverse * SIMD4(point, 1)
        return all(abs(SIMD3(local.x, local.y, local.z)) .<= halfExtents)
    }

    /// Never misses a real overlap; may report one the boxes do not have.
    public func touches(_ bounds: ModelBounds) -> Bool {
        let local = bounds.transformed(by: inverse)
        return all(local.min .<= halfExtents) && all(local.max .>= -halfExtents)
    }

    public var corners: [SIMD3<Float>] {
        ModelBounds(min: -halfExtents, max: halfExtents).corners.map { corner in
            let world = transform * SIMD4(corner, 1)
            return SIMD3(world.x, world.y, world.z)
        }
    }
}

/// The rooms of one interior and the portals between them.
nonisolated public struct RoomPortalGraph: Equatable, Sendable {
    /// One portal box between two rooms, by index into `rooms`.
    public struct Portal: Equatable, Sendable {
        public let box: OrientedBox
        public let rooms: SIMD2<Int32>

        public init(box: OrientedBox, rooms: SIMD2<Int32>) {
            self.box = box
            self.rooms = rooms
        }
    }

    /// The room index of an instance that belongs to no single room.
    public static let noRoom = UInt32.max

    public let rooms: [OrientedBox]
    public let portals: [Portal]
    /// Linked rooms by room index, both ways.
    public let links: [[Int]]
    private let portalsByRoom: [[Int]]

    /// Drops portals and links whose rooms are out of range.
    public init(rooms: [OrientedBox], portals: [Portal], links: [SIMD2<Int32>]) {
        let valid = 0 ..< Int32(rooms.count)
        self.rooms = rooms
        self.portals = portals.filter {
            valid.contains($0.rooms.x) && valid.contains($0.rooms.y) && $0.rooms.x != $0.rooms.y
        }
        var linked = [[Int]](repeating: [], count: rooms.count)
        for link in links where valid.contains(link.x) && valid.contains(link.y) {
            linked[Int(link.x)].append(Int(link.y))
            linked[Int(link.y)].append(Int(link.x))
        }
        self.links = linked
        var byRoom = [[Int]](repeating: [], count: rooms.count)
        for (index, portal) in self.portals.enumerated() {
            byRoom[Int(portal.rooms.x)].append(index)
            byRoom[Int(portal.rooms.y)].append(index)
        }
        portalsByRoom = byRoom
    }

    /// The one room `bounds` touches, or `noRoom` when it touches none or several.
    public func soleRoom(touching bounds: ModelBounds) -> UInt32 {
        var found = Self.noRoom
        for (index, room) in rooms.enumerated() where room.touches(bounds) {
            guard found == Self.noRoom else { return Self.noRoom }
            found = UInt32(index)
        }
        return found
    }

    /// Nil when the eye is in no room, which turns room culling off.
    public func visibleRooms(eye: SIMD3<Float>, viewProjection: float4x4) -> RoomVisibility? {
        var walk = RoomWalk(roomCount: rooms.count)
        for (index, room) in rooms.enumerated() where room.contains(eye) {
            walk.widen(index, to: .fullScreen)
        }
        guard walk.hasStarted else { return nil }
        // Rects only grow, so the walk ends; the cap guards float creep.
        var budget = 4 * (rooms.count + 1) * (portals.count + 1)
        while let room = walk.next() {
            budget -= 1
            guard budget > 0 else { return nil }
            let rect = walk.rect(of: room)
            for linked in links[room] {
                walk.widen(linked, to: rect)
            }
            for index in portalsByRoom[room] {
                let portal = portals[index]
                let other = Int(portal.rooms.x) == room ? portal.rooms.y : portal.rooms.x
                if let through = Self.narrow(rect, through: portal.box, eye, viewProjection) {
                    walk.widen(Int(other), to: through)
                }
            }
        }
        return walk.visibility
    }

    /// The part of `rect` seen through `portal`, nil when none is.
    static func narrow(
        _ rect: ScreenRect,
        through portal: OrientedBox,
        _ eye: SIMD3<Float>,
        _ viewProjection: float4x4
    ) -> ScreenRect? {
        if portal.contains(eye) {
            return rect
        }
        let clips = portal.corners.map { viewProjection * SIMD4($0, 1) }
        let inFront = clips.filter { $0.z > 0 && $0.w > 0 }
        guard !inFront.isEmpty else { return nil }
        guard inFront.count == clips.count else { return rect }
        var lower = SIMD2<Float>(repeating: .infinity)
        var upper = SIMD2<Float>(repeating: -.infinity)
        for clip in clips {
            let ndc = SIMD2(clip.x, clip.y) / clip.w
            lower = simd_min(lower, ndc)
            upper = simd_max(upper, ndc)
        }
        return rect.intersection(ScreenRect(min: lower, max: upper))
    }
}

/// A rectangle in normalised device coordinates.
nonisolated struct ScreenRect: Equatable, Sendable {
    static let fullScreen = ScreenRect(min: SIMD2(-1, -1), max: SIMD2(1, 1))

    var min: SIMD2<Float>
    var max: SIMD2<Float>

    func intersection(_ other: ScreenRect) -> ScreenRect? {
        let result = ScreenRect(min: simd_max(min, other.min), max: simd_min(max, other.max))
        return all(result.min .< result.max) ? result : nil
    }

    func union(_ other: ScreenRect) -> ScreenRect {
        ScreenRect(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }
}

/// The visibility walk's open rooms and the screen rect each is seen through.
nonisolated private struct RoomWalk {
    private var rects: [ScreenRect?]
    private var queue: [Int] = []
    private(set) var hasStarted = false

    init(roomCount: Int) {
        rects = Array(repeating: nil, count: roomCount)
    }

    mutating func widen(_ room: Int, to rect: ScreenRect) {
        hasStarted = true
        let merged = rects[room].map { $0.union(rect) } ?? rect
        guard merged != rects[room] else { return }
        rects[room] = merged
        queue.append(room)
    }

    mutating func next() -> Int? {
        queue.popLast()
    }

    func rect(of room: Int) -> ScreenRect {
        rects[room] ?? .fullScreen
    }

    var visibility: RoomVisibility {
        RoomVisibility(visible: rects.map { $0 != nil })
    }
}

/// Which rooms the camera sees this frame, as a bitset the cull kernel reads.
nonisolated public struct RoomVisibility: Equatable, Sendable {
    public let words: [UInt32]
    public let visibleCount: Int

    public init(visible: [Bool]) {
        var words = [UInt32](repeating: 0, count: (visible.count + 31) / 32)
        for (index, isVisible) in visible.enumerated() where isVisible {
            words[index / 32] |= 1 << UInt32(index % 32)
        }
        self.words = words
        visibleCount = visible.count(where: \.self)
    }

    /// An instance with no room is always visible.
    public func contains(room: UInt32) -> Bool {
        guard room != RoomPortalGraph.noRoom else { return true }
        let word = Int(room / 32)
        return word < words.count && words[word] & (1 << (room % 32)) != 0
    }
}
