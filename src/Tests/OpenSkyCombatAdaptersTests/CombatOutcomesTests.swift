// The combat world runs the coordinator's commands and shows kills and blood.

import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
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
        adapter.run([
            .showNotification("You are being attacked"),
            .removeReference(Self.foe),
            .resetRagdolls,
            .setCombatMusic(active: true),
            .playerAttackedOutsideCombat(.swing),
            .detectionEvent(owner: .player, at: .zero)
        ])
        #expect(host.fakeHud.showNotificationCalls == ["You are being attacked"])
        #expect(host.fakeWorldState.resetKeyCalls == [Self.foe])
        #expect(host.fakeStoryWorld.commentOnPlayerCalls.count == 1)
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

    @Test func aTargetCanBeKilledWhenZeroHealthMeansDeath() {
        host.fakeRagdollWorld.zeroHealthOutcomeResult = .dies
        #expect(adapter.canBeKilled(Self.foe, by: .player))
        #expect(host.fakeRagdollWorld.zeroHealthOutcomeCalls.map(\.key) == [Self.foe])
    }
}
