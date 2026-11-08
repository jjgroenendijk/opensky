public import OpenSkyWorldInterface

/// What the world adapters use of `SequenceDoorCoordinator`.
public protocol SequenceDoorPort: AnyObject {
    func openStateCode(of reference: UInt32) -> Int32?
    func swingOpen(_ reference: UInt32)
    func sync() -> [SequenceDoorCommand]
    func tick(deltaTime: Float) -> [SequenceDoorCommand]
}
