public import OpenSkyScriptingInterface

/// What the world adapters use of `ScriptCoordinator`.
public protocol ScriptPort: AnyObject {
    associatedtype PapyrusWorldRuntime: PapyrusWorldRuntimePort
    associatedtype PapyrusWorldStateBridge: PapyrusWorldStateBridgePort
    func advance(delta: Float)
    func advanceRestStep()
    var bridge: PapyrusWorldStateBridge? { get }
    func reportSleep(start: Double, end: Double)
    func restore(instances: [PapyrusInstanceState], timers: [PapyrusTimerState])
    var runtime: PapyrusWorldRuntime? { get }
    var scriptsSnapshot: ScriptsSnapshot { get }
    func advanceMenuTime(delta: Float)
}
