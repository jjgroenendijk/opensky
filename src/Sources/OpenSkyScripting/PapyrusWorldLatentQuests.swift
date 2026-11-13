// `SetStage` and `Start` are latent: they return once the fragments of the stage they
// set have run (<https://ck.uesp.net/wiki/SetCurrentStageID_-_Quest>).
// See docs/engine/papyrus-quests.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

nonisolated struct PapyrusLatentQuestWait: Equatable, Sendable {
    let token: UInt64
    let quest: ReferenceKey
    let value: PapyrusValue
}

extension PapyrusWorldRuntime.QuestScriptRuns {
    /// Returns `value` now when no fragment of `quest` waits to run, else waits for them.
    func awaitQuestFragments(
        of quest: ReferenceKey, answering value: PapyrusValue
    ) -> PapyrusNativeResult {
        guard hasPendingFragments(of: quest) else { return .returned(value) }
        let token = world.nextLatentQuestToken
        world.nextLatentQuestToken &+= 1
        world.latentQuestWaits.append(PapyrusLatentQuestWait(
            token: token,
            quest: quest,
            value: value
        ))
        return .suspended(.external(token))
    }

    /// A fragment on a busy instance does not count: the waiting call may hold that
    /// instance itself, and the game's latent call frees the script for the fragment.
    func hasPendingFragments(of quest: ReferenceKey) -> Bool {
        world.lifecycle.hasDeferredWork(forQuest: quest) || world.eventQueue.contains { event in
            event.target.reference == quest && !world.busyInstances.contains(event.target)
                && event.functionName.lowercased().hasPrefix("fragment_")
        }
    }

    func answerLatentQuestWaits() {
        world.latentQuestWaits.removeAll { wait in
            !hasPendingFragments(of: wait.quest)
                && world.scheduler.answer(wait.token, returning: wait.value)
        }
    }
}

extension PapyrusWorldRuntime.QuestScriptRuns {
    /// A shut-down stage stopped `quest`; its instances retire after its fragments run.
    public func retireAfterShutDown(_ quest: ReferenceKey) {
        world.shutDownQuests.insert(quest)
    }

    func retireShutDownQuests() {
        for quest in world.shutDownQuests.sorted() {
            let pending = world.eventQueue.contains { $0.target.reference == quest }
                || world.busyInstances.contains { $0.reference == quest }
            guard !pending || world.isQuestRunning(quest) else { continue }
            world.shutDownQuests.remove(quest)
            if !world.isQuestRunning(quest) {
                detachQuest(key: quest)
            }
        }
    }
}
