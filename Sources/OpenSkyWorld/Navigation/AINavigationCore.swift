// The pure rules of the AI & Navigation panel: the actor list order, which
// actor the selection resolves to, and the names the panel prints.

import OpenSkyFormatsESM
import simd

/// One resident actor as the session reports it, before the camera distance.
nonisolated public struct AIActorCandidate: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let feet: SIMD3<Float>
    public let isDead: Bool

    public init(key: ReferenceKey, name: String, feet: SIMD3<Float>, isDead: Bool) {
        self.key = key
        self.name = name
        self.feet = feet
        self.isDead = isDead
    }
}

nonisolated public struct AICameraPose: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let forward: SIMD3<Float>

    public init(position: SIMD3<Float>, forward: SIMD3<Float>) {
        self.position = position
        self.forward = forward
    }
}

nonisolated public enum AINavigationCore {
    /// How far the move-to-point pick reaches, world units. Whiterun's market
    /// is a couple of thousand units across; the use-key distance could only
    /// send an actor to its own feet. The broad phase searches the ray's
    /// bounds, so it is no larger than it needs to be.
    public static let pickDistance: Float = 4096

    /// Nearest the camera first, ties broken by key.
    public static func options(
        _ candidates: [AIActorCandidate],
        eye: SIMD3<Float>
    ) -> [AIActorOption] {
        candidates
            .map {
                AIActorOption(
                    key: $0.key,
                    name: $0.name,
                    distance: simd_distance($0.feet, eye),
                    isDead: $0.isDead
                )
            }
            .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
    }

    /// The chosen actor while it is still resident, else the nearest one.
    public static func resolve(
        _ chosen: ReferenceKey?,
        in actors: [AIActorOption]
    ) -> ReferenceKey? {
        if let chosen, actors.contains(where: { $0.key == chosen }) {
            return chosen
        }
        return actors.first?.key
    }

    public static func name(of key: ReferenceKey?, in actors: [AIActorOption]) -> String {
        guard let key else { return "—" }
        return actors.first { $0.key == key }?.name ?? key.description
    }

    /// The readout for a registered actor that no package won. That is a real
    /// outcome, not a missing readout.
    public static func emptyPackageReadout(_ actor: ReferenceKey) -> PackageActorReadout {
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
