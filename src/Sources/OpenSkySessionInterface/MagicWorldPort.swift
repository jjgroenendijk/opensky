public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface

/// What the world adapters use of `MagicWorldAdapter`.
public protocol MagicWorldPort: AnyObject {
    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder?
    @discardableResult func applySpellHit(_ hit: SpellHit) -> SpellHitReport
    func castReach(within range: Float) -> Float
    /// A shout word's cooldown: its recovery time scaled by `multiplier`.
    func shoutCooldown(recovery: Float, multiplier: Float) -> Float
    @discardableResult func staggerActor(_ key: ReferenceKey, magnitude: Float) -> Bool
}
