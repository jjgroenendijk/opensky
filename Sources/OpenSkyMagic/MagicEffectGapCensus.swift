// Magic effects whose archetype the planner applies as nothing, so `openskycli gaps`
// can rank the archetypes still to build. Counts only.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct MagicEffectGapCensus: Equatable, Sendable {
    /// Archetype name -> effects of it, over every effect.
    public private(set) var archetypes: [String: Int] = [:]
    /// Archetype name -> effects of it that apply nothing.
    public private(set) var unapplied: [String: Int] = [:]
    public private(set) var unappliedTotal = 0
    public private(set) var effectTotal = 0
    /// Effects whose DATA did not decode, so no archetype is known.
    public private(set) var undecoded = 0

    public init(effects: [MagicEffect]) {
        for effect in effects {
            effectTotal += 1
            guard let data = effect.data else {
                undecoded += 1
                continue
            }
            archetypes[data.archetype.description, default: 0] += 1
            if !MagicEffectPlanner.applies(data) {
                unappliedTotal += 1
                unapplied[data.archetype.description, default: 0] += 1
            }
        }
    }

    /// Archetypes the planner applies, perk carriers aside.
    public var appliedArchetypeCount: Int {
        archetypes.count - unapplied.count
    }

    /// Archetypes with effects that apply nothing, most effects first.
    public var rankedUnapplied: [(name: String, count: Int)] {
        unapplied.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
