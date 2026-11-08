public import OpenSkyBehavior
public import OpenSkyFormatsCore
public import OpenSkyWorldInterface
public import simd

/// What the world adapters use of `ObjectBehaviorCoordinator`.
public protocol ObjectBehaviorPort: AnyObject {
    func worldBone(of reference: UInt32, named name: String) -> float4x4?
    func bone(of reference: UInt32, named name: String) -> PosedBone?
    func boneMatrices(of reference: UInt32) -> [simd_float4x4]?
    var rows: [ObjectAnimationRow] { get }

    func awaitEvent(_ event: String, on reference: UInt32) -> UInt64?
    func contactPositions(of reference: UInt32) -> [SIMD3<Float>]?
    var runningReferences: [UInt32] { get }
    @discardableResult func send(_ event: String, to reference: UInt32) -> Bool
    @discardableResult func setVariable(
        _ value: BehaviorVariableValue,
        named name: String,
        on reference: UInt32
    ) -> Bool
    func sync()
    func tick(deltaTime: Float)
    func variable(named name: String, on reference: UInt32) -> BehaviorVariableValue?
}
