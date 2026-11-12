import Foundation

// Every state query and the player's debug commands answer from the fakes: each one either
// returns or fails with a typed error, and none reaches a port it should not.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AgentSweepTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        host.fakeMovies.readout = MoviePlaybackReadout(loading: false, interruptible: true)
        host.fakeScenes.sceneSnapshot = SceneControlSnapshot(playing: [], trace: [], lines: [])
        host.fakeScripts.scriptsSnapshot = .empty
        host.fakeMagic.weaponEnchantments.enchantmentCacheReadout = .empty
        host.fakeJournalMenu.snapshot = .empty
        host.fakeDialogueMenu.snapshot = .empty
        host.fakeFollowerCommands.phase = .idle
        host.fakeFollowerCommands.settings = .vanilla
        host.fakeMounts.phase = .none
        host.fakeMounts.settings = .vanilla
        host.fakeRagdoll.deathSettings = .vanilla
        let idles = FakeIdlePort()
        idles.idleSnapshotResult = .unavailable
        host.fakeIdleWorld.idles = idles
        host.fakeRenderControls.frameStatsSnapshot = .empty
        host.fakeWorldState.snapshotResult = .empty
        host.fakeStreamer.residentReferenceIndexResult = .empty
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func answers(_ query: AgentStateQuery) -> Bool {
        do {
            _ = try world.query(query)
            return true
        } catch {
            return false
        }
    }

    private func handles(_ command: AgentDebugCommand) -> Bool {
        do {
            _ = try world.perform(command)
            return true
        } catch {
            return false
        }
    }

    @Test func readoutsWithoutAReferenceAnswer() {
        let queries: [AgentStateQuery] = [
            .target, .scenes, .scripts(reference: nil), .objects(reference: nil),
            .effects(reference: nil), .nodes(reference: nil), .flight(reference: nil), .mount,
            .paired, .favor, .impulses, .changes(limit: 5), .time, .frame
        ]
        let answered = queries.filter(answers)
        #expect(
            answered.count == queries.count,
            "\(Set(queries.map { "\($0)" }).subtracting(answered.map { "\($0)" }))"
        )
    }

    @Test func playerReadoutsReachTheirPorts() {
        let queries: [AgentStateQuery] = [
            .player, .actors(radius: 1024), .quest("NoSuchQuest"), .packages(reference: "player"),
            .scripts(reference: "player"),
            .objects(reference: "player"), .effects(reference: "player"),
            .nodes(reference: "player"), .flight(reference: "player"),
            .actorValue(reference: "player", name: "Health"), .global("NoSuchGlobal"), .view
        ]
        for query in queries {
            _ = answers(query)
        }
        #expect(!answers(.quest("NoSuchQuest")))
    }

    @Test func playerDebugCommandsAnswer() {
        let commands: [AgentDebugCommand] = [
            .weather(nil), .weather("NoSuchWeather"), .overlay(name: "wireframe", enabled: true),
            .channel("off"), .shadows("low"), .cartMode(true), .loadScreen(nil), .skipBink,
            .titles("off"), .raceMenu(limited: false), .skillsMenu(sky: nil, levels: 0),
            .teammate(reference: "player", on: true),
            .relationship(reference: "player", rank: 1), .passTime(hours: 1, sleeping: false),
            .perk(editorID: "NoSuchPerk", owned: true), .beastForm("none"),
            .gamepad(count: 1, press: []), .sound(on: false), .settings([]),
            .setQuestStage(quest: "NoSuchQuest", stage: 10),
            .addItem(reference: "player", item: "NoSuchItem", count: 1),
            .removeItem(reference: "player", item: "NoSuchItem", count: 1),
            .subGraphEvent(reference: "player", event: "Idle"),
            .subGraphVariable(reference: "player", name: "x", value: 1),
            .knock(reference: "player", damage: 1), .fastTravel(marker: "NoSuchMarker")
        ]
        for command in commands {
            _ = handles(command)
        }
        #expect(!handles(.setQuestStage(quest: "NoSuchQuest", stage: 10)))
    }
}

@MainActor
struct AgentEventTapTests {
    private let host = AgentHost()

    @Test func theFirstPollTapsTheStreamersEvents() {
        let seam = FakeActivationGateSeamPort()
        seam.refusals = FrameSchedule()
        host.fakeStreamer.activationGate = seam
        host.fakeStreamer.onCellDetached = FrameSchedule()
        host.fakeStreamer.onInteraction = FrameSchedule()
        host.fakeScripts.scriptsSnapshot = .empty
        host.fakeCombat.meleeCombatSnapshot = .unavailable
        let world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        world.pollEvents { _, _ in }
        #expect(host.fakeStreamer.registerCellAttachedCalls.count == 1)
    }
}
