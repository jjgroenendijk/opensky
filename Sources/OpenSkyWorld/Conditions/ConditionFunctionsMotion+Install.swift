// The registrations for the motion facts in ConditionFunctionsMotion.swift.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

nonisolated extension ConditionFunctions {
    public static func installMotion(_ registry: inout ConditionFunctionRegistry) {
        registry
            .register(ConditionFunction(index: 6, name: "GetPos", parameter1: .integer) { call in
                let axis = ReferenceMotionFacts.axisIndex(call.parameter1)
                return motion(call) { facts in axis.map { facts.position[$0] } }
            })
        registry
            .register(ConditionFunction(
                index: 446,
                name: "GetVelocity",
                parameter1: .integer
            ) { call in
                let axis = ReferenceMotionFacts.axisIndex(call.parameter1)
                return motion(call) { facts in axis.map { facts.velocity[$0] } }
            })
        registry.register(ConditionFunction(index: 25, name: "IsMoving") { call in
            motion(call) { Self.isTrue($0.movementDirection != 0) }
        })
        registry.register(ConditionFunction(index: 589, name: "GetMovementDirection") { call in
            motion(call) { $0.movementDirection }
        })
        for (index, name) in [(UInt16(623), "GetMovementSpeed"), (683, "GetPathingCurrentSpeed")] {
            registry.register(ConditionFunction(index: index, name: name) { call in
                motion(call) { $0.speed }
            })
        }
        registry.register(ConditionFunction(index: 704, name: "IsPathing") { call in
            motion(call) { Self.isTrue($0.pathTarget != nil) }
        })
        registry.register(ConditionFunction(index: 621, name: "GetPathingTargetSpeed") { call in
            motion(call) { $0.pathTarget == nil ? 0 : $0.pathTargetSpeed }
        })
        registry.register(ConditionFunction(
            index: 620, name: "GetPathingTargetAngleOffset", parameter1: .integer
        ) { call in
            let axis = ReferenceMotionFacts.axisIndex(call.parameter1)
            return motion(call) { facts in
                guard let axis else { return nil }
                guard axis == 2, let target = facts.pathTarget else { return 0 }
                return facts.headingAngle(to: target)
            }
        })
        let turnRates = [
            (UInt16(622), "GetPathingTargetSpeedAngle", false),
            (684, "GetPathingCurrentSpeedAngle", true)
        ]
        for (index, name, current) in turnRates {
            registry
                .register(ConditionFunction(
                    index: index,
                    name: name,
                    parameter1: .integer
                ) { call in
                    let axis = ReferenceMotionFacts.axisIndex(call.parameter1)
                    return motion(call) { facts in
                        axis.map { $0 == 2 ? facts.pathTurnRate(current: current) : 0 }
                    }
                })
        }
        installMotionPairs(&registry)
    }

    private static func installMotionPairs(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 99,
            name: "GetHeadingAngle",
            parameter1: .formID
        ) { call in
            motionPair(call, index: 99) { facts, other in facts.headingAngle(to: other.position) }
        })
        registry.register(ConditionFunction(
            index: 584, name: "GetRelativeAngle", parameter1: .formID, parameter2: .integer
        ) { call in
            let axis = ReferenceMotionFacts.axisIndex(call.parameter2)
            return motionPair(call, index: 584) { facts, other in
                let delta = other.position - facts.position
                return switch axis {
                case 2: facts.headingAngle(to: other.position)
                case 0: atan2(delta.z, simd_length(SIMD2(delta.x, delta.y))) * 180 / .pi
                default: 0
                }
            }
        })
        registry.register(ConditionFunction(
            index: 639, name: "GetWithinDistance", parameter1: .formID, parameter2: .integer
        ) { call in
            let limit = call.parameter2?.asFloat ?? 0
            return motionPair(call, index: 639) { facts, other in
                Self.isTrue(simd_distance(facts.position, other.position) <= limit)
            }
        })
        registry.register(ConditionFunction(
            index: 720,
            name: "GetTargetHeight",
            parameter1: .formID
        ) { call in
            motionPair(call, index: 720) { facts, other in other.position.z - facts.position.z }
        })
        // The activator is the reference the condition's target names: the crosshair
        // reference in the live game.
        registry.register(ConditionFunction(index: 680, name: "GetActivatorHeight") { call in
            motion(call) { facts in
                call.context.target
                    .flatMap { call.context.motion.facts(of: $0) }
                    .map { $0.position.z - facts.position.z }
            }
        })
    }

    /// One read of the run-on's motion. A nil from `read` is a parameter it could not use.
    private static func motion(
        _ call: ConditionCall,
        read: (ReferenceMotionFacts) -> Float?
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { key in
            guard let facts = call.context.motion.facts(of: key) else {
                return .failure(.unavailableData(.motion))
            }
            guard let value = read(facts) else {
                return .failure(.unresolvedParameter(call.condition.functionIndex))
            }
            return .success(value)
        }
    }

    private static func motionPair(
        _ call: ConditionCall,
        index: UInt16,
        read: (ReferenceMotionFacts, ReferenceMotionFacts) -> Float
    ) -> Result<Float, ConditionFailure> {
        guard let other = parameterReference(call) else {
            return .failure(.unresolvedParameter(index))
        }
        return call.referenceKey().flatMap { key in
            let motion = call.context.motion
            guard let facts = motion.facts(of: key), let otherFacts = motion.facts(of: other) else {
                return .failure(.unavailableData(.motion))
            }
            return .success(read(facts, otherFacts))
        }
    }
}
