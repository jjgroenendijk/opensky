// `AINavigationControlProviding` conformance for the M16 gate panel (issue
// #203, roadmap item 16.8): the actor selection every section of
// `World > AI & Navigation` shares, and the mover and package state that answer
// for it.
//
// Nothing here invents an accounting. The actor list is the same
// `combatActors()` observation the fight steps against, so a name and a distance
// read the same in both panels; the mover state is 16.4's own readout; the
// package state is 16.5's own readout; the crosshair point is the same static
// raycast the HUD target uses.
//
// The one deliberate difference from the HUD target: this ray is not gated on a
// player-controlled camera and reaches much further. Picking a point for an NPC
// to walk to is an inspection, not a use key — a developer flying over Whiterun
// to send a guard across the market is exactly the session this destination is
// for, and 192 units is the arm's length a use key needs, not the distance a
// person aims across a city.

import AppKit
import simd

/// The gate panel's shared selection and its last outcome line. Extensions
/// cannot add stored properties, so it lives as one value on
/// `GameViewController`.
struct AINavigationBridgeState {
    /// The actor the destination acts on, or nil to follow the nearest resident
    /// one. Nil is the starting state and the state the selector returns to
    /// when the chosen actor stops being resident.
    var selectedActor: ReferenceKey?
    var lastActionText = "Select an actor, then move it, or watch its schedule."
    /// The last crosshair pick, keyed by the camera pose it was taken from.
    ///
    /// The pick is a raycast whose bounds span the whole 4,096-unit ray, which
    /// is a far wider broad-phase query than the HUD's arm's-length one, and
    /// six panel sections each read the snapshot twice a second. Keying it on
    /// the pose means a session inspecting a stationary scene pays for one
    /// raycast rather than a dozen a second, and a moving camera pays what it
    /// would have anyway.
    var pick: AICrosshairPick?
}

/// One crosshair raycast and the camera pose it was taken from.
struct AICrosshairPick: Equatable {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let hit: InteractionRayHit?
}

extension GameViewController: AINavigationControlProviding {
    /// How far the move-to-point pick reaches, world units. Whiterun's market
    /// is a couple of thousand units across, and a pick that stopped at the
    /// use-key distance could only ever send an actor to its own feet. Not
    /// larger than it needs to be: the ray's bounds are what the broad phase
    /// searches, and they grow with it.
    static let aiPickDistance: Float = 4096

    var aiNavigationSnapshot: AINavigationSnapshot {
        guard streamer != nil else { return .unavailable }
        let actors = aiActorOptions()
        let selected = resolvedAIActor(in: actors)
        return AINavigationSnapshot(
            isAvailable: true,
            actors: actors,
            selectedActor: selected,
            selectedActorName: aiActorName(selected, in: actors),
            movement: selected.flatMap { key in
                streamer?.npcMovementReadouts().first { $0.actor == key }
            },
            moverCount: streamer?.npcMovement.activeMoverCount ?? 0,
            moverLimit: NPCMovementRuntime.maximumSimultaneousMovers,
            package: selected.flatMap { key in
                packageReadouts().first { $0.actor == key }
            },
            packagedActorCount: packages.registeredActors.count,
            crosshairPoint: aiCrosshairPoint(),
            selectedActorIsHostile: selected.map { combatHostility(of: $0) == .hostile }
                ?? false,
            lastActionText: aiNavigation.lastActionText
        )
    }

    var selectedAIActorIsHostile: Bool {
        get {
            guard let key = resolvedAIActor(in: aiActorOptions()) else { return false }
            return combatHostility(of: key) == .hostile
        }
        set {
            let actors = aiActorOptions()
            guard let key = resolvedAIActor(in: actors) else {
                aiNavigation.lastActionText = "Cannot set hostility: no resident actor."
                return
            }
            setCombatHostility(newValue ? .hostile : .neutral, on: key)
            let regard = newValue ? "hostile" : "neutral"
            aiNavigation.lastActionText =
                "\(aiActorName(key, in: actors)) is now \(regard)."
        }
    }

    var selectedAIActor: ReferenceKey? {
        get { resolvedAIActor(in: aiActorOptions()) }
        set {
            aiNavigation.selectedActor = newValue
            let actors = aiActorOptions()
            aiNavigation.lastActionText =
                "Selected \(aiActorName(resolvedAIActor(in: actors), in: actors))."
        }
    }

