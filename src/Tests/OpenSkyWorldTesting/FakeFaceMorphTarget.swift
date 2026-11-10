// A face mesh's morph targets for playback tests: it keeps the last weights it was sent.

public import OpenSkyWorldInterface
import Synchronization

nonisolated public final class FakeFaceMorphTarget: FaceMorphWeightTarget {
    public let targetNames: [String]
    private let sent = Mutex<[[String: Float]]>([])

    public init(targetNames: [String]) {
        self.targetNames = targetNames
    }

    public var uploads: [[String: Float]] {
        sent.withLock { $0 }
    }

    public func update(weights: [String: Float]) {
        sent.withLock { $0.append(weights) }
    }
}
