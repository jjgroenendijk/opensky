import Foundation
import OpenSkyCamera
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `MenuScreensGuidesAdapter` reads from the session.
@MainActor
public protocol MenuScreensGuidesHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var mapWorld: any MapWorldPort { get }
    var messageWorld: any MessageWorldPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var progression: any ProgressionPort { get }
    var progressionWorld: any ProgressionWorldPort { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `MenuScreensWorldAdapter`, over its own narrow host.
public struct MenuScreensGuidesAdapter {
    public let game: any MenuScreensGuidesHost
}

extension MenuScreensGuidesAdapter {
    public func helpTopic(_ editorID: String) -> HelpTopic? {
        let messages = game.messageWorld
        guard
            let key = messages.messageKey(editorID: editorID),
            let built = messages.buildMessage(key, arguments: [])
        else { return nil }
        let name = editorID.dropFirst("Help".count).dropLast("Long".count)
        return HelpTopic(
            title: built.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(name),
            text: built.text
        )
    }

    var helpTopicEditorIDs: [String] {
        game.messageWorld.messageEditorIDs.filter(HelpTopic.isTopic(editorID:))
    }

    public func buttonName(forUserEvent event: String) -> String? {
        game.playerSettings.buttonName(forUserEvent: event)
    }
}

extension MenuScreensGuidesAdapter {
    public func mapScreenPoint(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        guard
            let pose = game.mapWorld.mapViewPose,
            let session = game.gameSession,
            let renderer = game.renderer
        else { return nil }
        let view = MenuScene(
            eye: pose.eye, target: pose.lookAt, up: SIMD3(0, 0, 1),
            fovYRadians: session.sessionFOVYRadians
        )
        guard
            let screen = view.screenPoint(point, aspectRatio: renderer.drawableAspectRatio),
            (0 ... 1).contains(screen.x), (0 ... 1).contains(screen.y)
        else { return nil }
        return screen
    }
}

extension MenuScreensGuidesAdapter {
    var nearestTrainer: ReferenceKey? {
        game.progressionWorld.nearestTrainer()?.trainer
    }

    public func trainingCard(trainer: ReferenceKey) -> TrainingCard? {
        guard let offer = game.progressionWorld.trainerOffer(for: trainer) else { return nil }
        let progression = game.progression
        let skill = progression.skillsMenuSkills.first { $0.index == offer.skill }
        let level = Int(skill?.level ?? 0)
        let name = skill?.name ?? ActorValueIdentity.name(at: offer.skill) ?? ""
        let sessions = progression.leveling?.state.trainingSessions ?? 0
        let cost = progression.training.cost(skillLevel: level)
        let price = (cost, game.progressionWorld.playerGold())
        return TrainingCard(
            skill: (name, level), progress: skill?.progress ?? 0,
            trainer: (offer.name, offer.maximumLevel),
            sessions: (Int(sessions), TrainingSettings.sessionsPerLevel),
            price: price,
            tier: progression.training.tier(trainerMaximum: offer.maximumLevel)
        )
    }

    public func train(with trainer: ReferenceKey) -> String? {
        guard let offer = game.progressionWorld.trainerOffer(for: trainer) else {
            return "No trainer"
        }
        let training = game.progression.training
        return switch game.progression.train(with: offer) {
        case .trained: nil
        case .refused(.insufficientGold): training.insufficientGoldText
        case let .refused(refusal): training.text(for: refusal)
        case .unavailable: "No game"
        }
    }
}
