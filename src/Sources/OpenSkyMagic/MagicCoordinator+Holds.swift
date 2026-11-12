// The held archetypes: Detect Life paints actors, Telekinesis floats a loose body, Grab
// Actor lifts an actor, and Guide lays a hazard trail. Each landing renews its hold;
// the rules live in `MagicHoldCore`. See docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

extension MagicCoordinator.HoldEffects {
    func performHold(_ action: MagicWorldAction) {
        let caster = action.caster ?? action.target.key
        let lifetime = MagicHoldCore.lifetime(duration: action.duration)
        switch action.archetype {
        case .detectLife:
            paintLife(action, caster: action.target.key, lifetime: lifetime)
        case .telekinesis:
            grabBody(caster: caster, effect: action.effect, lifetime: lifetime)
        case .grabActor:
            grabActor(action.target.key, caster: caster, effect: action.effect, lifetime: lifetime)
        case .guide:
            layGuideTrail(caster: action.target.key, effect: action.effect)
        default:
            break
        }
    }

    /// Ages every hold, steers what is held, and lets go of what no landing renewed.
    func advanceHolds(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        let (running, ended) = MagicHoldCore.advancing(coordinator.holds, by: delta)
        coordinator.holds = running
        for hold in ended {
            release(hold)
        }
        for hold in coordinator.holds {
            steer(hold, delta: delta)
        }
    }

    /// The body the player's Telekinesis holds: Papyrus `Game.GetPlayerGrabbedRef`.
    var playerGrabbedReference: ReferenceKey? {
        coordinator.holds.first { $0.kind == .telekinesis && $0.caster == .player }?.held.first
    }

    /// Whether a running Grab Actor holds `key`, which keeps it from acting.
    func isGrabbed(_ key: ReferenceKey) -> Bool {
        coordinator.holds.contains { $0.kind == .grabActor && $0.held.contains(key) }
    }

    // MARK: - Detect Life

    /// "Applies a visual effect to all valid targets in range." The range is the
    /// entry's area; a valid target passes the MGEF's own conditions as the subject.
    private func paintLife(_ action: MagicWorldAction, caster: ReferenceKey, lifetime: Float) {
        guard let shader = hitShader(of: action.effect) else { return }
        let radius = MagicAreaSettings.documentedDefaults.radius(ofArea: action.area)
        let painted = coordinator.world.livingActors(near: caster, radius: radius).filter { key in
            guard let holder = coordinator.world.actorValueHolder(for: key) else { return false }
            return coordinator
                .withEffects { $0.effectConditionsHold(action.effect, on: holder) } ?? false
        }
        let before = coordinator.holds.first { $0.kind == .detectLife && $0.caster == caster }?
            .held ?? []
        for key in painted where !before.contains(key) {
            coordinator.pendingCommands.append(.paintActor(
                key, shader: shader.form, plugin: shader.plugin, shown: true
            ))
        }
        for key in before where !painted.contains(key) {
            coordinator.pendingCommands.append(.paintActor(
                key, shader: shader.form, plugin: shader.plugin, shown: false
            ))
        }
        coordinator.holds.removeAll { $0.kind == .detectLife && $0.caster == caster }
        coordinator.holds.append(MagicHold(
            kind: .detectLife, caster: caster, effect: action.effect, remaining: lifetime,
            held: painted
        ))
    }

    /// The MGEF's hit shader and the plugin its link is written in.
    private func hitShader(of effect: ReferenceKey) -> (form: FormID, plugin: String)? {
        guard
            let resolved = coordinator.effects?.effects.effect(key: effect),
            let shader = resolved.effect.data?.hitShader
        else { return nil }
        return (shader, resolved.sourcePlugin)
    }

    // MARK: - Telekinesis

    /// "Applies the Telekinesis effect to the target object." The first landing picks
    /// the loose body under the aim; later landings keep holding it. A second
    /// Telekinesis, as from the other hand, finds the hands full: `sMagicTelekinesisNoRecast`.
    private func grabBody(caster: ReferenceKey, effect: ReferenceKey, lifetime: Float) {
        let existing = coordinator.holds.first { $0.kind == .telekinesis && $0.caster == caster }
        if let existing, !existing.held.isEmpty, existing.effect != effect {
            if caster == .player {
                coordinator.pendingCommands
                    .append(.notice(coordinator.texts.castNotices[.telekinesisNoRecast]))
            }
            return
        }
        if existing == nil || existing?.held.isEmpty == true {
            coordinator.holds.removeAll { $0.kind == .telekinesis && $0.caster == caster }
            let body = coordinator.world.telekinesisTarget(
                for: caster, within: coordinator.holdSettings.telekinesisReach
            )
            coordinator.holds.append(MagicHold(
                kind: .telekinesis, caster: caster, effect: effect, remaining: lifetime,
                held: body.map { [$0] } ?? []
            ))
            setHeldFlag(MagicArchetypeRule.telekinesisActorValue, on: caster, by: 1)
            if caster == .player, let body {
                coordinator.pendingCommands.append(.playerGrab(body, held: true))
            }
            return
        }
        coordinator.holds = MagicHoldCore.renewing(
            MagicHold(kind: .telekinesis, caster: caster, effect: effect, remaining: lifetime),
            in: coordinator.holds
        )
    }

