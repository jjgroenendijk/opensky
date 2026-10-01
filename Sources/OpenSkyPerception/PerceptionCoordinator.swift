// The shell of the perception domain: owns the perception pass, chooses which
// resident actors observe, and answers the AI & Navigation detection section.
// The pass itself is `PerceptionRuntime`. See docs/engine/coordinators.md.

import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyPhysics
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
    /// The player, and nothing else: NPC-versus-NPC perception is out of scope.
    func perceptionTargets() -> [PerceptionTarget]
    func perceptionHasLineOfSight(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> Bool
}

nonisolated public enum PerceptionCore {
    /// Every living candidate the AI drives: hostile, fighting, or keeping a
    /// package. Perception for the rest would be work nobody can observe.
    public static func observers(from candidates: [PerceptionCandidate]) -> [PerceptionObserver] {
        candidates
            .filter { !$0.isDead && ($0.isHostile || $0.isEngaged || $0.hasPackage) }
            .map(\.observer)
    }
}

/// Without detection settings the runtime stays nil, and the panel reports
/// itself unavailable rather than showing a convincing zero.
@MainActor
public final class PerceptionCoordinator {
    public private(set) var runtime: PerceptionRuntime?
    weak var world: (any PerceptionSessionWorld)?

    public init() {}

    public func attach(world: any PerceptionSessionWorld) {
        self.world = world
    }

    public func wire(settings: DetectionSettings) {
        let runtime = PerceptionRuntime(settings: settings)
        self.runtime = runtime
        runtime.attach(world: self)
    }

    public func advance(by delta: Float) {
        runtime?.advance(by: delta)
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
        PerceptionCore.observers(from: world?.perceptionCandidates() ?? [])
    }

    public func perceptionTargets() -> [PerceptionTarget] {
        world?.perceptionTargets() ?? []
    }

    public func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        world?.perceptionHasLineOfSight(from: origin, to: destination) ?? true
    }
}

extension PerceptionCoordinator: PerceptionControlProviding {
    public var perceptionSnapshot: PerceptionControlSnapshot {
        guard let runtime else { return .unavailable }
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

    public func perceptionLines(for actor: ReferenceKey) -> [String] {
        runtime?.readout().pairs(involving: actor).map(\.summaryLine) ?? []
    }
}
