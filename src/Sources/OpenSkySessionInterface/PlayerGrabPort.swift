public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// The player's grab of a loose object or a dead body (docs/engine/grab.md).
public protocol PlayerGrabPort: AnyObject {
    var grabReadout: PlayerGrabReadout { get }
    /// Grabs `key` at once, as a held Activate would; false when it cannot be grabbed.
    func grab(_ key: ReferenceKey) -> Bool
    func letGo()
}
