// What an actor that watched a fight keeps doing after it ends. See
// docs/engine/package-schedules.md.

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

extension PackageCoordinator {
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

        init(settings: PackageSettings) {
            self.init(rememberSeconds: settings.sandbox.spectatorRememberSeconds)
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
}
