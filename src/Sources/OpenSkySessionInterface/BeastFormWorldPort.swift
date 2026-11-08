public import OpenSkyWorldInterface

/// What the world adapters use of `BeastFormWorldAdapter`.
public protocol BeastFormWorldPort: AnyObject {
    func force(_ wanted: PlayerBeastForm) -> Bool
}
