// The player's shout: the hold picks the words, the graph's event fires the spell, and
// the word's recovery time starts the cooldown. Records are `ShoutPluginFixture`'s
// two-word shout.

import Foundation
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
import OpenSkyProgressionInterface
import Testing

@MainActor
struct ShoutTests {
    private static let plugin = "Base.esm"
    private static let fire = ShoutGraphNames.spellFire
    private static let frame: Float = 1.0 / 60

    @MainActor
    private struct Session {
        let coordinator: MagicCoordinator
        let world: FakeMagicWorld
        let shout: ReferenceKey
        /// Frames of the key held, then one released frame, then the graph's event.
        mutating func shout(holding seconds: Float, fire: Bool = true) -> [MagicCommand] {
            var commands: [MagicCommand] = []
            var held: Float = 0
            repeat {
                commands += coordinator.advanceShout(
                    held: true, delta: ShoutTests.frame, events: [], isPlayerControlled: true
                )
                held += ShoutTests.frame
            } while held < seconds
            commands += coordinator.advanceShout(
                held: false, delta: ShoutTests.frame, events: [], isPlayerControlled: true
            )
            commands += coordinator.advanceShout(
                held: false, delta: ShoutTests.frame, events: fire ? [ShoutTests.fire] : [],
                isPlayerControlled: true
            )
            return commands
        }
    }

    private func session(allowed: Bool = true) throws -> Session {
        let file = try ShoutPluginFixture.plugin()
        let world = FakeMagicWorld()
        world.perkValues[.modShoutOK] = allowed ? 1 : 0
        let coordinator = MagicCoordinator(world: world)
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(Self.plugin, file)]),
            pluginName: Self.plugin,
            conditionRegistry: ConditionFunctionRegistry()
        )
        try coordinator.wireCasting(
            spellbook: SpellbookFixture.runtime().0, values: FixedActorValues(),
            spellPluginName: Self.plugin, baselines: nil
        )
        coordinator.wireShouts(store: ShoutStore(plugins: [(Self.plugin, file)]))
        let shout = try #require(coordinator.shouts.keys.first)
        coordinator.learnShout(shout)
        coordinator.equipShout(shout)
        return Session(coordinator: coordinator, world: world, shout: shout)
    }

    private func spell(_ id: UInt32) -> ReferenceKey {
        .plugin(name: Self.plugin.lowercased(), objectID: id)
    }

    @Test func theHoldPicksTheWords() {
        let settings = ShoutSettings.vanilla
        #expect(ShoutCore.words(held: 0.1, unlocked: 3, settings: settings) == 1)
        #expect(ShoutCore.words(held: 0.5, unlocked: 3, settings: settings) == 2)
        #expect(ShoutCore.words(held: 1, unlocked: 3, settings: settings) == 3)
        #expect(ShoutCore.words(held: 1, unlocked: 2, settings: settings) == 2)
        #expect(ShoutCore.cooldown(recovery: 45, multiplier: 0.8) == 36)
    }

    /// A tap shouts the first word on `Voice_SpellFire_Event`, and its 20 s recovery starts.
    @Test func aTapShoutsOneWordOnTheGraphEvent() throws {
        var trial = try session()
        var casts: [ReferenceKey] = []
        trial.coordinator.onSpellCast = { spell, _ in casts.append(spell) }
        let commands = trial.shout(holding: Self.frame)
        #expect(commands == [.playerGraphEvent(ShoutGraphNames.release)])
        #expect(casts == [spell(ShoutPluginFixture.Form.spell1)])
        #expect(trial.coordinator.shoutMachine.cooldownTotal == 20)
    }

    /// The fixture has two words, so a hold past `fShoutTime1` releases by itself.
    @Test func aFullHoldShoutsEveryUnlockedWord() throws {
        var trial = try session()
        var casts: [ReferenceKey] = []
        trial.coordinator.onSpellCast = { spell, _ in casts.append(spell) }
        _ = trial.shout(holding: 0.5)
        #expect(casts == [spell(ShoutPluginFixture.Form.spell2)])
        #expect(trial.coordinator.lastShout == .shouted(
            shout: "Fire Breath",
            words: 2,
            cooldown: 45
        ))
    }

    @Test func theGraphHearsTheWishOnlyWhileInhaling() throws {
        let trial = try session()
        _ = trial.coordinator.advanceShout(
            held: true, delta: Self.frame, events: [], isPlayerControlled: true
        )
        #expect(trial.coordinator.shoutMachine.wantsVoice)
        _ = trial.coordinator.advanceShout(
            held: false, delta: Self.frame, events: [], isPlayerControlled: true
        )
        #expect(!trial.coordinator.shoutMachine.wantsVoice)
    }

    @Test func theCooldownRefusesTheNextShout() throws {
        var trial = try session()
        _ = trial.shout(holding: Self.frame)
        _ = trial.shout(holding: Self.frame)
        guard case .refused(.recovering) = trial.coordinator.lastShout else {
            Issue.record("expected a recovering refusal, got \(trial.coordinator.lastShout)")
            return
        }
    }

    /// Entry point 82 on a base of 0: without `AllowShoutingPerk` nothing happens.
    @Test func modShoutOKGatesTheShout() throws {
        var trial = try session(allowed: false)
        let commands = trial.shout(holding: Self.frame)
        #expect(commands.isEmpty)
        #expect(trial.coordinator.lastShout == .refused(.notAllowed))
    }

    /// With no graph, the spell still leaves once the wait runs out.
    @Test func noGraphEventStillFiresAfterTheWait() throws {
        var trial = try session()
        var casts: [ReferenceKey] = []
        trial.coordinator.onSpellCast = { spell, _ in casts.append(spell) }
        _ = trial.shout(holding: Self.frame, fire: false)
        #expect(casts.isEmpty)
        _ = trial.coordinator.advanceShout(
            held: false, delta: 2, events: [], isPlayerControlled: true
        )
        #expect(casts.count == 1)
    }

    @Test func aWordNeedsADragonSoul() throws {
        let trial = try session()
        let file = try ShoutPluginFixture.plugin()
        let fresh = MagicCoordinator(world: FakeMagicWorld())
        fresh.wireShouts(store: ShoutStore(plugins: [(Self.plugin, file)]))
        #expect(trial.coordinator.unlockNextWord(of: trial.shout) == .refused(.wordAlreadyUnlocked))
        let world = try #require(fresh.world as? FakeMagicWorld)
        world.changeShoutKnowledge(.teachWord(.plugin(
            name: Self.plugin.lowercased(), objectID: ShoutPluginFixture.Form.word1
        )))
        #expect(fresh.unlockNextWord(of: trial.shout) == .refused(.noDragonSoul))
    }
}
