// Session wiring for the perception pass: builds the runtime over the
// provider's detection GMSTs and advances it on the paused-aware world delta.
// It runs after NPC movement and the combat loop, because it reads where actors
// ended up this frame and which of them are hostile.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
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
    func wirePerception(provider: any WorldDataProviding, renderer: Renderer) {
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
            // After the pass, so a trespass noticed on arrival is judged
            // against detection state this frame produced (issue #504).
            self?.advanceCrimeTrespass()
            // After the trespass, so a bounty charged this frame is one the
            // guards see this frame (issue #505).
            self?.advanceGuardResponse()
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak self] context, list in
                self?.perception.runtime?.appendWorldOverlay(context: context, to: &list)
            }
    }
}

// MARK: - The world seam

extension GameViewController: PerceptionWorld {
    /// Every living resident actor the AI drives: hostile to the player, or
    /// running a selected package. Perception for the rest would be work
    /// nobody can observe.
    func perceptionObservers() -> [PerceptionObserver] {
        let packaged = Set(packageReadouts().filter { $0.currentPackage != nil }.map(\.actor))
        return combatActors().compactMap { actor in
            guard !actor.isDead else { return nil }
            guard
                combatHostility(of: actor.key) == .hostile
                || combat.loop?.phase(of: actor.key)?.isEngaged == true
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
