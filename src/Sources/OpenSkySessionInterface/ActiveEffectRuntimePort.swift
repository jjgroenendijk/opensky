public import OpenSkyGameData
public import OpenSkyMagicInterface

/// What the world adapters use of `ActiveEffectRuntime`.
public protocol ActiveEffectRuntimePort {
    func active(on holder: ActorValueHolder) -> [ActiveEffect]
    var effects: MagicEffectStore { get }
}
