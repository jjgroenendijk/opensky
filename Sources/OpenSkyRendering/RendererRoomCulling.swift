// Finds the interior rooms the camera sees each frame, for both culling paths.
// See docs/rendering/room-portal-culling.md.

import simd

/// The renderer's room-and-portal culling state.
public struct RoomCullingState {
    /// Off draws every room.
    public var enabled = true
    /// This frame's camera visibility; nil draws every room.
    var visibility: RoomVisibility?
}

/// What the room walk saw in the last frame.
nonisolated public struct RoomCullingReadout: Equatable, Sendable {
    public var rooms = 0
    public var portals = 0
    /// Rooms seen this frame; nil when culling is off or the camera is in no room.
    public var visibleRooms: Int?
    /// Camera instances skipped by rooms, over both culling paths.
    public var culledInstances = 0

    public init(
        rooms: Int = 0,
        portals: Int = 0,
        visibleRooms: Int? = nil,
        culledInstances: Int = 0
    ) {
        self.rooms = rooms
        self.portals = portals
        self.visibleRooms = visibleRooms
        self.culledInstances = culledInstances
    }
}

extension Renderer {
    public var roomCullingEnabled: Bool {
        get { roomCulling.enabled }
        set { roomCulling.enabled = newValue }
    }

    public var roomCullingReadout: RoomCullingReadout {
        RoomCullingReadout(
            rooms: scene.rooms?.rooms.count ?? 0,
            portals: scene.rooms?.portals.count ?? 0,
            visibleRooms: roomCulling.visibility?.visibleCount,
            culledInstances: combinedDrawStats().roomCulledInstances
        )
    }

    func updateRoomVisibility(viewProjection: float4x4) {
        guard roomCulling.enabled, let rooms = scene.rooms else {
            roomCulling.visibility = nil
            return
        }
        roomCulling.visibility = rooms.visibleRooms(
            eye: freeFlyCamera.position, viewProjection: viewProjection
        )
    }
}
