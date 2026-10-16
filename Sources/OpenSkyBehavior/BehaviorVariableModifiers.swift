// Modifiers that compute variables rather than bones: activity flags, smoothing,
// timers, vector maths, and the iState manager. Each reads its bound inputs and
// writes its outputs back through `writeOutputs` (docs/engine/behavior-runtime.md).

import Foundation
import OpenSkyFormatsAnimation
import simd

/// What one modifier run gets beside the pose.
nonisolated public struct BehaviorModifierStep {
    public let target: HKXPointerTarget
    public let node: BehaviorCompiledNode
    /// Bound member values, keyed by member path without the `m_` prefix.
    public let bound: [String: BehaviorVariableValue]
    public let deltaTime: Float
    public let depth: Int
}

nonisolated extension [String: BehaviorVariableValue] {
    public func bool(_ path: String, or fallback: Bool) -> Bool {
        self[BehaviorGraphInstance.normalizedMemberPath(path)]?.boolValue ?? fallback
    }

    public func quad(_ path: String, or fallback: SIMD4<Float>) -> SIMD4<Float> {
        switch self[BehaviorGraphInstance.normalizedMemberPath(path)] {
        case let .quad(value): value
        case let .some(other): SIMD4(other.realValue, 0, 0, 0)
        case .none: fallback
        }
    }
}

