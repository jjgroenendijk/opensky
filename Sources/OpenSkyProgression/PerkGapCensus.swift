// What the perk records ask for that the engine never does: entry points no code
// reads, and entry-point functions the evaluator does not compute. `openskycli gaps`
// prints it. Counts only.

import Foundation
import OpenSkyFormatsESM
import OpenSkyProgressionInterface

nonisolated public struct PerkGapCensus: Equatable, Sendable {
    /// Entry-point effects per entry point, over every perk.
    public private(set) var entryPoints: [PerkEntryPoint: Int] = [:]
    /// Entry-point effects per function, over every perk.
    public private(set) var functions: [PerkFunction: Int] = [:]
    public private(set) var effectTotal = 0
    /// The graph variables `Set Boolean Graph Variable` effects name. The combat
    /// runtime writes each one while its perk applies.
    public private(set) var graphVariables: Set<String> = []

    public init(perks: [Perk]) {
        for perk in perks {
            for perkEffect in perk.effects {
                guard case let .entryPoint(effect)? = perkEffect.data else { continue }
                effectTotal += 1
                entryPoints[effect.entryPoint, default: 0] += 1
                functions[effect.function, default: 0] += 1
                if effect.entryPoint == .setBooleanGraphVariable {
                    graphVariables.formUnion(Self.text(of: perkEffect.functionData))
                }
            }
        }
    }

    private static func text(of data: PerkFunctionData?) -> [String] {
        switch data {
        case let .text(value)?: [value]
        case let .localizedText(.inline(value))?: [value]
        default: []
        }
    }

    /// Entry points the data uses that no engine code reads, most effects first.
    public var unreadEntryPoints: [(name: String, count: Int)] {
        Self.ranked(entryPoints.filter { !PerkEntryPoint.engineRead.contains($0.key) })
    }

    /// Functions neither `PerkEntryPointEvaluator` computes nor a choice reader carries
    /// out, most effects first.
    public var unsupportedFunctions: [(name: String, count: Int)] {
        Self.ranked(functions.filter {
            !PerkEntryPointEvaluator.supports($0.key) && !PerkEntryPointChoice.carries($0.key)
        })
    }

    private static func ranked(
        _ counts: [some CustomStringConvertible: Int]
    ) -> [(name: String, count: Int)] {
        counts.map { (name: $0.key.description, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
