// The shell of the perception domain: owns the perception pass, chooses which
// resident actors observe, and answers the AI & Navigation detection section.
// The pass itself is `PerceptionRuntime`. See docs/engine/coordinators.md.

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPerceptionInterface
import OpenSkyPhysics
public import OpenSkyRenderCore
import simd

/// One resident actor that may observe, with the facts that decide whether it does.
nonisolated public struct PerceptionCandidate: Equatable, Sendable {
    public let observer: PerceptionObserver
    public let isDead: Bool
    public let isHostile: Bool
    /// In a fight right now, whatever its regard for the player.
    public let isEngaged: Bool
    /// Running a package the schedule selected.
    public let hasPackage: Bool

    public init(
        observer: PerceptionObserver,
        isDead: Bool,
        isHostile: Bool,
        isEngaged: Bool,
        hasPackage: Bool
    ) {
        self.observer = observer
        self.isDead = isDead
        self.isHostile = isHostile
        self.isEngaged = isEngaged
        self.hasPackage = hasPackage
    }
}

/// What the perception coordinator reads from the session.
@MainActor
public protocol PerceptionSessionWorld: AnyObject {
    func perceptionCandidates() -> [PerceptionCandidate]
    /// Builds only the candidates `isDue` asks for, given each actor's key and feet. The
    /// result lists every resident key, and the candidates built again this time; a key
    /// without a fresh candidate keeps its last one.
    func perceptionCandidates(
        isDue: (ReferenceKey, SIMD3<Float>) -> Bool
    ) -> (present: [ReferenceKey], fresh: [PerceptionCandidate])
    /// The player, and each NPC another NPC attacks on sight.
    func perceptionTargets() -> [PerceptionTarget]
    /// The observer and NPC target pairs to track.
    func perceptionActorPairs() -> [DetectionPairKey]
    func perceptionHasLineOfSight(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> Bool
}

extension PerceptionSessionWorld {
    /// A world without NPC foes tracks the player only.
    public func perceptionActorPairs() -> [DetectionPairKey] {
        []
    }

    /// Builds every candidate and keeps the due ones, for a world where one is cheap.
    public func perceptionCandidates(
        isDue: (ReferenceKey, SIMD3<Float>) -> Bool
    ) -> (present: [ReferenceKey], fresh: [PerceptionCandidate]) {
        let all = perceptionCandidates()
        return (
            present: all.map(\.observer.key),
            fresh: all.filter { isDue($0.observer.key, $0.observer.feet) }
        )
    }
}

nonisolated public enum PerceptionCore {
    /// Every living candidate the AI drives: hostile, fighting, or keeping a
    /// package. Perception for the rest would be work nobody can observe.
    public static func observers(from candidates: [PerceptionCandidate]) -> [PerceptionObserver] {
        candidates
            .filter { !$0.isDead && ($0.isHostile || $0.isEngaged || $0.hasPackage) }
            .map { candidate in
                var observer = candidate.observer
                observer.isAggressive = candidate.isHostile || candidate.isEngaged
                return observer
            }
    }
}

/// Without detection settings the runtime stays nil, and the readout reports
/// itself unavailable rather than showing a convincing zero.
@MainActor
public final class PerceptionCoordinator {
    public private(set) var runtime: PerceptionRuntime?
    let world: any PerceptionSessionWorld
    /// Each observer's banded refresh (`PerceptionCoordinator+Bands.swift`).
    var bandedRoster = PerceptionBandedRoster()

    public init(
        world: any PerceptionSessionWorld,
        settings: DetectionSettings?,
        stealthPoints: StealthPointSettings = .vanilla
    ) {
        self.world = world
        runtime = settings.map {
            PerceptionRuntime(settings: $0, stealthPoints: stealthPoints, world: self)
        }
    }

    /// - Returns: the Sneak skill uses earned by hiding during the steps run.
    public func advance(by delta: Float) -> [PerceptionCommand] {
        guard let runtime else { return [] }
        bandedRoster.waited += delta.isFinite ? max(delta, 0) : 0
        let steps = runtime.advance(by: delta)
        guard steps > 0 else { return [] }
        let seconds = Float(steps) * PerceptionRuntime.fixedStepSeconds
        return runtime.hiddenSneakers().map { target in
            .reportSneakSkillUse(runtime.settings.skillUsePerSecond.value * seconds, by: target)
        }
    }

    /// Every tracked pair plus every roster member's position, for condition
    /// evaluation.
    public func perceptionResolution() -> DetectionResolution {
        runtime?.resolution() ?? .empty
    }

    public func appendWorldOverlay(
        context: WorldOverlayFrameContext,
        to list: inout WorldOverlayDrawList
    ) {
        runtime?.appendWorldOverlay(context: context, to: &list)
    }
}

extension PerceptionCoordinator: PerceptionWorld {
    public func perceptionObservers() -> [PerceptionObserver] {
        PerceptionCore.observers(from: bandedCandidates())
    }

    /// The targets the observers were measured from, read once per roster refresh.
    public func perceptionTargets() -> [PerceptionTarget] {
        bandedRoster.takeTargets() ?? world.perceptionTargets()
    }

    public func perceptionActorPairs() -> [DetectionPairKey] {
        world.perceptionActorPairs()
    }

    public func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        world.perceptionHasLineOfSight(from: origin, to: destination)
    }
}

extension PerceptionCoordinator {
    func perceptionLines(for actor: ReferenceKey) -> [String] {
        runtime?.readout().pairs(involving: actor).map(\.summaryLine) ?? []
    }
}
