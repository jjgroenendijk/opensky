// One scene's step through its phases. Start and end phases are 0-based indices
// into the phase list, as the SCEN records store them. Actions on an empty alias
// are done at once, as the Creation Kit says of dead or disabled actors.

import Foundation
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

@MainActor
extension SceneRuntime {
    /// Seconds a line lasts when no host says otherwise.
    static let defaultLineDuration: Float = 3

    struct Playback {
        let runtime: SceneRuntime
        let entry: CatalogScene
        var state: SceneRuntimeState
        /// Playback writes the store only when this changed, to keep cells from rebuilding.
        private let initial: SceneRuntimeState?
        private var events: [SceneEvent] = []
        private var ended = false
        private var evaluator: ConditionEvaluator

        init(runtime: SceneRuntime, entry: CatalogScene, state: SceneRuntimeState, isNew: Bool) {
            self.runtime = runtime
            initial = isNew ? nil : state
            self.entry = entry
            self.state = state
            var context = runtime.dialogue.context
            context.subject = .player
            context.target = nil
            context.aliasQuest = entry.scene.quest
            evaluator = ConditionEvaluator(
                context: context, registry: runtime.dialogue.registry, tally: ConditionTally()
            )
        }

        private var scene: Scene {
            entry.scene
        }

        mutating func note(_ step: SceneStep) {
            events.append(SceneEvent(scene: entry.formID, step: step))
        }

        /// Moves through phases until one waits on a running action or the scene ends.
        mutating func advance() {
            var repeated = false
            var budget = scene.phases.count * 2 + 4
            while !ended, budget > 0 {
                budget -= 1
                completeDoneActions()
                guard Int(state.phase) < scene.phases.count else {
                    if
                        scene.flags.contains(.repeatConditionsWhileTrue), !repeated,
                        evaluator.evaluate(scene.conditions).isTrue
                    {
                        repeated = true
                        note(.repeated)
                        state = SceneRuntimeState()
                        continue
                    }
                    end(.finished)
                    return
                }
                guard enterPhaseIfNeeded() else { continue }
                guard completePhaseIfDone() else { return }
            }
        }

        /// False when the phase was skipped and the loop should go on to the next one.
        private mutating func enterPhaseIfNeeded() -> Bool {
            guard !state.phaseEntered else { return true }
            let index = state.phase
            guard evaluator.evaluate(scene.phases[Int(index)].startConditions).isTrue else {
                note(.phaseSkipped(index))
                state.phase += 1
                return false
            }
            state.phaseEntered = true
            note(.phaseStarted(index))
            runPhaseFragments(index, flag: 0x01)
            for (offset, action) in scene.actions.enumerated()
                where (action.startPhase ?? 0) == index
            {
                start(UInt32(offset), action)
            }
            completeDoneActions()
            return true
        }

        /// False while the phase still waits.
        private mutating func completePhaseIfDone() -> Bool {
            let index = state.phase
            let phase = scene.phases[Int(index)]
            let actionsDone = scene.actions.indices
                .filter { Self.endPhase(scene.actions[$0]) == index }
                .allSatisfy { !state.isRunning(UInt32($0)) }
            let byConditions = !phase.completionConditions.isEmpty
                && evaluator.evaluate(phase.completionConditions).isTrue
            guard actionsDone || byConditions else { return false }
            for progress in state.running
                where Self.endPhase(scene.actions[Int(progress.action)]) <= index
            {
                complete(progress.action)
            }
            runPhaseFragments(index, flag: 0x02)
            note(.phaseCompleted(index, byConditions: byConditions))
            state.phase += 1
            state.phaseEntered = false
            return true
        }

        static func endPhase(_ action: SceneAction) -> UInt32 {
            action.endPhase ?? action.startPhase ?? 0
        }

