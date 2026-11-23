// Snapshot and restore of the script calls that are running or waiting, which the save
// writes as `PCAL`. docs/engine/papyrus-world.md#script-state-in-a-save.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsPEX
public import OpenSkyScriptingInterface

/// Saved calls whose scripts still load, with the arrays the whole snapshot shares.
struct PapyrusHeldCallRestores {
    var arrays: [PapyrusArray] = []
    var calls: [PapyrusCallState] = []
}

extension PapyrusWorldRuntime.Lifecycle {
    /// Every waiting call, oldest first. A call of a magic effect's script is left
    /// out, because a load attaches the effect's script again and starts it anew.
    public func callStates() -> PapyrusCallSnapshot {
        var saver = PapyrusCallSaver(world: world)
        var snapshot = PapyrusCallSnapshot()
        for (call, wake) in world.scheduler.pendingWaits {
            if let state = saver.state(of: call, wake: wake) {
                snapshot.calls.append(state)
            }
        }
        // An element is never an array, so the list does not grow in this loop.
        for array in saver.arrays {
            snapshot.arrays.append(PapyrusSavedArray(
                elementType: array.elementType.name,
                elements: array.elements.map { saver.saved($0) }
            ))
        }
        return snapshot
    }

    /// Replaces the waiting calls with the saved ones. Tolerant by design: a call that
    /// names a script, a function, or an instance that is not there is counted
    /// (`unrestorableSaveCall`) and dropped. A call whose script still loads waits.
    public func restore(calls snapshot: PapyrusCallSnapshot) {
        world.scheduler.cancelAll()
        world.suspensionTracker.reset()
        world.latentQuestWaits.removeAll()
        let arrays = snapshot.arrays.map { array in
            PapyrusArray(
                elementType: PapyrusType(name: array.elementType),
                elements: array.elements.map { runtimeValue($0, arrays: []) }
            )
        }
        world.heldCallRestores = PapyrusHeldCallRestores(arrays: arrays, calls: snapshot.calls)
        resumeHeldCallRestores()
    }

    /// Restores each held call whose scripts are loaded now.
    func resumeHeldCallRestores() {
        guard !world.heldCallRestores.calls.isEmpty else { return }
        let held = world.heldCallRestores
        var waiting: [PapyrusCallState] = []
        for state in held.calls {
            let scripts = Set(state.frames.map(\.script))
            let availability = scripts.map { world.scriptAvailability(named: $0) }
            if availability.contains(.loading) {
                waiting.append(state)
            } else if !restoreCall(state, arrays: held.arrays) {
                world.skips.note(.unrestorableSaveCall)
            }
        }
        world.heldCallRestores.calls = waiting
        if waiting.isEmpty {
            world.heldCallRestores.arrays = []
        }
    }

    private func restoreCall(_ state: PapyrusCallState, arrays: [PapyrusArray]) -> Bool {
        if let owner = state.owner, world.instancesByKey[owner] == nil {
            return false
        }
        let interpreter = PapyrusRuntime.Interpreter(runtime: world.runtime)
        for saved in state.frames {
            guard let frame = frame(saved, arrays: arrays) else { return false }
            interpreter.frames.append(frame)
        }
        guard !interpreter.frames.isEmpty || state.resume == .root else { return false }
        let returnType = PapyrusType(name: state.returnType)
        let call = PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: state.nativeScript,
            functionName: state.nativeFunction,
            receiver: nil,
            arguments: [],
            returnType: returnType
        )
        let suspended = interpreter.natives.suspend(
            call: call,
            request: request(for: state.wake, returnType: returnType, arrays: arrays),
            target: state.resume == .root ? .root : .assign(destination(state.resume)),
            holdsInstance: state.holdsInstance
        )
        if let owner = state.owner {
            world.suspensionTracker.begin(suspended, instance: owner)
        }
        world.scheduler.schedule(.suspended(suspended))
        return true
    }

    private func frame(_ saved: PapyrusFrameState, arrays: [PapyrusArray]) -> PapyrusFrame? {
        guard
            let index = world.runtime.index(named: saved.script),
            let function = index.function(ordinal: saved.functionOrdinal),
            function.function.instructions.count == saved.instructionCount,
            function.slotDefaults.count == saved.slots.count,
            (0 ... saved.instructionCount).contains(saved.instructionIndex)
        else { return nil }
        var handle: PapyrusObjectHandle?
        if let instance = saved.instance {
            guard let live = world.instancesByKey[instance] else { return nil }
            handle = live
        }
        let completion: PapyrusFrameCompletion = switch saved.completion {
        case .root: .root
        case .discard: .discard
        case .assign: .assign(destination(saved.completion))
        }
        let frame = PapyrusFrame(
            owner: index, compiled: function, instanceHandle: handle, completion: completion
        )
        frame.instructionIndex = saved.instructionIndex
        for (slot, value) in saved.slots.enumerated() {
            frame.setSlot(slot, to: runtimeValue(value, arrays: arrays))
        }
        return frame
    }

    private func destination(_ saved: PapyrusSavedReturn) -> PexValue {
        if case let .assign(name?) = saved {
            return .identifier(name)
        }
        return .null
    }

    /// The wait a restored call starts. A quest wait gets a new token, because the
    /// saved one means nothing in this session.
    private func request(
        for wake: PapyrusSavedWake, returnType: PapyrusType, arrays: [PapyrusArray]
    ) -> PapyrusNativeSuspension {
        switch wake {
        case let .realSeconds(seconds, answer):
            guard let answer else { return .realSeconds(seconds) }
            return .realSecondsAnswering(seconds, runtimeValue(answer, arrays: arrays))
        case let .menuSeconds(seconds):
            return .realSecondsWithMenus(seconds)
        case let .gameHours(hours):
            return .gameHours(hours)
        case let .questFragments(quest, answer):
            return questWait(quest, value: runtimeValue(answer, arrays: arrays), start: nil)
        case let .questStart(quest, thenFragments):
            return questWait(
                quest, value: .boolean(true), start: thenFragments ? .thenFragments : .only
            )
        case .lost:
            return .realSecondsAnswering(0, returnType.defaultValue)
        }
    }

    private func questWait(
        _ quest: ReferenceKey, value: PapyrusValue, start: PapyrusLatentQuestWait.StartWait?
    ) -> PapyrusNativeSuspension {
        let token = world.nextLatentQuestToken
        world.nextLatentQuestToken &+= 1
        world.latentQuestWaits.append(PapyrusLatentQuestWait(
            token: token, quest: quest, value: value, start: start
        ))
        return .external(token)
    }

    private func runtimeValue(_ saved: PapyrusSavedValue, arrays: [PapyrusArray]) -> PapyrusValue {
        switch saved {
        case .none: .none
        case let .boolean(flag): .boolean(flag)
        case let .integer(number): .integer(number)
        case let .float(number): .float(number)
        case let .string(text): .string(text)
        case let .instance(key): world.instancesByKey[key].map { .object($0) } ?? .none
        case let .reference(key): .object(world.activationRuns.objectHandle(for: key))
        case let .alias(quest, id):
            .object(world.questRuns.aliasSlotHandle(PapyrusAliasSlot(quest: quest, aliasID: id)))
        case let .array(index): arrays.indices.contains(index) ? .array(arrays[index]) : .none
        }
    }
}

