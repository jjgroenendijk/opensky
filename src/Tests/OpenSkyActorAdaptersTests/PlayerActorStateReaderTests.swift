// The player's actor-state graph inputs come from combat, magic, keywords, and settings.

@testable import OpenSkyActorAdapters
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkySessionTesting
import Testing

@MainActor
struct PlayerActorStateReaderTests {
    private let host = ActorHost()

    @Test func aDrawnPowerAttackFillsTheCombatInputs() {
        let melee = FakeMeleeCombatRuntimePort()
        melee.state.drawStateValue = .drawn
        melee.state.attackPhaseValue = .swinging
        melee.state.isBlocking = true
        melee.strikeKindValue = .power
        melee.weaponValue = MeleeWeaponProfile(damage: 8, reach: 1, handType: .sword)
        melee.offHandValue = .dagger
        host.fakeCombat.melee = melee
        let inputs = PlayerActorStateReader(game: host).inputs(from: ActorStateGraphInputs())
        #expect(inputs.weaponDrawn)
        #expect(inputs.isAttacking)
        #expect(inputs.isPowerAttacking)
        #expect(inputs.isBlocking)
        #expect(inputs.rightHandType == CombatHandType.sword.rawValue)
        #expect(inputs.leftHandType == CombatHandType.dagger.rawValue)
    }

    @Test func aBeastRaceCastingVoicePlayerFillsTheOtherInputs() {
        host.fakeActorWorld.actorValueHolderResult = .player
        host.fakeMagicWorld.actorHasKeywordResult = true
        host.fakeMagic.wantsCastResult = true
        host.fakeMagic.shoutMachine.wantsVoice = true
        host.fakeHeadTracking.isEnabled = false
        let inputs = PlayerActorStateReader(game: host).inputs(from: ActorStateGraphInputs())
        #expect(inputs.isBeastRace)
        #expect(!inputs.weaponDrawn)
        #expect(!inputs.isBowDrawn)
        #expect(inputs.castingLeft)
        #expect(inputs.castingRight)
        #expect(inputs.wantsVoice)
        #expect(!inputs.headTracking)
        #expect(inputs.weight == 50)
    }
}
