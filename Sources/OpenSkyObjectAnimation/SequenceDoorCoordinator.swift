// Moves each resident sequence door toward its saved open state: plays the `Open`
// or `Close` sequence, runs the text keys it passes, and moves the leaf collision.
// The open state itself is world state, written by activation and `SetOpen`.
// See docs/engine/object-animation.md#sequence-doors.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

/// What the door coordinator reads from the session.
public protocol SequenceDoorWorld: AnyObject {
    func residentSequenceDoors() -> [CellSequenceDoor]
    /// The door's open state: the plugin's, or the one a save, script, or activation
    /// wrote. A container lid is open while its container menu is.
    func sequenceDoorWantsOpen(_ door: CellSequenceDoor) -> Bool
}

public final class SequenceDoorCoordinator {
    final class Running {
        var door: CellSequenceDoor
        var motion: SequenceDoorMotion
        var needsPublish = true
        /// The billboards and lag bones of the mesh, when its rig adds them.
        var animator: NIFNodeAnimator?

        init(door: CellSequenceDoor, motion: SequenceDoorMotion) {
            self.door = door
            self.motion = motion
            animator = door.nodes?.nodes.map { NIFNodeAnimator(animation: $0.animation) }
        }
    }

    weak let world: (any SequenceDoorWorld)?
    private(set) var running: [UInt32: Running] = [:]
    /// Load doors swinging open for a transition. Nothing saves the swing.
    private var swinging: Set<UInt32> = []
    /// The camera billboards turn to; nil leaves them at rest.
    private let viewer: () -> NIFBillboard.Viewer?
    /// Off holds every door in the pose it has; billboards keep turning.
    public var isEnabled = true

    public init(
        world: any SequenceDoorWorld, viewer: @escaping () -> NIFBillboard.Viewer? = { nil }
    ) {
        self.world = world
        self.viewer = viewer
    }

    /// Adopts new doors at their saved state and drops departed ones. A rebuilt cell
    /// brings a new pose buffer, and the door keeps moving into it.
    public func sync() -> [SequenceDoorCommand] {
        guard let world else { return [] }
        var seen = Set<UInt32>()
        for door in world.residentSequenceDoors() where seen.insert(door.reference).inserted {
            if let current = running[door.reference] {
                if current.door.pose !== door.pose {
                    current.door = door
                    current.animator = door.nodes?.nodes
                        .map { NIFNodeAnimator(animation: $0.animation) }
                    current.needsPublish = true
                }
                continue
            }
            let motion = SequenceDoorMotion(
                open: world.sequenceDoorWantsOpen(door), rig: door.rig
            )
            running[door.reference] = Running(door: door, motion: motion)
        }
        let departed = running.keys.filter { !seen.contains($0) }.sorted()
        for reference in departed {
            running.removeValue(forKey: reference)
            swinging.remove(reference)
        }
        return departed.map { .setLeaves(nil, reference: $0) }
    }

    /// Steps every door in reference order and publishes the ones that moved.
    public func tick(deltaTime: Float) -> [SequenceDoorCommand] {
        guard let world else { return [] }
        var commands: [SequenceDoorCommand] = []
        for reference in running.keys.sorted() {
            guard let entry = running[reference] else { continue }
            if isEnabled {
                let before = entry.motion
                let swings = swinging.contains(reference)
                let keys = entry.motion.step(
                    wantsOpen: swings || world.sequenceDoorWantsOpen(entry.door),
                    deltaTime: deltaTime, rig: entry.door.rig
                )
                // The transition plays the door's sound already.
                if !swings {
                    commands += keys.map { .textKey($0, reference: reference) }
                }
                entry.needsPublish = entry.needsPublish || entry.motion != before
            }
            let rig = entry.door.rig
            if entry.door.nodes != nil {
                publishNodes(entry, deltaTime: isEnabled ? deltaTime : 0)
            }
            guard entry.needsPublish else { continue }
            entry.needsPublish = false
            let leaves = rig.leafTransforms(entry.motion.motion, at: entry.motion.time)
            if entry.door.nodes == nil {
                entry.door.pose.publish(leaves.map { HKABonePose(transform: $0) })
            }
            commands.append(.setLeaves(rig.leafDeltas(leaves), reference: reference))
        }
        return commands
    }

    /// Steps the mesh's lag bones, turns its billboards, and publishes leaves and nodes.
    private func publishNodes(_ entry: Running, deltaTime: Float) {
        guard let nodes = entry.door.nodes else { return }
        let placement = entry.door.placement
        entry.animator?.step(
            deltaTime: deltaTime, placement: NodeControllerCoordinator.transform(placement)
        )
        if let camera = viewer() {
            entry.animator?.face(camera.local(to: placement))
        }
        let leaves = entry.door.rig.leafTransforms(entry.motion.motion, at: entry.motion.time)
        let local = leaves.map { HKABonePose(transform: $0) }
        entry.door.pose.publish(nodes.bonePoses(graph: local, animator: entry.animator))
    }

    /// A load door the player used swings open while the transition holds.
    public func swingOpen(_ reference: UInt32) {
        guard running[reference]?.door.kind == .loadDoor else { return }
        swinging.insert(reference)
    }

    /// The `GetOpenState` code of a resident sequence door, or nil for any other
    /// reference. A door told to move before its next step already answers the move.
    public func openStateCode(of reference: UInt32) -> Int32? {
        guard let entry = running[reference] else { return nil }
        let phase = entry.motion.phase
        guard
            let wantsOpen = world?.sequenceDoorWantsOpen(entry.door),
            wantsOpen != phase.isOpenSide
        else { return phase.openStateCode }
        return (wantsOpen ? SequenceDoorMotion.Phase.opening : .closing).openStateCode
    }
}
