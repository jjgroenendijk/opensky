// The `OnStory*` event a quest's scripts hear when a story-manager event started it.
// Each signature is the Creation Kit wiki page of the event, for example
// "OnStoryKillActor - Quest"; docs/engine/story-manager.md maps the event data.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldStateBridge {
    /// Queues the event on the quest's scripts. An event with no Papyrus twin sends nothing.
    @discardableResult
    public func queueStoryStartEvent(quest id: FormID, event: StoryEventData) -> Int {
        guard
            let world,
            let key = questRuntime?.quests.key(for: id),
            let start = storyStartEvent(event)
        else { return 0 }
        return world.queueActorEvent(start.name, on: key, arguments: start.arguments)
    }

    private func storyStartEvent(
        _ event: StoryEventData
    ) -> (name: String, arguments: [PapyrusValue])? {
        let values = [event.value1, event.value2]
            .map { PapyrusValue.integer(Int32(clamping: Int($0))) }
        switch event.event {
        case "KILL":
            return (PapyrusEngineEvents.onStoryKillActor, [
                reference(event.actor2), reference(event.actor1), location(event.location1)
            ] + values)
        case "CLOC":
            return (PapyrusEngineEvents.onStoryChangeLocation, [
                reference(event.actor1), location(event.location1), location(event.location2)
            ])
        case "AIPL":
            return (PapyrusEngineEvents.onStoryAddToPlayer, [
                reference(event.actor2), reference(event.actor1), location(event.location1),
                form(event.form), values[0]
            ])
        case "ASSU":
            return (PapyrusEngineEvents.onStoryAssaultActor, [
                reference(event.actor2), reference(event.actor1), location(event.location1),
                values[0]
            ])
        case "ADCR":
            return (PapyrusEngineEvents.onStoryCrimeGold, [
                reference(event.actor2), reference(event.actor1), form(event.form)
            ] + values)
        case "SKIL":
            return (PapyrusEngineEvents.onStoryIncreaseSkill, [.string(skillName(event.value1))])
        case "SCPT":
            return (PapyrusEngineEvents.onStoryScript, [
                form(event.keyword), location(event.location1), reference(event.actor1),
                reference(event.actor2)
            ] + values)
        default:
            return nil
        }
    }

    /// The script spelling of a skill: no spaces or hyphens, and the two skills whose
    /// script names differ from xEdit's.
    private func skillName(_ index: Float) -> String {
        let name = ActorValueIdentity.name(at: Int32(index)) ?? ""
        let scriptNames = ["Archery": "Marksman", "Speech": "Speechcraft"]
        return scriptNames[name] ?? name.filter { $0 != " " && $0 != "-" }
    }

    private func reference(_ key: ReferenceKey?) -> PapyrusValue {
        key.flatMap(objectHandle(for:)).map { .object($0) } ?? .none
    }

    private func location(_ id: ResolvedFormID?) -> PapyrusValue {
        reference(id.map(ReferenceKey.init(resolved:)))
    }

    private func form(_ id: FormID?) -> PapyrusValue {
        reference(id.flatMap(referenceKey(forFormID:)))
    }
}
