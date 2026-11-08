public import QuartzCore

/// What the world adapters use of `SteppedWallClock`.
public protocol SteppedWallClockPort: AnyObject {
    var frame: Int { get }
    func freeze()
    var isFrozen: Bool { get }
    var now: CFTimeInterval { get }
    var pendingSteps: Int { get }
    func requestSteps(_ count: Int, seconds: CFTimeInterval)
    func resume()
    var scale: Double { get }
    func setScale(_ scale: Double)
}
