// Actor-local FaceGen expression composition and frame-safe GPU upload.
// TRI deltas are composed on the CPU because the named target set is sparse
// and controlled by the developer panel; the vertex shader consumes one
// position/normal delta pair per face vertex before skinning.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering
import simd
import Synchronization

nonisolated public struct FaceMorphAssociationMiss: Equatable, Sendable {
    public let headPart: FormID
    public let reason: String
}

nonisolated public protocol LipMorphWeightApplying: AnyObject, Sendable {
    var actor: FormID { get }
    var targetNames: [String] { get }

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int

    @discardableResult
    func clearLipWeights() -> Int
}

nonisolated public final class FaceMorphPlayback: RenderAnimation, LipMorphWeightApplying {
    nonisolated private struct State {
        var manualWeights: [String: Float] = [:]
        var lipWeights: [String: Float] = [:]
        var unknownTargetCount = 0

        var weights: [String: Float] {
            var combined = manualWeights
            for (target, value) in lipWeights {
                combined[target] = min(max((combined[target] ?? 0) + value, 0), 1)
            }
            return combined
        }
    }

    public let actor: FormID
    public let bindings: [ObjectIdentifier: FaceMorphBuffer]
    public let pairedPaths: [String]
    public let misses: [FaceMorphAssociationMiss]
    /// Changed on the main actor after the build queue hands the scene over.
    private let state = Mutex(State())

    public var unknownTargetCount: Int {
        state.withLock { $0.unknownTargetCount }
    }

    public var weights: [String: Float] {
        state.withLock { $0.weights }
    }

    public var targetNames: [String] {
        Array(Set(bindings.values.flatMap { $0.targets.map(\.name) })).sorted()
    }

    public init(
        actor: FormID,
        bindings: [ObjectIdentifier: FaceMorphBuffer],
        pairedPaths: [String],
        misses: [FaceMorphAssociationMiss]
    ) {
        self.actor = actor
        self.bindings = bindings
        self.pairedPaths = pairedPaths
        self.misses = misses
    }

    @discardableResult
    public func setWeight(_ weight: Float, for target: String) -> Bool {
        guard targetNames.contains(target) else {
            state.withLock { $0.unknownTargetCount += 1 }
            return false
        }
        state.withLock { $0.manualWeights[target] = min(max(weight.isFinite ? weight : 0, 0), 1) }
        applyWeights()
        return true
    }

    @discardableResult
    public func setLipWeights(_ weights: [String: Float]) -> Int {
        let targets = Set(targetNames)
        state.withLock { $0.lipWeights = weights.filter { targets.contains($0.key) } }
        return applyWeights()
    }

    @discardableResult
    public func clearLipWeights() -> Int {
        let hadWeights = state.withLock { state in
            defer { state.lipWeights.removeAll(keepingCapacity: true) }
            return !state.lipWeights.isEmpty
        }
        return hadWeights ? applyWeights() : 0
    }

    @discardableResult
    public func update(at _: Float) -> Int {
        0
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        state.withLock {
            $0.manualWeights.removeAll(keepingCapacity: true)
            $0.lipWeights.removeAll(keepingCapacity: true)
        }
        return applyWeights()
    }

    @discardableResult
    private func applyWeights() -> Int {
        let weights = weights
        for buffer in bindings.values {
            buffer.update(weights: weights)
        }
        return bindings.count
    }
}
