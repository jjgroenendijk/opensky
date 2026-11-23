// The combat world runs the coordinator's commands and shows kills and blood.

import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkySessionTesting
import Testing

@MainActor
struct CombatOutcomesTests {
    private let host = CombatHost()
    private let idles = FakeIdlePort()
    private var adapter: CombatWorldAdapter {
        CombatWorldAdapter(game: host)
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let meleeHit = CombatHitRecord(damage: 12, kind: .melee, attacker: foe)

    init() {
        host.fakeIdleWorld.idles = idles
    }

    @Test func commandsReachTheirPorts() {
        let perception = FakePerceptionRuntimePort()
        perception.settings = .synthetic
        host.fakePerception.runtime = perception
        adapter.run([
            .showNotification("You are being attacked"),
            .removeReference(Self.foe),
            .resetRagdolls,
            .setCombatMusic(active: true),
            .playerAttackedOutsideCombat(.swing),
            .detectionEvent(owner: .player, level: 3, at: .zero),
            .detectionEvent(owner: Self.foe, level: nil, at: .zero)
        ])
        // A record's level becomes its sound value; no level is the normal one.
        #expect(perception.noteSoundEventCalls.map(\.level) == [200, 50])
        #expect(perception.noteSoundEventCalls.map(\.owner) == [.player, Self.foe])
        #expect(host.fakeHud.showNotificationCalls == ["You are being attacked"])
        #expect(host.fakeWorldState.resetKeyCalls == [Self.foe])
        #expect(host.fakeStoryWorld.commentOnPlayerCalls.count == 1)
    }

    @Test func aStatCommandCountsAndAWeaponUseJoinsTheFavourites() {
        let bridge = FakePapyrusWorldStateBridgePort()
        host.fakeScripts.bridge = bridge
        host.fakeWorldState.miscStatsValue = MiscStatsState()
        bridge.referenceKeyResult = Self.foe
        adapter.run([.incrementStat("Backstabs"), .playerUsedWeapon(FormID(0x139B9))])
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Backstabs"])
        let saved = host.fakeWorldState.setCalls.compactMap { $0.component as? MiscStatsState }
        #expect(saved.last?.recentUses[.weapon] == [Self.foe])
    }

    @Test func aMeleeHitOnThePlayerSplattersTheScreenAndBloodiesTheWeapon() {
        adapter.run([.drewBlood(Self.meleeHit, target: .player)])
        #expect(host.fakeEffects.splatterScreenDamageCalls == [12])
        #expect(host.fakeEffects.bloodyWeaponCalls == [Self.foe])
    }

    @Test func aRangedHitOnAnNPCDrawsNoWeaponBlood() {
        let arrow = CombatHitRecord(damage: 5, kind: .ranged, attacker: .player)
        adapter.run([.drewBlood(arrow, target: Self.foe)])
        #expect(host.fakeEffects.splatterScreenDamageCalls.isEmpty)
        #expect(host.fakeEffects.bloodyWeaponCalls.isEmpty)
    }

    @Test func defaultBloodShowsWithoutRaceRecords() {
        adapter.run([.showDefaultBlood(on: Self.foe, at: .zero, melee: true)])
        #expect(host.fakeEffects.showDefaultBloodCalls.count == 1)
        #expect(!adapter.actorFlies(Self.foe))
        #expect(!adapter.actorIsChild(Self.foe))
        #expect(adapter.impactMaterial(of: Self.foe) == nil)
    }

    @Test func aPlayerKillMoveStartsTheKillCam() {
        idles.startKillMoveResult = true
        let attempt = KillMoveAttempt(
            attacker: .player, target: Self.foe, action: KillMoveAttempt.attackAction, kills: true
        )
        #expect(adapter.startKillMove(attempt))
        #expect(host.fakeCinematicCamera.playKillCamCalls.count == 1)
        idles.startKillMoveResult = false
        #expect(!adapter.startKillMove(attempt))
        #expect(!adapter.isInKillMove(Self.foe))
    }

    @Test func thePlayerAsVictimLeavesFirstPerson() {
        idles.startKillMoveResult = true
        let session = FakeGameSessionPort()
        session.movementMode = .walk
        host.gameSession = session
        let attempt = KillMoveAttempt(
            attacker: Self.foe, target: .player, action: KillMoveAttempt.attackAction, kills: true
        )
        #expect(adapter.startKillMove(attempt))
        #expect(session.setMovementModeCalls == [.thirdPerson])
        #expect(host.fakeCinematicCamera.playKillCamCalls.isEmpty)
    }

    @Test func aTargetCanBeKilledWhenZeroHealthMeansDeath() {
        host.fakeRagdollWorld.zeroHealthOutcomeResult = .dies
        #expect(adapter.canBeKilled(Self.foe, by: .player))
        #expect(host.fakeRagdollWorld.zeroHealthOutcomeCalls.map(\.key) == [Self.foe])
    }
}