    func selectAIActorFromCrosshair() {
        guard let streamer, let reference = crosshairReference() else {
            aiNavigation.lastActionText = "Cannot select: the crosshair is not on anything."
            return
        }
        guard
            let entry = streamer.residentActorEntries().first(where: { $0.formID == reference })
        else {
            aiNavigation.lastActionText =
                "Cannot select: \(reference) under the crosshair is not an actor."
            return
        }
        selectedAIActor = entry.key
    }

    func moveSelectedAIActorToCrosshair() {
        let actors = aiActorOptions()
        guard let streamer, let key = resolvedAIActor(in: actors) else {
            aiNavigation.lastActionText = "Cannot move: no resident actor to act on."
            return
        }
        guard let point = aiCrosshairPoint() else {
            aiNavigation.lastActionText = "Cannot move: the crosshair is not on anything."
            return
        }
        aiNavigation.lastActionText = AINavigationReadout.moveResultText(
            streamer.moveActor(key, to: point),
            actor: aiActorName(key, in: actors)
        )
    }

    func stopSelectedAIActor() {
        let actors = aiActorOptions()
        guard let streamer, let key = resolvedAIActor(in: actors) else {
            aiNavigation.lastActionText = "Cannot stop: no resident actor to act on."
            return
        }
        let name = aiActorName(key, in: actors)
        aiNavigation.lastActionText = streamer.stopActor(key)
            ? "Stopped \(name) where it stands."
            : "\(name) had no mover to stop."
    }

    func reevaluateSelectedAIActorPackage() {
        let actors = aiActorOptions()
        guard let key = resolvedAIActor(in: actors) else {
            aiNavigation.lastActionText = "Cannot reevaluate: no resident actor to act on."
            return
        }
        let name = aiActorName(key, in: actors)
        guard packages.registeredActors[key] != nil else {
            aiNavigation.lastActionText = "\(name) has no package stack registered."
            return
        }
        resumePackage(for: key)
        let selected = packageReadouts().first { $0.actor == key }
        aiNavigation.lastActionText = "Reevaluated \(name): "
            + AIPackageReadout.selectionText(for: selected ?? Self.emptyPackageReadout(key))
    }

    // MARK: - Private

    /// Every resident actor, nearest the camera first, named exactly as the
    /// combat readout names it.
    private func aiActorOptions() -> [AIActorOption] {
        guard let renderer else { return [] }
        let eye = renderer.freeFlyCamera.position
        return combatActors()
            .map { actor in
                AIActorOption(
                    key: actor.key,
                    name: actor.name,
                    distance: simd_distance(actor.feet, eye),
                    isDead: actor.isDead
                )
            }
            .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
    }

    /// The chosen actor while it is still resident, else the nearest one.
    private func resolvedAIActor(in actors: [AIActorOption]) -> ReferenceKey? {
        if let chosen = aiNavigation.selectedActor, actors.contains(where: { $0.key == chosen }) {
            return chosen
        }
        return actors.first?.key
    }

    private func aiActorName(_ key: ReferenceKey?, in actors: [AIActorOption]) -> String {
        guard let key else { return "—" }
        return actors.first { $0.key == key }?.name ?? key.description
    }

    /// Where the crosshair meets world geometry, or nil when it meets nothing
    /// inside the pick distance.
    private func aiCrosshairPoint() -> SIMD3<Float>? {
        aiCrosshairHit()?.position
    }

    private func crosshairReference() -> FormID? {
        aiCrosshairHit()?.reference
    }

    private func aiCrosshairHit() -> InteractionRayHit? {
        guard
            let renderer,
            let streamer,
            let ray = InteractionRay(
                origin: renderer.freeFlyCamera.position,
                direction: renderer.freeFlyCamera.forward,
                maximumDistance: Self.aiPickDistance
            )
        else { return nil }
        if
            let pick = aiNavigation.pick,
            pick.origin == ray.origin, pick.direction == ray.direction
        {
            return pick.hit
        }
        let shapes = streamer.collisionCandidates(overlapping: ray.bounds)
        let hit = InteractionRaycaster.nearestHit(ray: ray, shapes: shapes)
        aiNavigation.pick = AICrosshairPick(
            origin: ray.origin, direction: ray.direction, hit: hit
        )
        return hit
    }

    /// What the reevaluate line says when the runtime registered the actor but
    /// no package won, which is a real outcome rather than a missing readout.
    private static func emptyPackageReadout(_ actor: ReferenceKey) -> PackageActorReadout {
        PackageActorReadout(
            actor: actor,
            actorBase: FormID(0),
            currentPackage: nil,
            editorID: nil,
            schedule: nil,
            procedure: nil,
            lastEvaluationGameSeconds: nil
        )
    }
}
