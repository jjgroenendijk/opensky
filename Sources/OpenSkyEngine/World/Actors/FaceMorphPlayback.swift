// Actor-local FaceGen expression composition and frame-safe GPU upload.
// TRI deltas are composed on the CPU because the named target set is sparse
// and controlled by the developer panel; the vertex shader consumes one
// position/normal delta pair per face vertex before skinning.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRendering
import simd

nonisolated public struct FaceMorphAssociationMiss: Equatable, Sendable {
    public let headPart: FormID
    public let reason: String
}

nonisolated public protocol LipMorphWeightApplying: AnyObject {
    var actor: FormID { get }
    var targetNames: [String] { get }

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int

    @discardableResult
    func clearLipWeights() -> Int
}

nonisolated public final class FaceMorphPlayback: RenderAnimation, LipMorphWeightApplying {
    public let actor: FormID
    public let bindings: [ObjectIdentifier: FaceMorphBuffer]
    public let pairedPaths: [String]
    public let misses: [FaceMorphAssociationMiss]
    public let worldBounds: ModelBounds?
    private var manualWeights: [String: Float] = [:]
    private var lipWeights: [String: Float] = [:]
    public private(set) var unknownTargetCount = 0

    public var weights: [String: Float] {
        var combined = manualWeights
        for (target, value) in lipWeights {
            combined[target] = min(max((combined[target] ?? 0) + value, 0), 1)
        }
        return combined
    }

    public var targetNames: [String] {
        Array(Set(bindings.values.flatMap { $0.targets.map(\.name) })).sorted()
    }

    public init(
        actor: FormID,
        bindings: [ObjectIdentifier: FaceMorphBuffer],
        pairedPaths: [String],
        misses: [FaceMorphAssociationMiss],
        worldBounds: ModelBounds?
    ) {
        self.actor = actor
        self.bindings = bindings
        self.pairedPaths = pairedPaths
        self.misses = misses
        self.worldBounds = worldBounds
    }

    @discardableResult
    public func setWeight(_ weight: Float, for target: String) -> Bool {
        guard targetNames.contains(target) else {
            unknownTargetCount += 1
            return false
        }
        manualWeights[target] = min(max(weight.isFinite ? weight : 0, 0), 1)
        applyWeights()
        return true
    }

    @discardableResult
    public func setLipWeights(_ weights: [String: Float]) -> Int {
        let targets = Set(targetNames)
        lipWeights = weights.filter { targets.contains($0.key) }
        return applyWeights()
    }

    @discardableResult
    public func clearLipWeights() -> Int {
        guard !lipWeights.isEmpty else { return 0 }
        lipWeights.removeAll(keepingCapacity: true)
        return applyWeights()
    }

    @discardableResult
    public func update(at _: Float) -> Int {
        0
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        manualWeights.removeAll(keepingCapacity: true)
        lipWeights.removeAll(keepingCapacity: true)
        return applyWeights()
    }

    @discardableResult
    private func applyWeights() -> Int {
        for buffer in bindings.values {
            buffer.update(weights: weights)
        }
        return bindings.count
    }
}
