// The world side of the player: what `PlayerCoordinator` reads from and does to
// the running renderer. The app answers it; a test passes a fake.

import OpenSkyFormatsESM
import OpenSkyGameData

/// What `PlayerCoordinator` reads from the running world.
public protocol PlayerWorld: AnyObject {
    /// Nil without a renderer.
    var playerLocomotion: LocomotionBridge? { get }
    var isPlayerGrounded: Bool { get }
    /// Nil while nothing has touched the player's inventory. The body then
    /// wears the plugin's default outfit.
    var playerEquippedSet: [FormID]? { get }
    /// The race menu choices; nil keeps the `Player` record.
    var playerAppearanceOverride: PlayerAppearanceOverride? { get }
    /// The behaviour project of a race with its own, such as a beast form's; nil for a race
    /// that runs the character graphs.
    var playerBehaviorProject: String? { get }
    /// True while the weapon rides the hand node rather than its sheath.
    var playerWeaponsDrawn: Bool { get }
    func showPlayerBody(_ body: PlayerBody) throws
    func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws
    var playerFirstPersonRig: PlayerFirstPersonRig? { get }
    var areFirstPersonArmsVisible: Bool { get }
    /// Nil without a renderer.
    var firstPersonFOVYRadians: Float? { get }
    func setFirstPersonFOVY(radians: Float)
    /// Nil without a renderer.
    var firstPersonArmsEnabled: Bool? { get }
    func setFirstPersonArmsEnabled(_ enabled: Bool)
}
