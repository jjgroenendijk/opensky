// `state assist` over a fake combat port: each helper rule's rows reach the reply.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct AgentAssistReadoutTests {
    private let host = AgentHost()

    private var world: AgentWorldAdapter {
        AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    @Test func theAssistReadListsTracksWatchesAndProcessLevels() throws {
        var readout = CombatAssistReadout()
        readout.tracks = [
            .init(attacker: .generated(1), target: .player, aim: [1, 2, 3], refreshes: 4)
        ]
        readout.attackPicks = [
            .init(
                attacker: .generated(1),
                event: "attackPowerStart",
                isPowerAttack: true,
                knockdown: 30
            )
        ]
        readout.closeMoves = [
            .init(actor: .generated(1), current: "circle", started: 3, placeDegrees: 90)
        ]
        readout.guards = [.init(actor: .generated(1), current: "block", raised: 2, bashes: 1)]
        var watch = CombatDangerWatch()
        watch.score = 0.5
        watch.dodgeCount = 2
        readout.watches = [.generated(1): watch]
        readout.reactions = [
            HitReactionReport(
                attacker: .player, target: .generated(1), hit: HitReactionHit(),
                reaction: HitReaction()
            )
        ]
        host.fakeCombat.assistReadoutValue = readout
        host.fakePackages.processReadout = ["high": 3]
        let reply = try world.query(.assist)
        #expect(reply.value(atPath: "attackTracks.0.refreshes") == .init(4))
        #expect(reply.value(atPath: "attackPicks.0.event") == .string("attackPowerStart"))
        #expect(reply.value(atPath: "attackPicks.0.power") == .bool(true))
        #expect(reply.value(atPath: "attackPicks.0.knockdown") == .init(Float(30)))
        #expect(reply.value(atPath: "closeMoves.0.current") == .string("circle"))
        #expect(reply.value(atPath: "closeMoves.0.started") == .init(3))
        #expect(reply.value(atPath: "closeMoves.0.place") == .init(Float(90)))
        #expect(reply.value(atPath: "guards.0.current") == .string("block"))
        #expect(reply.value(atPath: "guards.0.raised") == .init(2))
        #expect(reply.value(atPath: "guards.0.bashes") == .init(1))
        #expect(reply.value(atPath: "danger.watches.0.dodges") == .init(2))
        #expect(reply.value(atPath: "danger.threats") == .array([]))
        #expect(reply.value(atPath: "autoAim") == .null)
        #expect(reply.value(atPath: "magnetism") == .null, "no session runs")
        #expect(reply.value(atPath: "hitReactions.0.largeRecoil") == .bool(false))
        #expect(reply.value(atPath: "processLevels.high") == .number(3))
    }

    @Test func theAssistReadShowsTheLastMagnetismTurn() throws {
        let session = FakeGameSessionPort()
        var tracker = MeleeMagnetismTracker()
        var frame = MeleeMagnetism.Frame()
        frame.speed = 350
        frame.strafe = 1
        frame.deltaTime = 1
        frame.weaponDrawn = true
        let enemy = MeleeMagnetism.Sighting(actor: .generated(9), position: .zero)
        _ = tracker.step(frame, sighting: enemy, eye: .zero)
        session.motion.magnetismValue = tracker
        host.gameSession = session
        host.fakeCombat.assistReadoutValue = CombatAssistReadout()
        let reply = try world.query(.assist)
        #expect(reply.value(atPath: "magnetism.enabled") == .bool(true))
        #expect(reply.value(atPath: "magnetism.turning") == .bool(true))
        #expect(reply.value(atPath: "magnetism.target") == .string("\(ReferenceKey.generated(9))"))
        #expect(reply.value(atPath: "magnetism.heading") == .init(Float(0.5)))
    }

    @Test func theProjectilesReadListsShotsArrowsAndLandings() throws {
        var readout = ProjectileReadout()
        readout.inFlight = 2
        readout.bouncing = 1
        readout.stuck = [.generated(9)]
        var landing = ProjectileReadout.Landing(outcome: "hitStatic", position: [1, 2, 3])
        landing.bounced = true
        landing.material = FormID(0x0001_0002)
        var spell = ProjectileReadout.Landing(outcome: "hitActor", position: [1, 2, 3])
        spell.spellTargets = 1
        spell.spellEntries = 2
        spell.spellRefusals = 0
        spell.spellMagnitudes = [25]
        spell.spellLanded = 1
        spell.spellSkipped = 1
        spell.spellHealthTaken = 25
        spell.spellOutcomes = ["landed", "entryConditions"]
        readout.landings = [landing, spell]
        host.fakeCombat.projectileReadoutValue = readout

        let reply = try world.query(.projectiles)

        #expect(reply.value(atPath: "inFlight") == .init(2))
        #expect(reply.value(atPath: "bouncing") == .init(1))
        #expect(reply.value(atPath: "landings.0.bounced") == .bool(true))
        #expect(reply.value(atPath: "landings.0.target") == .null)
        #expect(reply.value(atPath: "landings.0.spellTargets") == .null)
        #expect(reply.value(atPath: "landings.0.damage") == .init(Float(0)))
        #expect(reply.value(atPath: "landings.1.spellEntries") == .init(2))
        #expect(reply.value(atPath: "landings.1.spellMagnitudes.0") == .init(Float(25)))
        #expect(reply.value(atPath: "landings.1.spellHealthTaken") == .init(Float(25)))
        #expect(reply.value(atPath: "landings.1.spellOutcomes.1") == .string("entryConditions"))
        #expect(reply.value(atPath: "landings.0.spellLanded") == .null)
        #expect(reply.value(atPath: "stuck.0") == .string(ReferenceKey.generated(9).description))
    }

    @Test func theProjectilesReadShowsTheLastKillCamCheck() throws {
        var readout = ProjectileReadout()
        host.fakeCombat.projectileReadoutValue = readout
        #expect(try world.query(.projectiles).value(atPath: "lastKillCamCheck") == .null)
        var check = ProjectileReadout.KillCamCheck(
            target: .generated(4), enemiesInCombat: 1, targetAlive: true, hitKills: true,
            damage: 25, clearLine: true, distance: 130
        )
        check.chance = 50
        check.roll = 31
        check.plays = true
        readout.lastKillCamCheck = check
        host.fakeCombat.projectileReadoutValue = readout

        let reply = try world.query(.projectiles)

        #expect(reply
            .value(atPath: "lastKillCamCheck.target") == .string("\(ReferenceKey.generated(4))"))
        #expect(reply.value(atPath: "lastKillCamCheck.enemiesInCombat") == .init(1))
        #expect(reply.value(atPath: "lastKillCamCheck.chance") == .init(Float(50)))
        #expect(reply.value(atPath: "lastKillCamCheck.roll") == .init(Float(31)))
        #expect(reply.value(atPath: "lastKillCamCheck.plays") == .bool(true))
    }
}
