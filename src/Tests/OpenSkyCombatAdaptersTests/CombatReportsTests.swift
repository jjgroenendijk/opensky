// The combat world reports hits to crime, perception, and dialogue, and runs kill cams.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyProgressionInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct CombatReportsTests {
    private let host = CombatHost()
    private var adapter: CombatWorldAdapter {
        CombatWorldAdapter(game: host)
    }

    private var cinematic: CinematicCameraWorldAdapter {
        CinematicCameraWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let ally = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)

    init() {
        host.fakeDialogue.speechTimersValue = .vanilla
        host.fakeFactions.hostilityResult = .hostile
    }

    @Test func aHitIsReportedAsAnAssaultAndAsksForCombatLines() {
        let hit = ScriptHitEvent(target: Self.foe, aggressor: .player, damage: 30)
        #expect(adapter.reportScriptHit(hit) == 0)
        #expect(host.fakeCrime.reportAssaultCalls.count == 1)
        #expect(host.fakeDialogue.combatLineCalls.map(\.speaker) == [Self.foe])
        let back = ScriptHitEvent(target: .player, aggressor: Self.foe, damage: 30)
        adapter.reportScriptHit(back)
        #expect(host.fakeDialogue.combatLineCalls.map(\.speaker) == [Self.foe, Self.foe])
    }

    @Test func skillUsesAndWeaponMagicGoToTheirPorts() {
        host.fakeProgression.reportSkillUseResult = 2
        #expect(adapter.reportSkillUse(SkillUseEvent(
            actor: .player,
            action: .blockedBlow,
            amount: 5
        )) == 2)
        #expect(adapter.applyWeaponEnhancement(attacker: .player, target: Self.foe) == 0)
        #expect(host.fakeMagic.applyWeaponEnhancementCalls.count == 1)
    }

    @Test func aHostileDeathStartsAKillCamWithTheHostilesLeft() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.foe, feet: .zero),
            CombatActorObservation(key: Self.ally, feet: .zero)
        ]
        cinematic.actorDied(Self.foe)
        #expect(host.fakeCinematicCamera.playKillCamCalls.map(\.remainingHostiles) == [1])
        cinematic.actorDied(.player)
        host.fakeCinematicCamera.isPlaying = true
        cinematic.actorDied(Self.foe)
        #expect(host.fakeCinematicCamera.playKillCamCalls.count == 1)
    }

    @Test func withoutASessionTheCameraHasNoAnchors() {
        let camera = cinematic
        #expect(camera.anchorPosition(of: Self.foe) == nil)
        #expect(camera.cinematicAnchor(of: .player) == nil)
        #expect(camera.cameraShotFacts(attacker: .player, target: Self.foe) == .empty)
        #expect(camera.playerPosition == nil)
        #expect(camera.cameraPaths == nil)
        #expect(camera.cameraTrack(model: "Cameras/KillCam.nif") == nil)
        #expect(!camera.startImageSpaceModifier(Self.foe))
        #expect(CinematicCameraWorldAdapter.killCamSettings(nil).baseOdds > 0)
    }
}
