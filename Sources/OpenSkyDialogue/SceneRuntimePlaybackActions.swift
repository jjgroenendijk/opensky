// The actions of one scene's playback. An action on an empty alias is done at
// once, as the Creation Kit says of dead or disabled actors. A package action is
// done when its package reaches its Done state, and a line when its voice file ends
// (<https://ck.uesp.net/wiki/Category:Scenes>, "Completing a Phase").

import Foundation
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

@MainActor
extension SceneRuntime.Playback {
    mutating func start(_ index: UInt32, _ action: SceneAction) {
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
            let topic = entry.translation?(dialogue.topic) ?? dialogue.topic
            say(index, topic: topic, speaker: speaker, lookAt: lookTarget(of: dialogue))
        case .package:
            guard let actor = actor(of: action) else {
                note(.emptyAlias(index))
                complete(index)
                return
            }
            note(.packageStarted(index, actor: actor))
            run(index, duration: nil)
            checkPackage(index, action)
        case .unknown:
            note(.unsupportedAction(index, type: action.type))
            complete(index)
        }
    }

    private func owner(_ index: UInt32) -> ScenePackageOwner {
        ScenePackageOwner(scene: entry.formID, action: index)
    }

    private func lookTarget(of dialogue: SceneDialogue) -> ReferenceKey? {
        guard let alias = dialogue.headtrackAliasID, alias >= 0, let quest = entry.quest else {
            return nil
        }
        return evaluator.context.aliases.reference(alias: UInt32(alias), in: quest)
    }

    private mutating func say(
        _ index: UInt32, topic id: FormID?, speaker: ReferenceKey, lookAt: ReferenceKey?
    ) {
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
        var line = SceneLine(speaker: speaker, topic: topic.formID, info: offer.info)
        line.lookAt = lookAt
        run(index, duration: nil)
        runtime.pendingLines.lines[owner(index)] = line
        startLineClock(index)
        if runtime.pendingLines.lines[owner(index)] != nil {
            note(.voiceLoading(index))
        }
    }

    /// Starts the line's clock once its length is known, so the next line starts
    /// when this one ends: no overlap and no gap.
    private mutating func startLineClock(_ index: UInt32) {
        guard var line = runtime.pendingLines.lines[owner(index)] else {
            complete(index)
            return
        }
        let seconds: Float? = if
            let host = runtime.host,
            let info = runtime.dialogue.dialogue.info(line.info)
        {
            host.lineDuration(of: info, speaker: line.speaker)
        } else {
            SceneRuntime.defaultLineDuration
        }
        guard let seconds else { return }
        runtime.pendingLines.lines[owner(index)] = nil
        line.seconds = seconds
        note(.line(line))
        state.running.removeAll { $0.action == index }
        run(index, duration: seconds)
    }

    func actor(of action: SceneAction) -> ReferenceKey? {
        guard let alias = action.aliasID, alias >= 0, let quest = entry.quest else {
            return nil
        }
        return evaluator.context.aliases.reference(alias: UInt32(alias), in: quest)
    }

    private mutating func run(_ index: UInt32, duration: Float?) {
        let progress = SceneActionProgress(
            action: index, startedAt: runtime.now, duration: duration
        )
        // The initializer keeps the running list sorted, as a loaded save has it.
        state = SceneRuntimeState(
            phase: state.phase, phaseEntered: state.phaseEntered,
            running: state.running + [progress], completed: state.completed
        )
    }

    mutating func complete(_ index: UInt32) {
        releaseAction(index)
        state = SceneRuntimeState(
            phase: state.phase, phaseEntered: state.phaseEntered,
            running: state.running.filter { $0.action != index },
            completed: state.completed + [index]
        )
        note(.actionCompleted(index))
    }

    /// Hands a package actor back to its schedule and drops a waiting line.
    mutating func releaseAction(_ index: UInt32) {
        runtime.pendingLines.lines[owner(index)] = nil
        let action = scene.actions[Int(index)]
        guard case .package = action.payload, let actor = actor(of: action) else { return }
        runtime.host?.releaseScenePackages(actor: actor, owner: owner(index))
    }

    mutating func completeDoneActions() {
        for progress in state.running {
            guard progress.duration != nil else {
                checkWaiting(progress.action)
                continue
            }
            if progress.isDone(at: runtime.now) {
                complete(progress.action)
            }
        }
    }

    /// An action with no clock waits on its package or on its voice file.
    private mutating func checkWaiting(_ index: UInt32) {
        let action = scene.actions[Int(index)]
        switch action.payload {
        case .package: checkPackage(index, action)
        case .dialogue: startLineClock(index)
        default: break
        }
    }

    private mutating func checkPackage(_ index: UInt32, _ action: SceneAction) {
        guard case let .package(packages) = action.payload, let actor = actor(of: action) else {
            complete(index)
            return
        }
        guard let host = runtime.host else { return }
        let translated = packages.map { entry.translation?($0) ?? $0 }
        let progress = host.runScenePackages(translated, actor: actor, owner: owner(index))
        guard progress == .done else { return }
        note(.packageDone(index))
        complete(index)
    }
}
