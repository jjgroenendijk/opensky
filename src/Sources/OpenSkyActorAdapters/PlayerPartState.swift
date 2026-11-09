public import OpenSkyPlayer
public import OpenSkyWorldInterface

/// The session's player parts. The composition root sets these, so the hosts stay port-only.
public final class PlayerPartState {
    public var locomotion: () -> LocomotionBridge? = { nil }
    public var firstPersonRig: () -> PlayerFirstPersonRig? = { nil }
    public var playerFace: () -> FaceMorphPlayback? = { nil }

    public init() {}
}
