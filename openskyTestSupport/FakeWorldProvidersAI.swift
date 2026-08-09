// The AI-and-navigation half of the world-provider fake (issues #422, #202 and
// #203), in its own file so `FakeWorldProviders` stays inside the type-length
// cap — the same split `FakeWorldProvidersCombat.swift` made.
//
// Three seams specified one milestone item at a time and consumed all at once by
// the `World > AI & Navigation` panel the M16 gate ships. Every answer is a
// plain stored value and every action is recorded rather than performed, which
// is what lets a panel test drive the whole destination with no renderer, no
// window and no game data.

@testable import opensky

/// The world-overlay half of the fake's stored state (issue #422).
struct FakeAIOverlayState {
    var navmesh = false
    var path = false
    var detection = false
    var stats = WorldOverlayDrawStats()
}

extension FakeWorldProviders {
    var navmeshOverlayEnabled: Bool {
        get { aiOverlay.navmesh }
        set { aiOverlay.navmesh = newValue }
    }

    var pathOverlayEnabled: Bool {
        get { aiOverlay.path }
        set { aiOverlay.path = newValue }
    }

    var detectionOverlayEnabled: Bool {
        get { aiOverlay.detection }
        set { aiOverlay.detection = newValue }
    }

    var aiOverlaySnapshot: AIOverlayControlSnapshot {
        AIOverlayControlSnapshot(
            navmeshOverlayEnabled: aiOverlay.navmesh,
            pathOverlayEnabled: aiOverlay.path,
            detectionOverlayEnabled: aiOverlay.detection,
            stats: aiOverlay.stats
        )
    }
}

/// The perception half of the fake's stored state (issue #202).
struct FakePerceptionState {
    var snapshot = PerceptionControlSnapshot.unavailable
    /// Canned per-actor pair lines, keyed by the actor the panel asks about.
    var lines: [ReferenceKey: [String]] = [:]
}

extension FakeWorldProviders {
    var perceptionSnapshot: PerceptionControlSnapshot {
        perception.snapshot
    }

    func perceptionLines(for actor: ReferenceKey) -> [String] {
        perception.lines[actor] ?? []
    }
}

/// The gate panel's selection half of the fake's stored state (issue #203).
struct FakeAINavigationState {
    var snapshot = AINavigationSnapshot.unavailable
    var isHostile = false
    /// Every action the panel asked for, in order, so a gate can assert that a
    /// button sent exactly what it claimed to.
    var crosshairSelectCount = 0
    var moveRequestCount = 0
    var stopRequestCount = 0
    var reevaluateCount = 0
}

extension FakeWorldProviders {
    var aiNavigationSnapshot: AINavigationSnapshot {
        aiNavigation.snapshot
    }

    var selectedAIActor: ReferenceKey? {
        get { aiNavigation.snapshot.selectedActor }
        set { aiNavigation.snapshot = Self.selecting(newValue, in: aiNavigation.snapshot) }
    }

    var selectedAIActorIsHostile: Bool {
        get { aiNavigation.isHostile }
        set { aiNavigation.isHostile = newValue }
    }

    func selectAIActorFromCrosshair() {
        aiNavigation.crosshairSelectCount += 1
    }

    func moveSelectedAIActorToCrosshair() {
        aiNavigation.moveRequestCount += 1
    }

    func stopSelectedAIActor() {
        aiNavigation.stopRequestCount += 1
    }

    func reevaluateSelectedAIActorPackage() {
        aiNavigation.reevaluateCount += 1
    }

    /// Rebuilds the snapshot around a new selection, exactly as the live
    /// provider does: the name follows the key rather than being set apart from
    /// it, so a test cannot assert on a pairing the app could never produce.
    private static func selecting(
        _ key: ReferenceKey?,
        in snapshot: AINavigationSnapshot
    ) -> AINavigationSnapshot {
        AINavigationSnapshot(
            isAvailable: snapshot.isAvailable,
            actors: snapshot.actors,
            selectedActor: key,
            selectedActorName: snapshot.actors.first { $0.key == key }?.name ?? "—",
            movement: snapshot.movement,
            moverCount: snapshot.moverCount,
            moverLimit: snapshot.moverLimit,
            package: snapshot.package,
            packagedActorCount: snapshot.packagedActorCount,
            crosshairPoint: snapshot.crosshairPoint,
            selectedActorIsHostile: snapshot.selectedActorIsHostile,
            lastActionText: snapshot.lastActionText
        )
    }
}
