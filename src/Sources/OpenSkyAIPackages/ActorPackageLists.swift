// The package lists of an actor's AI Packages tab, and the situations that pick
// an override list (<https://ck.uesp.net/wiki/AI_Packages_Tab>).

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
import simd

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

/// A spectator keeps watching for `fAISpectatorRememberThreatTimer` seconds after the
/// fight near it ends.
nonisolated public struct SpectatorMemory: Equatable, Sendable {
    /// `fAISpectatorRememberThreatTimer`.
    public var rememberSeconds: Float = 5
    /// Seconds each recent spectator has gone without a fight near it.
    public private(set) var quietSeconds: [ReferenceKey: Float] = [:]

    public init(rememberSeconds: Float = 5) {
        self.rememberSeconds = rememberSeconds
    }

    /// `situations` with each remembered spectator kept a spectator, after `delta` seconds.
    public mutating func remembering(
        _ situations: [ReferenceKey: PackageSituation], actors: [ReferenceKey], delta: Float
    ) -> [ReferenceKey: PackageSituation] {
        var result = situations
        for actor in actors {
            if situations[actor] == .spectator {
                quietSeconds[actor] = 0
                continue
            }
            guard let quiet = quietSeconds[actor] else { continue }
            let now = quiet + max(0, delta)
            if situations[actor] == nil, now < rememberSeconds {
                quietSeconds[actor] = now
                result[actor] = .spectator
            } else {
                quietSeconds[actor] = nil
            }
        }
        return result
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
