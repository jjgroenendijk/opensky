// The `--detection-overlay` half of `render` (issue #202), split out like the
// reporting tail: a headless perception pass over one built cell, so the view
// cones can be seen in an offscreen frame without launching the app.
//
// The target is a stand-in rather than the player: there is no player in a CLI
// render. It is placed two hundred units in front of the lowest-keyed actor,
// walking, so at least one cone is always lit and at least one memory line
// always points somewhere — a capture where nothing was ever perceived is not
// evidence that the pass works. Every cone drawn is a real ACHR's real
// placement and facing.

import Foundation
import simd

/// A `PerceptionWorld` over one render's built cells. Line of sight goes
/// through the same exact ray and the same per-cell broadphase the app uses.
@MainActor
final class CellScenePerceptionWorld: PerceptionWorld {
    private let observers: [PerceptionObserver]
    private let target: PerceptionTarget
    private let collision: [StaticCollisionSet]

    /// How far in front of the anchor actor the stand-in target stands, world
    /// units — inside its cone and well inside its range.
    static let targetStandoff: Float = 200

    init(scenes: [CellScene]) {
        collision = scenes.map(\.staticCollision)
        observers = scenes
            .flatMap { $0.references.sortedEntries() }
            .compactMap { entry in
                guard let actor = entry.placedActor else { return nil }
                return PerceptionObserver(
                    key: entry.key,
                    feet: actor.placement.position,
                    facing: actor.placement.rotation.z,
                    isExterior: true,
                    name: entry.formID.description
                )
            }
            .sorted { $0.key < $1.key }
        let anchor = observers.first
        let heading = anchor.map { SIMD3($0.heading.x, $0.heading.y, 0) } ?? SIMD3<Float>()
        target = PerceptionTarget(
            key: .player,
            feet: (anchor?.feet ?? SIMD3<Float>()) + heading * Self.targetStandoff,
            gait: .walk,
            name: "Stand-in target"
        )
    }

    var observerCount: Int {
        observers.count
    }

    func perceptionObservers() -> [PerceptionObserver] {
        observers
    }

    func perceptionTargets() -> [PerceptionTarget] {
        [target]
    }

    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        let offset = destination - origin
        let distance = simd_length(offset)
        guard
            distance > 0,
            let ray = InteractionRay(
                origin: origin, direction: offset, maximumDistance: distance
            )
        else { return true }
        return collision.allSatisfy { set in
            InteractionRaycaster.nearestHit(
                ray: ray, shapes: set.candidates(overlapping: ray.bounds)
            ) == nil
        }
    }
}

extension RenderCommand {
    /// Fixed steps run before the frame, so the levels have converged and the
    /// cones are drawn in the colour they settle at. Two seconds.
    static let detectionWarmupSteps = 120

    /// A warmed perception pass over `scenes`, or nil when no ACHR is placed in
    /// any of them — which is a real answer for an empty stretch of Tamriel and
    /// is reported rather than drawn as an empty overlay.
    @MainActor
    static func makeDetectionRuntime(
        _ scenes: [CellScene],
        settings: DetectionSettings
    ) -> (runtime: PerceptionRuntime, world: CellScenePerceptionWorld)? {
        let world = CellScenePerceptionWorld(scenes: scenes)
        guard world.observerCount > 0 else { return nil }
        let runtime = PerceptionRuntime(settings: settings, world: world)
        for _ in 0 ..< detectionWarmupSteps {
            runtime.advance(by: PerceptionRuntime.fixedStepSeconds)
        }
        return (runtime, world)
    }

    /// The pass `--detection-overlay` draws, warmed and reported, or nil when
    /// the built cells hold no actor to observe with.
    @MainActor
    static func warmedDetection(
        _ scenes: [CellScene],
        context: CLIContext
    ) -> (runtime: PerceptionRuntime, world: CellScenePerceptionWorld)? {
        let detection = makeDetectionRuntime(
            scenes,
            settings: DetectionSettings.resolve(
                store: GameSettingLoader.load(root: context.root)
            )
        )
        guard let detection else {
            print("[WARNING] detection overlay: no ACHR is placed in the built cells")
            return nil
        }
        return detection
    }

    /// Probe-stable evidence line for the pass behind the drawn cones.
    static func printDetectionStats(_ runtime: PerceptionRuntime) {
        let readout = runtime.readout()
        print(
            "[INFO] detection: \(readout.observerCount) observers, "
                + "\(readout.pairs.count) pairs, \(readout.droppedPairCount) dropped, "
                + "\(readout.lineOfSightQueryCount) rays"
        )
        for row in readout.pairs.prefix(4) {
            print("[INFO] \(row.summaryLine)")
        }
    }
}
