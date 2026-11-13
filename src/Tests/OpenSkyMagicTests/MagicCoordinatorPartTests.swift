// The coordinator's parts over a fake world: what each one forwards to the world, and
// what it answers without game data. Records are synthetic and built in code.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import Testing

@MainActor
struct MagicCoordinatorPartTests {
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private static var victimHolder: ActorValueHolder {
        ActorValueHolder(key: victim, subject: .actor(base: FormID(0x0F01)), cell: nil)
    }

    private static func payload() -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x600),
            sourcePlugin: ActiveEffectFixture.pluginName,
            caster: .player,
            entries: [],
            isHostile: true,
            ignoresResistance: false,
            projectile: nil,
            name: "Spark"
        )
    }

    /// Without game data each port call answers its empty value.
    @Test func thePortCallsAnswerEmptyWithoutGameData() {
        let coordinator = MagicCoordinator(world: FakeMagicWorld())
        coordinator.noteEffectsRestored()
        #expect(!coordinator.wantsCast(.right))
        #expect(coordinator.magicConditionResolution().state(of: .player) == nil)
        #expect(coordinator.playerGrabbedReference == nil)
        #expect(coordinator.playerKnownSpells().isEmpty)
        #expect(coordinator.raceEffectLinks(base: FormID(1), actor: .player).isEmpty)
        #expect(coordinator.timeScales == coordinator.slowTimeClock.timeScales)
        #expect(coordinator.summonFades.isEmpty)
        #expect(coordinator.applySpellHit(SpellHit(payload: Self.payload(), targets: [])) == .none)
        #expect(coordinator.playerStaff() == nil)
    }

    @Test func theCasterBridgeAsksTheWorld() {
        let world = FakeMagicWorld()
        world.gameDaysPassed = 3.5
        let coordinator = MagicCoordinator(world: world)
        let bridge = coordinator.casterBridge
        #expect(bridge.castingGameDay == MagicCore.gameDay(3.5))
        #expect(!bridge.castsFromFlyingMount(key: .player))
        _ = bridge.reportSkillUse(SkillUseEvent(actor: .player, action: .lockpick, amount: 1))
        #expect(world.skillUses.count == 1)
        #expect(bridge.spellHitCandidates().isEmpty)
        bridge.spellLanded(Self.payload(), at: SIMD3(0, 0, 0))
        #expect(coordinator.magicLights.isEmpty)
    }

    /// A target location spell lands where the caster aims; nothing aimed applies nothing.
    @Test func aLocationSpellLandsWhereTheCasterAims() throws {
        let world = FakeMagicWorld()
        let coordinator = try MagicCoordinatorTests.castingWired(world)
        let firebolt = SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        let spell = try #require(coordinator.caster?.spellbook.spells.spell(key: firebolt))
        let applied = coordinator.casterBridge.deliverToLocation(
            Self.payload(), spell: spell, caster: .player
        )
        #expect(applied == 0)
        #expect(world.aimRequests.count == 1)
    }

    /// Cure Disease and Cure Poison read the source's kind.
    @Test func archetypeLookupsSortTheEffectSources() throws {
        let coordinator = try MagicCoordinatorTests.castingWired(FakeMagicWorld())
        let lookups = coordinator.archetypeLookups
        let firebolt = SpellbookFixture.key(SpellbookFixture.Spell.firebolt)
        let sources: [ActiveEffectSource] = [
            ActiveEffectSource(kind: .spell, record: firebolt),
            ActiveEffectSource(kind: .potion, record: Self.victim),
            ActiveEffectSource(kind: .ingredient, record: Self.victim)
        ]
        #expect(sources.map(lookups.category(of:)) == [.other, .other, .other])
        #expect(!lookups.isPoison(Self.victim))
        #expect(!lookups.isPoison(.generated(1)))
    }

    /// A spell's entries pass the caster's perks first; a potion's go on as authored.
    @Test func castEffectsLandOnTheTarget() throws {
        let world = FakeMagicWorld()
        world.holders[Self.victim] = Self.victimHolder
        let coordinator = try MagicCoordinatorTests.effectsWired(world)
        for kind in [ActiveEffectSourceKind.spell, .potion] {
            let applied = coordinator.casterBridge.applyCastEffects(
                [],
                origin: (ActiveEffectFixture.pluginName, ActiveEffectSource(
                    kind: kind, record: .plugin(name: "base.esm", objectID: 0x600)
                )),
                caster: .player,
                on: Self.victimHolder
            )
            #expect(applied == 0)
        }
        coordinator.frameStep.elapseRestTime(seconds: 60)
        #expect(coordinator.frameStep.takeCommands().isEmpty)
    }

    /// An actor with no melee weapon cannot take Enhance Weapon, and holds no bound one.
    @Test func weaponArchetypesNeedAMeleeWeapon() throws {
        let world = FakeMagicWorld()
        world.holders[Self.victim] = Self.victimHolder
        let coordinator = try MagicCoordinatorTests.effectsWired(world)
        let weapons = coordinator.weaponArchetypes
        #expect(weapons.boundWeapons(on: Self.victimHolder).isEmpty)
        #expect(weapons.enhanceWeaponRefusal(on: Self.victimHolder) == .noMeleeWeapon)
        weapons.endWeaponEnhancement(on: Self.victimHolder)
        weapons.dismissBoundWeaponsOnSheathe(of: Self.victim)
        #expect(coordinator.effects?.active(on: Self.victimHolder).isEmpty == true)
    }
}

@MainActor
struct MagicCastingPartTests {
    /// A tome teaches its spell once; a book the plugin does not hold is named as such.
    @Test func readingATomeTeachesItsSpell() throws {
        let coordinator = try MagicCoordinatorTests.castingWired(FakeMagicWorld())
        let panels = coordinator.controlPanels
        let taught = panels.readSpellTome(
            FormID(SpellbookFixture.Book.healingTome),
            spell: FormID(SpellbookFixture.Spell.healing)
        )
        #expect(!taught.text.isEmpty)
        let missing = panels.readSpellTome(FormID(0xDEAD), spell: FormID(0xBEEF))
        #expect(missing.text != taught.text)
    }

    /// Select, ready, and cast a known spell, then hold the hand over real frames
    /// with the weapons drawn and sheathed. The readout counts the cues.
    @Test func aCastRunsThroughTheParts() throws {
        let world = FakeMagicWorld()
        let coordinator = try MagicCoordinatorTests.castingWired(world)
        let panels = coordinator.controlPanels
        _ = panels.readSpellTome(
            FormID(SpellbookFixture.Book.healingTome),
            spell: FormID(SpellbookFixture.Spell.healing)
        )
        _ = panels.selectNextKnownSpell()
        _ = panels.readySelectedSpell(in: .right)
        _ = panels.castReadiedSpell(in: .right)
        let step = coordinator.frameStep
        for drawn in [true, true, false] {
            _ = step.advanceCasting(
                CastingIntent(rightHeld: true, deltaTime: 0.5),
                isPlayerControlled: true,
                events: ["MRh_SpellFire_Event"],
                weaponsDrawn: drawn
            )
        }
        _ = step.advanceCasting(
            CastingIntent(deltaTime: 0.5), isPlayerControlled: true, weaponsDrawn: false
        )
        _ = coordinator.wantsCast(.right)
        #expect(panels.castingControlSnapshot.castingCueText.hasPrefix("Casting cues:"))
    }
}
