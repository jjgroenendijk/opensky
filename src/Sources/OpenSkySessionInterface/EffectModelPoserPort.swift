public import OpenSkyWorldInterface

/// What the world adapters use of `EffectModelPoser`.
public protocol EffectModelPoserPort: AnyObject {
    var rows: [PosedEffectRow] { get }
}
