// The quest notices the HUD shows each frame the quest state changed, and the
// object animation coordinators that share the "Animated objects" switch.

import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyWorldState

extension GameSessionScope {
    func updateQuestNotices() {
        guard let runtime = journal.runtime else { return }
        questNotices.update(
            runtime: runtime, quests: runtime.runtimeQuests(),
            revision: runtime.store.revision(of: [.quest]),
            strings: journal.strings, aliases: journalMenu.aliasNaming(runtime: runtime)
        )
    }

    func makeSequenceDoors() -> SequenceDoorCoordinator {
        let doors = SequenceDoorCoordinator(world: objectAnimationWorld)
        doors.isEnabled = objectBehaviors.isEnabled
        return doors
    }

    func makeNodeControllers() -> NodeControllerCoordinator {
        let nodes = NodeControllerCoordinator(world: objectAnimationWorld)
        nodes.isEnabled = objectBehaviors.isEnabled
        return nodes
    }
}
