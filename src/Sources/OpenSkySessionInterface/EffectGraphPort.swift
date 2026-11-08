public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `EffectGraphCoordinator`.
public protocol EffectGraphPort: AnyObject {
    @discardableResult func deliver(_ event: String, from actor: ReferenceKey) -> Bool
    var rows: [EffectGraphRow] { get }
    @discardableResult func setSubGraphVariable(
        _ value: Float,
        named name: String,
        on actor: ReferenceKey
    ) -> Bool
    func tick(deltaTime: Float)
}
