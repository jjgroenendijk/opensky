// A quest start that a script asks for waits in a queue: the aliases fill on the
// next frame, and the start-up stages run on the frame after that. The calling
// script waits for the result. See docs/engine/quest-state.md, "Starting a quest".

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

/// What a script's start request got.
nonisolated public enum PapyrusQuestStartAnswer: Equatable, Sendable {
    /// The call returns this value at once; nothing was queued.
    case answered(Bool)
    /// The call fails with this log line and returns false.
    case refused(String)
    /// The request waits in the queue.
    case queued
}

@MainActor
extension PapyrusWorldStateBridge.QuestScripts {
    static let eventScopedError = "attempting to start event scoped quest outside of story manager"

    /// Queues the start of a stopped quest. `stage` and `objective` are set once it runs.
    public func requestQuestStart(
        for key: ReferenceKey, stage: UInt16?, objective: UInt16?
    ) throws -> PapyrusQuestStartAnswer {
        let resolved = try resolveQuest(key)
        let id = resolved.quest.formID
        let state = try resolved.runtime.state(of: id)
        if state.isRunning {
            return .answered(true)
        }
        if !state.awaitsStart {
            if resolved.quest.event != nil {
                return .refused(Self.eventScopedError)
            }
            if resolved.quest.runsOnce, state.start.hasRun {
                return .answered(false)
            }
        }
        try resolved.runtime.queueStart(id, stage: stage, objective: objective)
        return .queued
    }

    /// Moves each queued start one phase on. A quest that filled its aliases in this
    /// call waits for the next call before its start-up stages run.
    func advanceQueuedStarts() {
        guard let runtime = bridge.questRuntime else { return }
        let pending = runtime.pendingStarts()
        guard !pending.isEmpty else { return }
        for entry in pending where entry.start.phase == .prepared {
            beginStartUp(entry.quest, key: entry.key, runtime: runtime)
        }
        for entry in pending where entry.start.phase == .queued {
            do {
                try runtime.prepareStart(entry.quest.formID)
            } catch {
                bridge.runState.questAliasFillFailures += 1
                bridge.world?.questRuns.answerStartWaits(of: entry.key, started: false)
            }
        }
    }

    /// Ends each start whose start-up fragments have all run, and answers its scripts.
    func finishQuestStartUps() {
        guard let runtime = bridge.questRuntime, let world = bridge.world else { return }
        for entry in runtime.pendingStarts() where entry.start.phase == .startUp {
            guard !world.questRuns.hasPendingFragments(of: entry.key) else { continue }
            let id = entry.quest.formID
            guard attempt({ try runtime.finishStart(id) }) != nil else { continue }
            bridge.natives.story.questStarted?(id)
            _ = bridge.ports.story?.sendStoryEvent(.questStart(id))
            for stage in entry.start.stages {
                _ = attempt { try setQuestStage(stage, for: entry.key) }
            }
            for objective in entry.start.objectives {
                _ = attempt { try setQuestObjectiveDisplayed(objective, true, for: entry.key) }
            }
            world.questRuns.answerStartWaits(of: entry.key, started: true)
        }
    }

    private func beginStartUp(_ quest: Quest, key: ReferenceKey, runtime: any QuestAccess) {
        guard attempt({ try runtime.beginStartUp(quest.formID) }) != nil else { return }
        attachQuestScripts(quest, key: key)
        for stage in quest.stages where stage.flags.contains(.startUpStage) {
            _ = attempt { try setQuestStage(stage.index, for: key) }
        }
    }
}

extension PapyrusWorldRuntime.QuestScriptRuns {
    /// Suspends the calling script until the queued start of `quest` ends. A call that
    /// also set a stage then waits for that stage's fragments.
    func awaitQuestStart(of quest: ReferenceKey, thenFragments: Bool) -> PapyrusNativeResult {
        let token = world.nextLatentQuestToken
        world.nextLatentQuestToken &+= 1
        world.latentQuestWaits.append(PapyrusLatentQuestWait(
            token: token, quest: quest, value: .boolean(true),
            start: thenFragments ? .thenFragments : .only
        ))
        return .suspended(.external(token))
    }

    /// A failed start answers false. A start that worked answers true, or leaves the
    /// wait to `answerLatentQuestWaits` when the call also set a stage.
    func answerStartWaits(of quest: ReferenceKey, started: Bool) {
        var kept: [PapyrusLatentQuestWait] = []
        for var wait in world.latentQuestWaits {
            guard wait.quest == quest, wait.start != nil else {
                kept.append(wait)
                continue
            }
            if started, wait.start == .thenFragments {
                wait.start = nil
                kept.append(wait)
            } else if !world.scheduler.answer(wait.token, returning: .boolean(started)) {
                kept.append(wait)
            }
        }
        world.latentQuestWaits = kept
    }
}
