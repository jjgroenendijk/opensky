// Moves each resident sequence door toward its saved open state: plays the `Open`
// or `Close` sequence, runs the text keys it passes, and moves the leaf collision.
// The open state itself is world state, written by activation and `SetOpen`.
// See docs/engine/object-animation.md#sequence-doors.

import OpenSkyFormatsAnimation
import simd

/// What the door coordinator reads from and writes to the session.
public protocol SequenceDoorWorld: AnyObject {
    func residentSequenceDoors() -> [CellSequenceDoor]
    /// The reference's open state: the plugin's, or the one a save, script, or
    /// activation wrote.
    func sequenceDoorWantsOpen(_ reference: UInt32) -> Bool
    /// One text key the door's sequence passed, such as `Sound: DRSWoodGateHelgenOpen`.
    func sequenceDoorTextKey(_ name: String, from reference: UInt32)
    /// Each leaf's model-frame move from rest, or nil when the door left.
    func setSequenceDoorLeaves(_ deltas: [float4x4]?, for reference: UInt32)
}

/// One line of the doors panel.
nonisolated public struct SequenceDoorRow: Equatable, Sendable {
    public let reference: UInt32
    public let modelPath: String
    public let phase: SequenceDoorMotion.Phase

    public init(reference: UInt32, modelPath: String, phase: SequenceDoorMotion.Phase) {
        self.reference = reference
        self.modelPath = modelPath
        self.phase = phase
    }
}

public final class SequenceDoorCoordinator {
    final class Running {
        var door: CellSequenceDoor
        var motion: SequenceDoorMotion
        var needsPublish = true

        init(door: CellSequenceDoor, motion: SequenceDoorMotion) {
            self.door = door
            self.motion = motion
        }
    }

    weak var world: (any SequenceDoorWorld)?
    private(set) var running: [UInt32: Running] = [:]
    /// Off holds every door in the pose it has.
    public var isEnabled = true

    public init() {}

    public func attach(world: any SequenceDoorWorld) {
        self.world = world
    }

    /// Adopts new doors at their saved state and drops departed ones. A rebuilt cell
    /// brings a new pose buffer, and the door keeps moving into it.
    public func sync() {
        guard let world else { return }
        var seen = Set<UInt32>()
        for door in world.residentSequenceDoors() where seen.insert(door.reference).inserted {
            if let current = running[door.reference] {
                if current.door.pose !== door.pose {
                    current.door = door
                    current.needsPublish = true
                }
                continue
            }
            let motion = SequenceDoorMotion(
                open: world.sequenceDoorWantsOpen(door.reference), rig: door.rig
            )
            running[door.reference] = Running(door: door, motion: motion)
        }
        for reference in running.keys where !seen.contains(reference) {
            running.removeValue(forKey: reference)
            world.setSequenceDoorLeaves(nil, for: reference)
        }
    }

    /// Steps every door in reference order and publishes the ones that moved.
    public func tick(deltaTime: Float) {
        guard let world else { return }
        for reference in running.keys.sorted() {
            guard let entry = running[reference] else { continue }
            if isEnabled {
                let before = entry.motion
                let keys = entry.motion.step(
                    wantsOpen: world.sequenceDoorWantsOpen(reference),
                    deltaTime: deltaTime, rig: entry.door.rig
                )
                for key in keys {
                    world.sequenceDoorTextKey(key, from: reference)
                }
                entry.needsPublish = entry.needsPublish || entry.motion != before
            }
            guard entry.needsPublish else { continue }
            entry.needsPublish = false
            let rig = entry.door.rig
            let leaves = rig.leafTransforms(entry.motion.motion, at: entry.motion.time)
            entry.door.pose.publish(leaves.map { HKABonePose(transform: $0) })
            world.setSequenceDoorLeaves(rig.leafDeltas(leaves), for: reference)
        }
    }

    /// The `GetOpenState` code of a resident sequence door, or nil for any other
    /// reference. A door told to move before its next step already answers the move.
    public func openStateCode(of reference: UInt32) -> Int32? {
        guard let phase = running[reference]?.motion.phase else { return nil }
        guard
            let wantsOpen = world?.sequenceDoorWantsOpen(reference),
            wantsOpen != phase.isOpenSide
        else { return phase.openStateCode }
        return (wantsOpen ? SequenceDoorMotion.Phase.opening : .closing).openStateCode
    }

    /// One row per resident door, in reference order.
    public var rows: [SequenceDoorRow] {
        running.keys.sorted().compactMap { reference in
            running[reference].map {
                SequenceDoorRow(
                    reference: reference, modelPath: $0.door.modelPath, phase: $0.motion.phase
                )
            }
        }
    }
}
