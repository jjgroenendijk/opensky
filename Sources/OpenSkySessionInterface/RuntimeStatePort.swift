public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What the world adapters use of `RuntimeStateCoordinator`.
public protocol RuntimeStatePort: AnyObject {
    func conditionContext(indexing keys: [ReferenceKey]) -> ConditionContext
    func dateLine(of clock: GameClock) -> String
    func globalResolution() -> GlobalResolution
    var globalStore: GlobalStore? { get }
    var runtimeStateClock: RuntimeStateClockSnapshot { get }
    func runtimeStateGlobal(editorID: String) -> RuntimeStateGlobalSnapshot?
    func setGameClockHour(_ hour: Float)
    @discardableResult func setGlobalValue(_ value: Float, editorID: String) -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension RuntimeStatePort {
    @discardableResult public func conditionContext() -> ConditionContext {
        conditionContext(indexing: [])
    }
}
