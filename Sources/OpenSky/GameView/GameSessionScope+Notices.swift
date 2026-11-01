// The quest notices the HUD shows each frame the quest state changed, and the
// object animation coordinators that share the "Animated objects" switch.

import OpenSkyFormatsMesh
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyWorld
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

    /// The camera that world billboards and effect billboards turn to.
    var billboardViewer: NIFBillboard.Viewer? {
        gameSession.map { NIFBillboard.Viewer(camera: $0.freeFlyCamera) }
    }

    func makeNodeControllers() -> NodeControllerCoordinator {
        let nodes = NodeControllerCoordinator(world: objectAnimationWorld)
        nodes.isEnabled = objectBehaviors.isEnabled
        return nodes
    }
}
