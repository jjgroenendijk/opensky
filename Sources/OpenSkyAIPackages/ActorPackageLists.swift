// The package lists of an actor's AI Packages tab, and the situations that pick
// an override list (<https://ck.uesp.net/wiki/AI_Packages_Tab>).

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

/// A code-driven behaviour that suspends the actor's usual package choice. A
/// valid package from the matching override list runs in its place.
nonisolated public enum PackageSituation: String, CaseIterable, Sendable {
    /// The actor sees a fight it does not join.
    case spectator
    case observeDeadBody
    /// A guard package warns a trespasser.
    case guardWarn
    case combat
}

nonisolated public struct ActorPackageLists: Equatable, Sendable {
    /// The AI Package List, evaluated first.
    public var own: [FormID]
    /// Evaluated when no package of `own` is valid.
    public var defaults: [FormID]
    public var overrides: [PackageSituation: [FormID]]

    public init(
        own: [FormID], defaults: [FormID] = [], overrides: [PackageSituation: [FormID]] = [:]
    ) {
        self.own = own
        self.defaults = defaults
        self.overrides = overrides
    }
}

/// What the situation scan reads of one loaded actor.
nonisolated public struct PackageSituationObservation: Equatable, Sendable {
    public let key: ReferenceKey
    public let position: SIMD3<Float>
    public let isDead: Bool
    public let isFighting: Bool

    public init(key: ReferenceKey, position: SIMD3<Float>, isDead: Bool, isFighting: Bool) {
        self.key = key
        self.position = position
        self.isDead = isDead
        self.isFighting = isFighting
    }
}

/// Which situation each actor is in, from where the others stand. The radii are
/// OpenSky's: the wiki names the behaviours but not their ranges.
nonisolated public enum PackageSituationScan {
    public static let spectatorRadius: Float = 2048
    public static let deadBodyRadius: Float = 1024

    public static func situations(
        of actors: [ReferenceKey], observations: [PackageSituationObservation]
    ) -> [ReferenceKey: PackageSituation] {
        let byKey = Dictionary(
            observations.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var result: [ReferenceKey: PackageSituation] = [:]
        for actor in actors {
            guard let seen = byKey[actor], !seen.isDead else { continue }
            if seen.isFighting {
                result[actor] = .combat
            } else if
                observations.contains(where: {
                    $0.key != actor && $0.isFighting && !$0.isDead
                        && simd_distance($0.position, seen.position) <= spectatorRadius
                })
            {
                result[actor] = .spectator
            } else if
                observations.contains(where: {
                    $0.key != actor && $0.isDead
                        && simd_distance($0.position, seen.position) <= deadBodyRadius
                })
            {
                result[actor] = .observeDeadBody
            }
        }
        return result
    }
}
