public import OpenSkyScriptingInterface

/// What the world adapters use of `ObjectAnimationWorldAdapter`.
public protocol ObjectAnimationWorldPort: AnyObject, PapyrusObjectAnimationBridge {
    func answerWait(token: UInt64, fired: Bool)
    var objects: any ObjectBehaviorPort { get }
}