/// Turns one waiting call into its saved form.
private struct PapyrusCallSaver {
    let world: PapyrusWorldRuntime
    /// Each array the calls hold, at its index in the snapshot.
    private(set) var arrays: [PapyrusArray] = []
    private var arrayIndices: [ObjectIdentifier: Int] = [:]

    init(world: PapyrusWorldRuntime) {
        self.world = world
    }

    mutating func state(
        of call: SuspendedCall, wake: PapyrusScheduler.PendingWake
    ) -> PapyrusCallState? {
        let owner = world.suspensionTracker.instance(waiting: call.id)
        let interpreter = call.continuation.interpreter
        guard
            owner?.effectRun == nil, let pending = interpreter.pendingResume,
            pending.id == call.id
        else { return nil }
        var frames: [PapyrusFrameState] = []
        for frame in interpreter.frames {
            guard let saved = savedFrame(frame) else { return nil }
            frames.append(saved)
        }
        var state = PapyrusCallState(
            wake: savedWake(wake), resume: savedReturn(pending.target), frames: frames
        )
        state.owner = owner
        state.holdsInstance = call.holdsInstance
        state.nativeScript = call.nativeCall.scriptName
        state.nativeFunction = call.nativeCall.functionName
        state.returnType = call.nativeCall.returnType.name
        return state
    }

    private mutating func savedFrame(_ frame: PapyrusFrame) -> PapyrusFrameState? {
        var instance: PapyrusInstanceKey?
        if let handle = frame.instanceHandle {
            guard let key = world.keysByHandle[handle], key.effectRun == nil else { return nil }
            instance = key
        }
        let completion: PapyrusSavedReturn = switch frame.completion {
        case .root: .root
        case .discard: .discard
        case let .assign(destination): .assign(destination.stringValue)
        }
        var state = PapyrusFrameState(
            script: frame.ownerScript.name, functionOrdinal: frame.compiled.ordinal,
            instructionCount: frame.function.instructions.count,
            instance: instance, completion: completion
        )
        state.instructionIndex = frame.instructionIndex
        state.slots = frame.slots.map { saved($0) }
        return state
    }

    private func savedReturn(_ target: PapyrusResumeTarget) -> PapyrusSavedReturn {
        switch target {
        case .root: .root
        case let .assign(destination): .assign(destination.stringValue)
        }
    }

    private mutating func savedWake(_ wake: PapyrusScheduler.PendingWake) -> PapyrusSavedWake {
        switch wake {
        case let .realSeconds(seconds, answer):
            return .realSeconds(seconds, answer: answer.map { saved($0) })
        case let .menuSeconds(seconds):
            return .menuSeconds(seconds)
        case let .gameHours(hours):
            return .gameHours(hours)
        case let .external(_, answer?):
            return .realSeconds(0, answer: saved(answer))
        case let .external(token, nil):
            guard let wait = world.latentQuestWaits.first(where: { $0.token == token }) else {
                return .lost
            }
            if let start = wait.start {
                return .questStart(quest: wait.quest, thenFragments: start == .thenFragments)
            }
            return .questFragments(quest: wait.quest, answer: saved(wait.value))
        }
    }

    mutating func saved(_ value: PapyrusValue) -> PapyrusSavedValue {
        switch value {
        case .none: return .none
        case let .boolean(flag): return .boolean(flag)
        case let .integer(number): return .integer(number)
        case let .float(number): return .float(number)
        case let .string(text): return .string(text)
        case let .object(handle): return savedObject(handle)
        case let .array(array):
            if let known = arrayIndices[ObjectIdentifier(array)] {
                return .array(known)
            }
            arrayIndices[ObjectIdentifier(array)] = arrays.count
            arrays.append(array)
            return .array(arrays.count - 1)
        }
    }

    private func savedObject(_ handle: PapyrusObjectHandle) -> PapyrusSavedValue {
        if let key = world.keysByHandle[handle] {
            return key.effectRun == nil ? .instance(key) : .none
        }
        if let key = world.opaqueKeysByHandle[handle] {
            return .reference(key)
        }
        if let slot = world.aliasSlotsByHandle[handle] {
            return .alias(quest: slot.quest, id: slot.aliasID)
        }
        return .none
    }
}
