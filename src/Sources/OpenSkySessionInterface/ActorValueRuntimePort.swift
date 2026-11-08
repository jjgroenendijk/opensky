public import OpenSkyActorsInterface
public import OpenSkyGameData

/// What the world adapters use of `ActorValueRuntime`.
public protocol ActorValueRuntimePort: ActorValueAccess {
    func setGodMode(_ isOn: Bool)
    func baseValue(at index: Int32, on holder: ActorValueHolder) -> Float?
    func baseline(of holder: ActorValueHolder) -> ActorValueBaseline
    var baselines: ActorValueBaselineResolver { get }
    func current(of holder: ActorValueHolder) -> ActorValues
    @discardableResult func damage(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState
    @discardableResult func damage(
        at index: Int32,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> Bool
    func fraction(at index: Int32, on holder: ActorValueHolder) -> Float?
    func fractions(of holder: ActorValueHolder) -> ActorValues
    var godMode: Bool { get set }
    func hasZeroHealth(_ holder: ActorValueHolder) -> Bool
    func maximums(of holder: ActorValueHolder) -> ActorValues
    func pauseRegeneration(_ kind: ActorValueKind, on holder: ActorValueHolder, for seconds: Float)
    func permanentMaximum(of kind: ActorValueKind, for holder: ActorValueHolder) -> Float
    var regeneration: RegenerationSettings { get }
    func regenerationPause(_ kind: ActorValueKind, of holder: ActorValueHolder) -> Float
    @discardableResult func restore(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState
    @discardableResult func restore(at index: Int32, by amount: Float, on holder: ActorValueHolder)
        -> Bool
    @discardableResult func restoreAll(on holder: ActorValueHolder) -> ActorValueState
    func value(at index: Int32, on holder: ActorValueHolder) -> Float?
}