nonisolated extension BehaviorGraphInstance {
    func runVariableModifier(
        _ object: any HKBClass, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        switch object {
        case let modifier as BSIsActiveModifier:
            applyIsActive(modifier, step)
        case let modifier as HKBEvaluateExpressionModifier:
            applyExpressions(modifier, step)
        case let modifier as HKBEventsFromRangeModifier:
            applyEventsFromRange(modifier, step)
        case let modifier as BSInterpValueModifier:
            applyInterpolation(modifier, step)
        case let modifier as HKBDampingModifier:
            applyDamping(modifier, step)
        case let modifier as BSSpeedSamplerModifier:
            let goal = step.bound.float("goalSpeed", or: modifier.goalSpeed)
            writeOutputs(["speedOut": .real(goal)], of: step.node)
        case let modifier as BSEventOnFalseToTrueModifier:
            applyFalseToTrue(modifier, step)
        case let modifier as BSTimerModifier:
            applyTimer(
                at: step.target,
                alarm: step.bound.float("alarmTimeSeconds", or: modifier.alarmTimeSeconds),
                event: modifier.alarmEvent,
                repeating: step.bound.bool("resetAlarm", or: modifier.resetAlarm),
                deltaTime: step.deltaTime
            )
        case let modifier as BSModifyOnceModifier:
            return applyModifyOnce(modifier, step, to: pose)
        default:
            return runVectorModifier(object, step, to: pose)
        }
        return pose
    }

    private func runVectorModifier(
        _ object: any HKBClass, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        switch object {
        case let modifier as BSDecomposeVectorModifier:
            let vector = step.bound.quad("vector", or: modifier.vector)
            writeOutputs(
                [
                    "x": .real(vector.x),
                    "y": .real(vector.y),
                    "z": .real(vector.z),
                    "w": .real(vector.w)
                ],
                of: step.node
            )
        case is BSGetTimeStepModifier:
            writeOutputs(["timeStep": .real(step.deltaTime)], of: step.node)
        case let modifier as HKBTransformVectorModifier:
            applyTransformVector(modifier, step)
        case let modifier as BSIStateManagerModifier:
            applyIStateManager(modifier, step)
        default:
            return runBoneModifier(object, step, to: pose)
        }
        return pose
    }

    // MARK: - Activity

    /// `BSIsActiveModifier`: while it runs, each `bIsActiveN` reads true, or false
    /// when `bInvertActiveN` is set. Deactivation writes the opposite.
    private func applyIsActive(_ modifier: BSIsActiveModifier, _ step: BehaviorModifierStep) {
        var state = markReached(step.target)
        state.isModifierRunning = true
        nodeStates[step.target] = state
        writeOutputs(isActiveOutputs(modifier, step.bound, running: true), of: step.node)
    }

    private func isActiveOutputs(
        _ modifier: BSIsActiveModifier,
        _ bound: [String: BehaviorVariableValue],
        running: Bool
    ) -> [String: BehaviorVariableValue] {
        var outputs: [String: BehaviorVariableValue] = [:]
        for slot in modifier.invertActive.indices {
            let invert = bound.bool("bInvertActive\(slot)", or: modifier.invertActive[slot])
            outputs["bIsActive\(slot)"] = .bool(running != invert)
        }
        return outputs
    }

    /// The deactivation half of the variable modifiers. True when `object` was one.
    func noteModifierDeactivation(of object: any HKBClass, at target: HKXPointerTarget) -> Bool {
        switch object {
        case let modifier as BSIsActiveModifier:
            guard
                nodeStates[target]?.isModifierRunning == true,
                let node = compiledNode(at: target)
            else { return true }
            let outputs = isActiveOutputs(modifier, boundValues(of: node), running: false)
            // A node that just became active wrote these this update; it wins.
            let fresh = outputs.filter { path, _ in
                outputIndexes(of: node, path: path).allSatisfy {
                    !variablesWrittenThisUpdate.contains($0)
                }
            }
            writeOutputs(fresh, of: node)
            return true
        case let modifier as BSModifyOnceModifier:
            if let onDeactivate = modifier.onDeactivateModifier {
                _ = applyModifier(at: onDeactivate, to: skeleton.restPose, deltaTime: 0)
            }
            return true
        default:
            return false
        }
    }

    /// `BSModifyOnceModifier`: the activate modifier runs on the first update only.
    private func applyModifyOnce(
        _ modifier: BSModifyOnceModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        var state = markReached(step.target)
        guard !state.hasSeeded else { return pose }
        state.hasSeeded = true
        nodeStates[step.target] = state
        return applyModifier(
            at: modifier.onActivateModifier, to: pose, deltaTime: step.deltaTime,
            depth: step.depth + 1
        )
    }

    // MARK: - Smoothing

    /// `BSInterpValueModifier`: moves `result` from `source` towards `target` by
    /// `gain` per second. Bound with `source` and `result` on one variable, this is
    /// an exponential follow.
    private func applyInterpolation(
        _ modifier: BSInterpValueModifier, _ step: BehaviorModifierStep
    ) {
        let source = step.bound.float("source", or: modifier.source)
        let target = step.bound.float("target", or: modifier.target)
        let gain = step.bound.float("gain", or: modifier.gain)
        let amount = min(max(gain * step.deltaTime, 0), 1)
        writeOutputs(["result": .real(source + (target - source) * amount)], of: step.node)
    }

    /// `hkbDampingModifier`: a PID filter, applied once per update, that moves the
    /// damped value towards the raw one.
    private func applyDamping(_ modifier: HKBDampingModifier, _ step: BehaviorModifierStep) {
        var state = markReached(step.target)
        let bound = step.bound
        let gains = SIMD3(
            bound.float("kP", or: modifier.proportionalGain),
            bound.float("kI", or: modifier.integralGain),
            bound.float("kD", or: modifier.derivativeGain)
        )
        var outputs: [String: BehaviorVariableValue] = [:]
        if bound.bool("enableScalarDamping", or: modifier.enableScalarDamping) {
            let raw = SIMD4(bound.float("rawValue", or: modifier.rawValue), 0, 0, 0)
            let damped = SIMD4(bound.float("dampedValue", or: modifier.dampedValue), 0, 0, 0)
            outputs["dampedValue"] = .real(damp(raw, damped, gains, &state).x)
        }
        if bound.bool("enableVectorDamping", or: modifier.enableVectorDamping) {
            let raw = bound.quad("rawVector", or: modifier.rawVector)
            let damped = bound.quad("dampedVector", or: modifier.dampedVector)
            outputs["dampedVector"] = .quad(damp(raw, damped, gains, &state))
        }
        nodeStates[step.target] = state
        writeOutputs(outputs, of: step.node)
    }

    private func damp(
        _ raw: SIMD4<Float>, _ damped: SIMD4<Float>, _ gains: SIMD3<Float>,
        _ state: inout BehaviorNodeState
    ) -> SIMD4<Float> {
        let error = raw - damped
        state.errorSum += error
        let derivative = error - state.previousError
        state.previousError = error
        return damped + gains.x * error + gains.y * state.errorSum + gains.z * derivative
    }

    // MARK: - Events

    /// `BSEventOnFalseToTrueModifier`: each enabled slot raises its event when its
    /// bound bool goes from false to true. Slots start at their authored value.
    private func applyFalseToTrue(
        _ modifier: BSEventOnFalseToTrueModifier, _ step: BehaviorModifierStep
    ) {
        var state = markReached(step.target)
        if !state.hasSeeded {
            state.hasSeeded = true
            state.flags = modifier.slots.map(\.variableToTest)
        }
        for (index, slot) in modifier.slots.enumerated() where state.flags.indices.contains(index) {
            let label = index + 1
            let value = step.bound.bool("bVariableToTest\(label)", or: slot.variableToTest)
            let enabled = step.bound.bool("bEnableEvent\(label)", or: slot.enableEvent)
            if enabled, value, !state.flags[index] {
                raise(slot.eventToSend)
            }
            state.flags[index] = value
        }
        nodeStates[step.target] = state
    }

    // MARK: - Vectors and states

    /// `hkbTransformVectorModifier`: `vectorOut` is `vectorIn` rotated, then
    /// translated unless `rotateOnly`; `inverse` undoes the transform instead.
    private func applyTransformVector(
        _ modifier: HKBTransformVectorModifier, _ step: BehaviorModifierStep
    ) {
        var state = markReached(step.target)
        let first = !state.hasSeeded
        state.hasSeeded = true
        nodeStates[step.target] = state
        let bound = step.bound
        guard
            bound.bool("computeOnModify", or: modifier.computeOnModify)
            || (first && bound.bool("computeOnActivate", or: modifier.computeOnActivate))
        else { return }
        let raw = bound.quad("rotation", or: modifier.rotation)
        let rotation = BehaviorPoseMath.normalized(simd_quatf(vector: raw))
        let move = bound.bool("rotateOnly", or: modifier.rotateOnly)
            ? SIMD3<Float>() : BehaviorModelPose.vector3(bound.quad(
                "translation",
                or: modifier.translation
            ))
        let input = BehaviorModelPose.vector3(bound.quad("vectorIn", or: modifier.vectorIn))
        let output = bound.bool("inverse", or: modifier.inverse)
            ? rotation.inverse.act(input - move)
            : rotation.act(input) + move
        writeOutputs(["vectorOut": .quad(SIMD4(output, 0))], of: step.node)
    }

    /// `BSIStateManagerModifier`: publishes the iState of the first listed state
    /// machine that is in the listed state.
    private func applyIStateManager(
        _ modifier: BSIStateManagerModifier, _ step: BehaviorModifierStep
    ) {
        markReached(step.target)
        for data in modifier.stateData {
            guard
                let machine = data.stateMachine,
                let state = machineStates[machine],
                state.isEntered,
                state.currentStateId == data.stateID
            else { continue }
            writeOutputs(
                ["iStateVar": .int(Int32(truncatingIfNeeded: data.stateToSetAs))],
                of: step.node
            )
            return
        }
    }
}
