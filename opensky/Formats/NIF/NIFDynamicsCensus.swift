// Aggregate view over decoded collision models: what motion systems, layers,
// masses, and joints the shipped data actually uses. Item 15.2 takes its
// supported motion-system list from this, and item 15.6 its constraint list,
// rather than from what nif.xml says is representable.
//
// Counts, names, and block types only. Nothing here carries geometry or any
// other extract of the user's install (AGENTS.md Legal & IP).

import Foundation

/// One joint reduced to the two scene objects it binds. On a character
/// skeleton those names are bones.
nonisolated struct NIFConstraintBonePair: Hashable, Sendable {
    let type: String
    let bodyA: String
    let bodyB: String
}

/// Mass distribution over the bodies that carry one. Kilograms, as stored.
nonisolated struct NIFMassDistribution: Sendable {
    private(set) var bodyCount = 0
    private(set) var minimum = Float.greatestFiniteMagnitude
    private(set) var maximum = -Float.greatestFiniteMagnitude
    private(set) var total: Double = 0
    /// Power-of-ten bucket exponent -> body count, so `0` is 1 to 10 kg.
    /// Bodies at zero mass are counted separately by the census.
    private(set) var decades: [Int: Int] = [:]

    var mean: Float? {
        bodyCount > 0 ? Float(total / Double(bodyCount)) : nil
    }

    mutating func add(_ mass: Float) {
        guard mass.isFinite, mass > 0 else { return }
        bodyCount += 1
        minimum = min(minimum, mass)
        maximum = max(maximum, mass)
        total += Double(mass)
        decades[Int(log10(mass).rounded(.down)), default: 0] += 1
    }
}

nonisolated struct NIFDynamicsCensus: Sendable {
    private(set) var modelCount = 0
    private(set) var collisionBearingModelCount = 0
    private(set) var bodyCount = 0
    /// Bodies item 15.2 would integrate: simulated motion system, positive mass.
    private(set) var simulatedBodyCount = 0
    /// Bodies whose motion system says simulated but whose mass is zero, which
    /// is the combination a naive integrator divides by.
    private(set) var masslessSimulatedBodyCount = 0
    /// Raw `hkMotionType` byte -> body count.
    private(set) var motionSystemCounts: [UInt8: Int] = [:]
    /// Raw `hkQualityType` byte -> body count.
    private(set) var qualityCounts: [UInt8: Int] = [:]
    /// `SkyrimLayer` raw value from the rigid-body filter -> body count.
    private(set) var layerCounts: [UInt8: Int] = [:]
    /// `bhkCollisionObject` vs `bhkBlendCollisionObject` -> body count.
    private(set) var carrierCounts: [String: Int] = [:]
    private(set) var mass = NIFMassDistribution()
    private(set) var zeroMassBodyCount = 0
    /// Constraint block type name -> how many joints of it were decoded.
    private(set) var constraintTypeCounts: [String: Int] = [:]
    /// Distinct joint-to-bone-pair bindings, with how many models show each.
    private(set) var bonePairs: [NIFConstraintBonePair: Int] = [:]
    /// Constraint ends whose entity pointer named no decoded body.
    private(set) var unboundConstraintEndCount = 0
    /// Reachable block types the decoder does not read, by type.
    private(set) var unsupportedBlocks: [String: Int] = [:]
    private(set) var decodeFailureCount = 0
    /// Every decode failure with the model and block it came from, so a
    /// non-zero tally is diagnosable without re-running the sweep.
    private(set) var decodeFailures: [String] = []
    /// Model paths that did not parse at all, with the reason.
    private(set) var loadFailures: [String] = []
    /// Models whose census contributed a constraint, so the report can name
    /// where the ragdoll data lives.
    private(set) var constraintBearingModelPaths: [String] = []

    mutating func record(model: NIFCollisionModel, path: String) {
        modelCount += 1
        if !model.bodies.isEmpty {
            collisionBearingModelCount += 1
        }
        for body in model.bodies {
            record(body: body)
        }
        record(constraints: model, path: path)
        for (type, count) in model.unsupportedReachableBlocks {
            unsupportedBlocks[type, default: 0] += count
        }
        decodeFailureCount += model.decodeFailures.count
        decodeFailures += model.decodeFailures.map {
            "\(path) block \($0.block): \($0.message)"
        }
    }

    mutating func record(loadFailure: String, path: String) {
        modelCount += 1
        loadFailures.append("\(path): \(loadFailure)")
    }

    private mutating func record(body: NIFCollisionBody) {
        bodyCount += 1
        motionSystemCounts[body.dynamics.rawMotionSystem, default: 0] += 1
        qualityCounts[body.dynamics.rawQualityType, default: 0] += 1
        layerCounts[body.rigidBodyFilter.layer, default: 0] += 1
        carrierCounts[body.carrier.rawValue, default: 0] += 1
        if body.dynamics.isSimulated {
            simulatedBodyCount += 1
        }
        if body.dynamics.mass > 0 {
            mass.add(body.dynamics.mass)
        } else {
            zeroMassBodyCount += 1
            if body.dynamics.motionSystem?.isSimulated == true {
                masslessSimulatedBodyCount += 1
            }
        }
    }

    private mutating func record(constraints model: NIFCollisionModel, path: String) {
        let constraints = model.constraints
        guard !constraints.isEmpty else { return }
        constraintBearingModelPaths.append(path)
        for constraint in constraints {
            constraintTypeCounts[String(describing: constraint.type), default: 0] += 1
            let names = model.boneNames(of: constraint)
            unboundConstraintEndCount += [names.a, names.b].count(where: { $0 == nil })
            bonePairs[NIFConstraintBonePair(
                type: String(describing: constraint.type),
                bodyA: names.a ?? "<unbound>",
                bodyB: names.b ?? "<unbound>"
            ), default: 0] += 1
        }
    }
}
