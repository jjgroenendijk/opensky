public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `PlayerCoordinator`.
public protocol PlayerPort: AnyObject {
    func drainClipLoads()
    var eyeTextureSet: FormID? { get set }
    var failureReason: String? { get }
    var firstPersonSnapshot: FirstPersonSnapshot { get }
    var graphProject: String? { get }
    var isSneaking: Bool { get set }
    func playIdle(named name: String, state: String?)
    var raceGraphFailureReason: String? { get }
    func refreshBody()
    func requestBody()
}
