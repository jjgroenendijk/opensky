// AI casting acceptance on the user's install: a pinned vanilla caster, given
// its own record spells, decides to cast in a fight and damages the player.
// Headless: `CombatCastingChain` runs over the real SPEL, MGEF and EQUP
// indexes. A one-line summary goes to gitignored `logs/`.

import Foundation
@testable import OpenSkyActors
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
struct AICastingAcceptanceRealDataTests {
    /// `LvlBanditWizard`, the caster `ActorSpellBaselineRealDataTests` pins.
    private static let banditWizard = FormID(0x0001_E79F)

    /// The chain, built over the install's own stores.
    @MainActor
    private static func chain(root: GameDataRoot) throws -> (CombatCastingChain, [ReferenceKey]) {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let plugin = esmURL.lastPathComponent
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root, baseFile: file),
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
        )
        let effects = MagicEffectStore(index: index)
        let store = WorldStateStore()
        // Every actor starts at 500 of everything and regenerates nothing, so a
        // number this suite reads is only ever what a cast moved. The same
        // baseline `CasterAcceptanceRealDataTests` uses.
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 500),
                    regenPercentPerSecond: .zero
                )
            )
        )
        let spellbook = SpellbookRuntime(
            store: store,
            spells: SpellStore(index: index, effects: effects),
            equipSlots: EquipSlotStore(index: index)
        )
        let chain = CombatCastingChain(
            spellbook: spellbook,
            values: values,
            effects: ActiveEffectRuntime(
                values: values,
                effects: effects,
                conditionRegistry: .standard
            )
        )
        let baselines = ActorSpellBaselineResolver(
            actorValues: ActorValueResolver.build(
                from: file,
                localized: localized,
                pluginName: plugin
            )
        )
        let authored = spellbook.resolve(
            baselines.baseline(for: banditWizard).all,
            fromPlugin: plugin
        )
        return (chain, authored)
    }

    /// The acceptance picture: a vanilla caster's own spell list, a fight, and
    /// the player's health going down because of a spell rather than a fist.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func aVanillaCasterCastsAtThePlayerAndTheDamageLands() throws {
        let (chain, authored) = try Self.chain(root: #require(RealDataEnvironment.dataRoot))
        chain.grant(authored)
        // Well outside weapon reach, so a swing cannot be what lands.
        chain.casterFeet = SIMD3(900, 0, 0)
        let magickaBefore = chain.casterMagicka
        let options = chain.options
        #expect(!options.isEmpty)

        chain.advance(seconds: 6)

        let machine = try #require(chain.combat.behaviors[CombatCastingChain.caster])
        #expect(machine.castCount > 0)
        #expect(machine.attackCount == 0)
        #expect(chain.casterMagicka < magickaBefore)
        // The spell reached the player and took health off: a vanilla caster's
        // own records, through the decision, the cast loop, the 19.8 delivery
        // and the effect runtime.
        #expect(!chain.spellHits.isEmpty)
        #expect(chain.playerHealth < 500)

        try writeSummary(chain: chain, authored: authored, options: options)
    }

    /// A caster whose magicka is gone stops casting and closes to swing, which
    /// is the self-preservation minimum stated in the issue.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func aDrainedVanillaCasterFallsBackToItsHands() throws {
        let (chain, authored) = try Self.chain(root: #require(RealDataEnvironment.dataRoot))
        chain.grant(authored)
        chain.values.set(.magicka, to: 0, on: chain.casterHolder)
        chain.casterFeet = SIMD3(60, 0, 0)

        chain.advance(seconds: 4)

        let machine = try #require(chain.combat.behaviors[CombatCastingChain.caster])
        #expect(machine.castCount == 0)
        #expect(machine.attackCount > 0)
    }

    /// One summary into a run directory under gitignored `logs/`.
    @MainActor
    private func writeSummary(
        chain: CombatCastingChain,
        authored: [ReferenceKey],
        options: [CombatSpellOption]
    ) throws {
        let named = options.compactMap { option in
            chain.spellbook.record(option.spell).map { spell in
                String(
                    format: "  %@ cost %.0f range %.0f",
                    spell.editorID ?? spell.key.description,
                    option.cost,
                    option.range
                )
            }
        }
        // Resolved through `RepositoryLogs` rather than the working directory,
        // which in a test host is `/`.
        let directory = try RepositoryLogs.directory("ai-casting-acceptance")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let machine = chain.combat.behaviors[CombatCastingChain.caster]
        let text = """
        19.10 AI casting acceptance, issue #473
        caster:         LvlBanditWizard (0001E79F)
        known spells:   \(authored.count)
        castable:       \(options.count)
        \(named.joined(separator: "\n"))
        casts begun:    \(machine?.castCount ?? 0)
        swings:         \(machine?.attackCount ?? 0)
        spells landed:  \(chain.spellHits.count)
        projectiles:    \(chain.firedProjectiles.count)
        player health:  \(chain.playerHealth)
        caster magicka: \(chain.casterMagicka)

        """
        try text.write(
            to: directory.appending(path: "summary.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
