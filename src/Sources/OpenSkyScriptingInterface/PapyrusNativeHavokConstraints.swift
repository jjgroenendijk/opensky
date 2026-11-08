import Foundation
public import OpenSkyFormatsESM

/// One end of a script constraint: a reference, the node of its rigid body, and an
/// offset in that body's own space.
nonisolated public struct PapyrusConstraintEnd: Equatable, Sendable {
    public let reference: ReferenceKey
    public let node: String
    public let offset: SIMD3<Float>

    public init(reference: ReferenceKey, node: String, offset: SIMD3<Float> = .zero) {
        self.reference = reference
        self.node = node
        self.offset = offset
    }
}
