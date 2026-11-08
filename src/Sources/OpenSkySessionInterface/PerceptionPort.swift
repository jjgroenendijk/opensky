public import OpenSkyPerceptionInterface
public import OpenSkyRenderCore

/// What the world adapters use of `PerceptionCoordinator`.
public protocol PerceptionPort: AnyObject {
    associatedtype PerceptionRuntime: PerceptionRuntimePort
    func advance(by delta: Float) -> [PerceptionCommand]
    func appendWorldOverlay(context: WorldOverlayFrameContext, to list: inout WorldOverlayDrawList)
    func perceptionResolution() -> DetectionResolution
    var runtime: PerceptionRuntime? { get }
}
