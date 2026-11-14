// `openskycli game debug ...`: console-style changes to the running game. Each
// answers with the value as stored afterwards, so a script can check it.

import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySaveInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension AgentWorldAdapter {
    public func perform(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentHandling {
        switch command {
        case .teleport, .view:
            return try .waiting(moveJob(command).wait)
        case let .setTime(hour):
            game.runtimeState.setGameClockHour(hour)
            return done(["hour": .init(game.runtimeState.runtimeStateClock.hourOfDay)])
        case let .weather(editorID):
            return try done(render.forceWeather(editorID))
        case .setActorValue, .modActorValue, .addItem, .removeItem:
            return try done(items.changeActor(command))
        case let .setQuestStage(quest, stage):
            return try done(events.setQuestStage(quest, stage: stage))
        case .kill, .resurrect, .decapitate, .flight, .drunk, .knock, .knockdown, .perk,
             .beastForm, .eyes, .link, .paired:
            return try done(actorDebug(command))
        case .overlay, .channel, .shadows, .fade, .cartMode, .playBink, .skipBink, .titles,
             .loadScreen, .sound, .settings:
            return try done(render.renderDebug(command))
        case .raceMenu, .skillsMenu, .gamepad, .fastTravel, .newGame:
            return try done(menuDebug(command))
        case let .benchmark(request):
            return try view.benchmark(request)
        case .favor, .teammate, .relationship:
            return try done(objects.followerDebug(command))
        case .sit, .stand, .passTime:
            return try done(behaviour.performFurniture(command))
        case .subGraphEvent, .subGraphVariable:
            return try done(objects.driveSubGraphs(command))
        }
    }

    private func moveJob(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentTeleportJob {
        switch command {
        case let .teleport(target): try AgentTeleportJob(hub: hub, target: target)
        case let .view(target): try view.viewJob(target)
        default: throw AgentFailure(.invalidArgument, "not a move")
        }
    }

    private func menuDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .raceMenu(limited): try menuReadout.openRaceMenu(limited: limited)
        case let .skillsMenu(sky, levels): try menuReadout.openSkillsMenu(sky: sky, levels: levels)
        case let .gamepad(count, press): try screens.driveGamepad(count: count, press: press)
        case let .fastTravel(marker): try screens.fastTravel(to: marker)
        case let .newGame(request): try startNewGame(request)
        default: throw AgentFailure(.invalidArgument, "not a menu debug command")
        }
    }

    private func startNewGame(_ request: AgentNewGameRequest) throws(AgentFailure) -> AgentJSON {
        if game.titleMenu.isOpen {
            game.titleMenu.close()
        }
        try game.menuWorld.startNewGame(request)
        return request.json
    }

    private func actorDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .kill(reference): try items.kill(reference)
        case let .resurrect(reference): try items.resurrect(reference)
        case let .decapitate(reference): try actors.decapitate(reference)
        case let .flight(reference, order): try motion.orderFlight(reference, order: order)
        case let .drunk(reference, drunk): try actors.setDrunk(reference, drunk: drunk)
        case let .paired(reference, target, idle):
            try behaviour.playPaired(reference, target: target, idle: idle)
        case let .perk(editorID, owned): try actors.setPlayerPerk(editorID, owned: owned)
        case let .beastForm(name): try actors.forceBeastForm(name)
        case let .eyes(reference, textureSet): try actors.setEyes(reference, textureSet: textureSet)
        case let .link(link, linked): try actors.setRagdollLink(link, linked: linked)
        case .knock, .knockdown: try motion.knockDebug(command)
        default: throw AgentFailure(.invalidArgument, "not an actor debug command")
        }
    }

    private func done(_ value: AgentJSON) -> AgentHandling {
        .done(.success(value))
    }
}

extension AgentWorldAdapter {
    public func teleportJob(to target: AgentTeleportTarget) throws(AgentFailure)
        -> AgentTeleportJob
    {
        try AgentTeleportJob(hub: hub, target: target)
    }

    public func teleportJob(to place: SavePlayerPlace) throws(AgentFailure) -> AgentTeleportJob {
        try AgentTeleportJob(hub: hub, place: place)
    }
}