    // MARK: - Grab Actor

    /// "Can pick up and throw selected NPC." The actor is held in front of the caster.
    private func grabActor(
        _ target: ReferenceKey, caster: ReferenceKey, effect: ReferenceKey, lifetime: Float
    ) {
        guard target != caster else { return }
        if coordinator.holds.contains(where: { $0.kind == .grabActor && $0.caster == caster }) {
            coordinator.holds = MagicHoldCore.renewing(
                MagicHold(kind: .grabActor, caster: caster, effect: effect, remaining: lifetime),
                in: coordinator.holds
            )
            return
        }
        coordinator.holds.append(MagicHold(
            kind: .grabActor, caster: caster, effect: effect, remaining: lifetime,
            held: [target]
        ))
        setHeldFlag(MagicArchetypeRule.grabbedActorValue, on: target, by: 1)
    }

    /// "Distance at which the target is held is based on the GrabActorOffset actor
    /// value of the caster", never nearer than `fMagicGrabActorMinDistance`.
    private func grabDistance(of caster: ReferenceKey) -> Float {
        let offset = coordinator.world.actorValueHolder(for: caster)
            .flatMap { coordinator.effects?.values.value(at: Self.grabActorOffsetValue, on: $0) } ??
            0
        return max(coordinator.holdSettings.grabActorMinDistance, offset)
    }

    /// `Grab Actor Offset` in the vanilla actor-value table.
    static let grabActorOffsetValue: Int32 = 160

    // MARK: - Guide

    /// "Creates a trail of Hazard objects from the caster to the nearest quest target."
    private func layGuideTrail(caster: ReferenceKey, effect: ReferenceKey) {
        guard let hazard = coordinator.associatedItem(of: effect) else { return }
        switch coordinator.world.guidePath(for: caster) {
        case .noMarker:
            if caster == .player {
                coordinator.pendingCommands
                    .append(.notice(coordinator.texts.castNotices[.guideNoMarker]))
            }
        case .noPath:
            if caster == .player {
                coordinator.pendingCommands
                    .append(.notice(coordinator.texts.castNotices[.guideNoPath]))
            }
        case let .path(points):
            let trail = MagicHoldCore.trail(
                along: points, spacing: coordinator.holdSettings.guideSpacing,
                limit: coordinator.holdSettings.guideWaypoints
            )
            for point in trail {
                coordinator.world.placeHazard(ReferenceKey(resolved: hazard), at: point)
            }
        }
    }

    // MARK: - Steering and release

    private func steer(_ hold: MagicHold, delta: Float) {
        guard
            let target = hold.held.first,
            let ray = coordinator.world.aimRay(of: hold.caster) else { return }
        switch hold.kind {
        case .telekinesis:
            guard let body = coordinator.world.heldBody(target) else { return }
            let distance = max(
                coordinator.holdSettings.telekinesisDistanceMin,
                MagicHoldCore.telekinesisHoldDistance
            )
            let impulse = MagicHoldCore.steeringImpulse(
                body, toward: ray.origin + ray.direction * distance, delta: delta,
                gravity: PhysicsStep.gravity
            )
            coordinator.world.pushBody(target, impulse: impulse)
        case .grabActor:
            coordinator.world.holdActor(
                target,
                at: ray.origin + ray.direction * grabDistance(of: hold.caster)
            )
        case .detectLife, .guide:
            break
        }
    }

    private func release(_ hold: MagicHold) {
        switch hold.kind {
        case .detectLife:
            guard let shader = hitShader(of: hold.effect) else { return }
            for key in hold.held {
                coordinator.pendingCommands.append(.paintActor(
                    key, shader: shader.form, plugin: shader.plugin, shown: false
                ))
            }
        case .telekinesis:
            setHeldFlag(MagicArchetypeRule.telekinesisActorValue, on: hold.caster, by: -1)
            if hold.caster == .player, let target = hold.held.first {
                coordinator.pendingCommands.append(.playerGrab(target, held: false))
            }
            guard
                let target = hold.held.first, let body = coordinator.world.heldBody(target),
                let ray = coordinator.world.aimRay(of: hold.caster)
            else { return }
            let throwVelocity = ray.direction * MagicHoldCore.telekinesisThrowSpeed
            coordinator.world.pushBody(target, impulse: (throwVelocity - body.velocity) * body.mass)
        case .grabActor:
            guard let target = hold.held.first else { return }
            setHeldFlag(MagicArchetypeRule.grabbedActorValue, on: target, by: -1)
            coordinator.world.holdActor(target, at: nil)
            if let ray = coordinator.world.aimRay(of: hold.caster) {
                coordinator.world.throwActor(
                    target,
                    along: ray.direction,
                    force: coordinator.holdSettings.grabActorThrowForce
                )
            }
        case .guide:
            break
        }
    }

    /// Raises or lowers a flag actor value by one, as a held effect would.
    private func setHeldFlag(_ index: Int32, on key: ReferenceKey, by change: Float) {
        guard let holder = coordinator.world.actorValueHolder(for: key) else { return }
        coordinator.effects?.values.addModifier(change, to: .temporary, at: index, on: holder)
    }
}
