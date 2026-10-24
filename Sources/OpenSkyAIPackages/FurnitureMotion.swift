// Where an actor's root is while an entry or exit clip carries it into or out of a
// seat. The clip's root motion is relative to where the clip starts.
// See docs/engine/furniture.md.

import Foundation
import OpenSkyWorldInterface
import simd

/// A root position and a facing.
nonisolated public struct FurniturePose: Equatable, Sendable {
    public let root: SIMD3<Float>
    /// Clockwise radians, as a reference's z rotation.
    public let heading: Float

    public init(root: SIMD3<Float>, heading: Float) {
        self.root = root
        self.heading = heading
    }

    /// Moves by an offset in this pose's own frame (+x right, +y forward) and turns by
    /// `yaw` counter-clockwise radians, as clip root motion does.
    public func moved(by offset: SIMD3<Float>, turning yaw: Float) -> FurniturePose {
        let forward = SIMD2(sin(heading), cos(heading))
        let right = SIMD2(forward.y, -forward.x)
        let step = right * offset.x + forward * offset.y
        return FurniturePose(root: root + SIMD3(step.x, step.y, offset.z), heading: heading - yaw)
    }

    /// Where a clip that ends on this pose after `offset` and `yaw` started.
    public func start(beforeMoving offset: SIMD3<Float>, turning yaw: Float) -> FurniturePose {
        let turned = FurniturePose(root: root, heading: heading + yaw)
        let step = turned.moved(by: offset, turning: 0).root - root
        return FurniturePose(root: root - step, heading: turned.heading)
    }
}

/// An entry or exit clip's root motion at one moment, from the idle runtime.
nonisolated public struct FurnitureMotionSample: Equatable, Sendable {
    public let offset: SIMD3<Float>
    /// Counter-clockwise radians.
    public let yaw: Float
    public let endOffset: SIMD3<Float>
    public let endYaw: Float
    public let isFinished: Bool

    public init(
        offset: SIMD3<Float>, yaw: Float, endOffset: SIMD3<Float>, endYaw: Float, isFinished: Bool
    ) {
        self.offset = offset
        self.yaw = yaw
        self.endOffset = endOffset
        self.endYaw = endYaw
        self.isFinished = isFinished
    }
}

nonisolated extension FurnitureSeat {
    public var seatedPose: FurniturePose {
        FurniturePose(root: root, heading: heading)
    }

    /// An entry clip ends on the seat, so it starts where its motion leads back from.
    public func enteringPose(_ sample: FurnitureMotionSample) -> FurniturePose {
        seatedPose.start(beforeMoving: sample.endOffset, turning: sample.endYaw)
            .moved(by: sample.offset, turning: sample.yaw)
    }

    /// An exit clip starts on the seat.
    public func leavingPose(_ sample: FurnitureMotionSample) -> FurniturePose {
        seatedPose.moved(by: sample.offset, turning: sample.yaw)
    }

    /// Without an exit motion the actor stands `standDistance` out on its entry side.
    public func standingPose(entry: UInt16) -> FurniturePose {
        FurniturePose(root: standPoint(entry: entry), heading: heading)
    }
}
