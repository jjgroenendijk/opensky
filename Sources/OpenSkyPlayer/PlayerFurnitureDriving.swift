// The furniture the player sits in. While seated, a move key gets the player up,
// as in the game (docs/engine/furniture.md).

/// The session asks it to stand the player up; the app answers it.
@MainActor
public protocol PlayerFurnitureDriving: AnyObject {
    /// A move or jump key was pressed while the player sits. Nothing happens on a vehicle.
    func playerAskedToStand()
}
