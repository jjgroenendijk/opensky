// Session wiring for the perception pass (issue #202, roadmap item 16.6):
// builds the runtime over the provider's detection GMSTs, advances it on the
// same paused-aware world delta everything else takes, and registers its world
// overlay.
//
// AppKit stays in this controller satellite; the pass, the formula, the pair
// states and the readout are all engine types that build into `openskycli` and
// are testable without a window.
//
// Ordering: perception is advanced *after* NPC movement and the combat loop,
// because it reads where actors ended up this frame and which of them are
// hostile. A pass that ran first would describe the previous frame's world.

import AppKit
import simd

/// Perception state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct PerceptionBridgeState {
    /// The pass, built by `wirePerception` when the provider can supply
    /// detection settings. Nil without game data, and then the panel reports
    /// itself unavailable rather than showing a convincing zero.
    var runtime: PerceptionRuntime?
}

extension GameViewController {
    /// Builds the perception pass over the provider's detection GMSTs.
    func wirePerception(provider: any CellSceneProvider, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.detectionSettings else {
            return
        }
        let runtime = PerceptionRuntime(settings: settings)
        perception.runtime = runtime
        runtime.attach(world: self)
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advanceWorld?(delta)
            self?.perception.runtime?.advance(by: delta)
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak self] context, list in
                self?.perception.runtime?.appendWorldOverlay(context: context, to: &list)
            }
    }
}

// MARK: - The world seam

extension GameViewController: PerceptionWorld {
    /// Every resident actor the AI is driving.
    ///
    /// "Driving" is the session's definition and is deliberately narrow: an
    /// actor is an observer when it is hostile to the player, or when the
    /// package runtime has selected a package for it. Those are exactly the
    /// actors something in this engine is already simulating, and simulating
    /// perception for the rest would be work nobody can observe. A dead actor
    /// observes nothing whatever else it carries.
    func perceptionObservers() -> [PerceptionObserver] {
        let packaged = Set(packageReadouts().filter { $0.currentPackage != nil }.map(\.actor))
        return combatActors().compactMap { actor in
            guard !actor.isDead else { return nil }
            guard
                actor.key == combat.runtime?.devTarget
                || combatHostility(of: actor.key) == .hostile
                || packaged.contains(actor.key)
            else { return nil }
            return PerceptionObserver(
                key: actor.key,
                feet: actor.feet,
                eye: actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0)),
                facing: actor.facing,
                isExterior: streamer?.interiorScene == nil,
                name: actor.name
            )
        }
    }

    /// The player, and nothing else.
    ///
    /// NPC-versus-NPC perception is explicitly out of 16.6's scope beyond what
    /// 16.7's combat needs, and the target seam is a list precisely so 16.7 can
    /// widen it without touching the pass.
    func perceptionTargets() -> [PerceptionTarget] {
        guard let renderer else { return [] }
        let status = renderer.locomotion.status
        let plan = status.lastPlan
        let isMoving = simd_length_squared(plan.horizontalDisplacement) > 0
        return [PerceptionTarget(
            key: .player,
            feet: status.feetPosition,
            eye: status.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            gait: isMoving ? status.gait : nil,
            isSneaking: status.gait == .sneak,
            equippedWeight: 0,
            name: "Player"
        )]
    }

    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        guard let streamer else { return true }
        let offset = destination - origin
        let distance = simd_length(offset)
        guard
            distance.isFinite, distance > 0,
            let ray = InteractionRay(
                origin: origin, direction: offset, maximumDistance: distance
            )
        else { return true }
        let shapes = streamer.staticCollisionCandidates(overlapping: ray.bounds)
        return InteractionRaycaster.nearestHit(ray: ray, shapes: shapes) == nil
    }
}

// MARK: - The panel seam

extension GameViewController: PerceptionControlProviding {
    var perceptionSnapshot: PerceptionControlSnapshot {
        guard let runtime = perception.runtime else { return .unavailable }
        return PerceptionControlSnapshot(
            readout: runtime.readout(),
            settings: runtime.settings.report.map {
                DetectionSettingReadout(
                    editorID: $0.editorID,
                    value: $0.setting.value,
                    source: $0.setting.source
                )
            }
        )
    }

    func perceptionLines(for actor: ReferenceKey) -> [String] {
        guard let runtime = perception.runtime else { return [] }
        return runtime.readout().pairs(involving: actor).map(\.summaryLine)
    }

    /// The perception seam for condition evaluation (issue #202): every tracked
    /// pair plus every roster member's position.
    func perceptionResolution() -> DetectionResolution {
        perception.runtime?.resolution() ?? .empty
    }
}
