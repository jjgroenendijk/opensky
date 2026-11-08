// Census probes for dialogue, scene, story-manager, idle, and message records.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countBranch(_ branch: DialogueBranch) {
        count("DLBR", branch, [
            ("editorID", { $0.editorID }), ("category", { $0.category }),
            ("exclusive", { $0.flags.contains(.exclusive) })
        ])
        tally("DLBR", branch.skipped)
    }

    mutating func countView(_ view: DialogueView) {
        count("DLVW", view, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }),
            ("topicType", { $0.topicType })
        ])
        tally("DLVW", view.skipped)
    }

    mutating func countScene(_ scene: Scene) {
        count("SCEN", scene, Self.sceneProbes)
        count("SCEN action", scene.actions, [
            ("name", { $0.name }), ("aliasID", { $0.aliasID }),
            ("unknownLNAM", { $0.unknownLNAM }), ("index", { $0.index }),
            ("flags", { $0.flags }), ("endPhase", { $0.endPhase })
        ])
        count("SCEN actor", scene.actors, [("flags", { $0.flags })])
        count("SCEN behavior", scene.actorBehavior, [
            ("death", { $0.death }), ("dialogue", { $0.dialogue }),
            ("observeCombat", { $0.observeCombat })
        ])
        let lines = scene.actions.compactMap { action -> SceneDialogue? in
            guard case let .dialogue(line) = action.payload else { return nil }
            return line
        }
        count("SCEN dialogue", lines, [
            ("headtrackAliasID", { $0.headtrackAliasID }), ("loopingMax", { $0.loopingMax }),
            ("loopingMin", { $0.loopingMin }), ("emotionType", { $0.emotionType }),
            ("emotionValue", { $0.emotionValue })
        ])
        countFragments("SCEN", scene.scriptData)
        tally("SCEN", scene.skipped)
    }

    mutating func countFragments(_ owner: String, _ script: ScriptData) {
        let section = script.recordFragments
        count("\(owner) fragments", section, [
            ("extraBindDataVersion", { $0.extraBindDataVersion }), ("flags", { $0.flags }),
            ("fileName", { $0.fileName })
        ])
        count("\(owner) fragment", section?.fragments ?? [], [
            ("scriptName", { $0.scriptName }), ("functionName", { $0.functionName })
        ])
        count("\(owner) phase fragment", section?.phaseFragments ?? [], [
            ("phaseFlag", { $0.phaseFlag }), ("phaseIndex", { $0.phaseIndex }),
            ("scriptName", { $0.scriptName }), ("functionName", { $0.functionName })
        ])
    }

    mutating func countStoryNode(_ node: StoryManagerNode) {
        count("\(Self.storyOwner(node))", node, Self.storyProbes)
        tally("SM node", node.skipped)
    }

    mutating func countIdle(_ idle: IdleAnimation) {
        count("IDLE", idle, [
            ("formID", { $0.formID }), ("fileName", { $0.fileName }),
            ("animationEvent", { $0.animationEvent })
        ])
        count("IDLE data", idle.properties, [
            ("loopMinimum", { $0.loopMinimum }), ("loopMaximum", { $0.loopMaximum }),
            ("flags", { $0.flags })
        ])
        tally("IDLE", idle.skipped)
    }

    mutating func countAnimatedObject(_ object: AnimatedObject) {
        count("ANIO", object, [("formID", { $0.formID }), ("model", { $0.model })])
        tally("ANIO", object.skipped)
    }

    mutating func countIdleMarker(_ marker: IdleMarker) {
        count("IDLM", marker, [
            ("formID", { $0.formID }), ("bounds", { $0.bounds }), ("flags", { $0.flags }),
            ("idleTimer", { $0.idleTimer }), ("model", { $0.model })
        ])
        tally("IDLM", marker.skipped)
    }

    mutating func countMessage(_ message: GameMessage) {
        count("MESG", message, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }),
            ("description", { $0.description }), ("name", { $0.name }),
            ("unusedIcon", { $0.unusedIcon }), ("quest", { $0.quest }),
            ("displayTime", { $0.displayTime })
        ])
        tally("MESG", message.skipped)
    }

    mutating func countLoadScreen(_ screen: LoadScreen) {
        count("LSCR", screen, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }),
            ("description", { $0.description }), ("conditions", { $0.conditions }),
            ("model", { $0.model }), ("initialScale", { $0.initialScale }),
            ("initialTranslation", { $0.initialTranslation })
        ])
        tally("LSCR", screen.skipped)
    }

    private static func storyOwner(_ node: StoryManagerNode) -> String {
        switch node.kind {
        case .branch: "SMBN"
        case .quest: "SMQN"
        case .event: "SMEN"
        }
    }

    static var sceneProbes: [Probe<Scene>] {
        [
            ("formID", { $0.formID }), ("flags", { $0.flags.rawValue }),
            ("lastActionIndex", { $0.lastActionIndex }), ("conditions", { $0.conditions }),
            ("scriptData", { $0.scriptData.scripts }),
            ("beginOnQuestStart", { $0.flags.contains(.beginOnQuestStart) }),
            ("stopQuestOnEnd", { $0.flags.contains(.stopQuestOnEnd) }),
            ("showAllText", { $0.flags.contains(.showAllText) }),
            ("repeatConditionsWhileTrue", { $0.flags.contains(.repeatConditionsWhileTrue) }),
            ("interruptible", { $0.flags.contains(.interruptible) })
        ]
    }

    static var storyProbes: [Probe<StoryManagerNode>] {
        [
            ("formID", { $0.formID }), ("flags", { $0.flags.rawValue }),
            ("maxConcurrentQuests", { $0.maxConcurrentQuests }),
            ("questsToRun", { $0.questsToRun }), ("random", { $0.flags.contains(.random) }),
            ("warnIfNoChildQuestStarted", { $0.flags.contains(.warnIfNoChildQuestStarted) }),
            ("doAllBeforeRepeating", { $0.flags.contains(.doAllBeforeRepeating) }),
            ("sharesEvent", { $0.flags.contains(.sharesEvent) }),
            ("numberOfQuestsToRun", { $0.flags.contains(.numberOfQuestsToRun) })
        ]
    }
}
