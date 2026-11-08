public import OpenSkyWorldInterface

/// What the world adapters use of `NodeControllerCoordinator`.
public protocol NodeControllerPort: AnyObject {
    func sync()
    func tick(deltaTime: Float)
    func nodes(of reference: UInt32) -> [NodeControllerNodeRow]?
    var references: [UInt32] { get }
}