        private mutating func start(_ index: UInt32, _ action: SceneAction) {
            note(.actionStarted(index))
            switch action.payload {
            case let .timer(seconds):
                run(index, duration: seconds ?? 0)
            case let .dialogue(dialogue):
                guard let speaker = actor(of: action) else {
                    note(.emptyAlias(index))
                    complete(index)
                    return
                }
                say(index, topic: dialogue.topic, speaker: speaker)
            case .package, .unknown:
                note(.unsupportedAction(index, type: action.type))
                complete(index)
            }
        }

        private mutating func say(_ index: UInt32, topic id: FormID?, speaker: ReferenceKey) {
            let dialogue = runtime.dialogue
            guard
                let topic = id.flatMap({ dialogue.dialogue.topic($0) }),
                let offer = dialogue.selectTopics([topic], speaker: speaker).offers.first,
                (try? dialogue.choose(offer.info, speaker: speaker)) != nil
            else {
                note(.noLine(index))
                complete(index)
                return
            }
            let line = SceneLine(speaker: speaker, topic: topic.formID, info: offer.info)
            note(.line(line))
            let duration = dialogue.dialogue.info(offer.info)
                .map { runtime.host?.lineDuration(of: $0) ?? SceneRuntime.defaultLineDuration }
            run(index, duration: duration ?? SceneRuntime.defaultLineDuration)
        }

        private func actor(of action: SceneAction) -> ReferenceKey? {
            guard let alias = action.aliasID, alias >= 0, let quest = scene.quest else {
                return nil
            }
            return evaluator.context.aliases.reference(alias: UInt32(alias), in: quest)
        }

        private mutating func run(_ index: UInt32, duration: Float) {
            var running = state.running
            let progress = SceneActionProgress(
                action: index,
                startedAt: runtime.now,
                duration: duration
            )
            running.append(progress)
            state = SceneRuntimeState(
                phase: state.phase, phaseEntered: state.phaseEntered,
                running: running, completed: state.completed
            )
        }

        private mutating func complete(_ index: UInt32) {
            state = SceneRuntimeState(
                phase: state.phase, phaseEntered: state.phaseEntered,
                running: state.running.filter { $0.action != index },
                completed: state.completed + [index]
            )
            note(.actionCompleted(index))
        }

        private mutating func completeDoneActions() {
            for progress in state.running where progress.isDone(at: runtime.now) {
                complete(progress.action)
            }
        }

        mutating func end(_ reason: SceneEndReason) {
            guard !ended else { return }
            ended = true
            runFragment(slot: 0x02)
            note(.ended(reason))
            let stopsQuest = scene.flags.contains(.stopQuestOnEnd)
            if reason == .finished, stopsQuest, let quest = scene.quest {
                runtime.host?.stopQuest(quest)
            }
        }

        /// Writes the state back, or drops it when the scene ended.
        func finish() -> [SceneEvent] {
            if ended {
                runtime.store.reset(.scene, for: entry.key)
            } else if state != initial {
                runtime.store.set(state, for: entry.key)
            }
            return events
        }

        /// Begin is slot 0x01 and end 0x02 in the VMAD SCEN tail.
        mutating func runFragment(slot: UInt32) {
            guard let section = scene.scriptData.recordFragments else { return }
            for fragment in section.fragments where fragment.slot == slot {
                let function = fragment.functionName
                dispatch(script: fragment.scriptName, section: section, function: function)
            }
        }

        private mutating func runPhaseFragments(_ phase: UInt32, flag: UInt8) {
            guard let section = scene.scriptData.recordFragments else { return }
            for fragment in section.phaseFragments
                where fragment.phaseIndex == phase && fragment.phaseFlag & flag != 0
            {
                let function = fragment.functionName
                dispatch(script: fragment.scriptName, section: section, function: function)
            }
        }

        private mutating func dispatch(
            script: String,
            section: RecordFragmentSection,
            function: String
        ) {
            let name = script.isEmpty ? section.fileName : script
            let ran = runtime.fragments?.runSceneFragment(
                of: scene, key: entry.key, scriptName: name, functionName: function
            ) ?? false
            note(ran ? .fragment(function) : .fragmentUnrun(function))
        }
    }
}
