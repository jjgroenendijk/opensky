/// Which camera the world is viewed through. `fly` is the developer's free view;
/// `walk` and `thirdPerson` show the same simulated player from the eye and from behind.
nonisolated public enum CameraMovementMode: Equatable, CaseIterable, Sendable {
    case fly
    case walk
    case thirdPerson

    /// True while the capsule, the locomotion bridge, and the player body are
    /// being simulated. Everything gated on "the player exists" reads this
    /// rather than comparing against `.walk`, so a third-person session keeps
    /// its interaction ray, its trigger volumes, and its readouts.
    public var isPlayerControlled: Bool {
        self != .fly
    }

    /// The next mode in the cycle the camera key and the panel selector share.
    public var next: CameraMovementMode {
        switch self {
        case .fly: .walk
        case .walk: .thirdPerson
        case .thirdPerson: .fly
        }
    }
}
