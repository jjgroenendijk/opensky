// The 19.7 acceptance chain, end to end against the user's own install
// (issue #470): find the spell tome the game ships, read it, ready the spell it
// teaches to a hand, cast it, and check that magicka went down and health came
// back up.
//
// Read-only against the install and headless: it builds the same engine types
// the app wires — `SpellbookRuntime`, `CasterRuntime` and the real
// `ActiveEffectRuntime` behind them — with no window and no renderer, so what it
// proves is the chain rather than the panel. `CombatSpellcastingPanelTests`
// covers the panel; this covers what the panel's Cast button reaches.
//
// It writes a one-line summary into gitignored `logs/` so a pull request can
// link the run. Counts and editor IDs only: no game bytes leave the machine
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct CasterAcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Forwards a cast's effect list into the real active-effect runtime, which
    /// is exactly what `GameViewController` does.
    @MainActor
    private final class RealCasterWorld: CasterWorld {
        var castingGameDay: Int32 = 0
        var effects: ActiveEffectRuntime

        init(effects: ActiveEffectRuntime) {
            self.effects = effects
        }

        func applyCastEffects(
            _ entries: [MagicItemEffect],
            fromPlugin pluginName: String,
            source: ActiveEffectSource,
            caster: ReferenceKey,
            on target: ActorValueHolder
        ) -> Int {
            effects.apply(
                entries,
                fromPlugin: pluginName,
                source: source,
                caster: caster,
                on: target
            ).count
        }
    }

    /// The load order's magic side, indexed once.
    @MainActor
    private struct Data {
        let plugin: String
        let index: RecordIndex
        let effects: MagicEffectStore
        let spells: SpellStore
        let items: ItemDefinitionStore

        init(root: GameDataRoot) throws {
            let esmURL = root.dataURL.appending(path: "Skyrim.esm")
            let file = try ESMFile(url: esmURL)
            plugin = esmURL.lastPathComponent
            index = RecordIndex(
                plugins: ActivePluginFiles.load(root: root, baseFile: file),
                recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
            )
            effects = MagicEffectStore(index: index)
            spells = SpellStore(index: index, effects: effects)
            items = ItemDefinitionStore(file: file)
        }

        /// The tome the game ships for `spell`, found by the link rather than
        /// by name: `BOOK.DATA` carries the SPEL it teaches under the 0x04 flag.
        func tome(teaching spell: ResolvedSpell) -> ItemDefinition? {
            items.definitions(of: .book).first { book in
                items.teachesSpell(book.formID)
                    .flatMap { spells.resolvedID($0, fromPlugin: plugin) } == spell.id
            }
        }

        func key(_ id: FormID) -> ReferenceKey? {
            spells.resolvedID(id, fromPlugin: plugin).map(ReferenceKey.init(resolved:))
        }
    }

    /// The same stack the app wires, minus the window: every actor starts at
    /// 500 of everything and regenerates nothing, so a number the test reads is
    /// only ever what the cast moved.
    @MainActor
    private struct Session {
        let values: ActorValueRuntime
        let spellbook: SpellbookRuntime
        let caster: CasterRuntime
        private let world: RealCasterWorld

        init(data: Data) {
            let store = WorldStateStore()
            values = ActorValueRuntime(
                store: store,
                baselines: ActorValueBaselineResolver(
                    fallback: ActorValueBaseline(
                        maximums: ActorValues(repeating: 500),
                        regenPercentPerSecond: .zero
                    )
                )
            )
            world = RealCasterWorld(
                effects: ActiveEffectRuntime(values: values, effects: data.effects)
            )
            spellbook = SpellbookRuntime(
                store: store,
                spells: data.spells,
                equipSlots: EquipSlotStore(index: data.index)
            )
            caster = CasterRuntime(spellbook: spellbook, values: values)
            caster.attach(world: world)
        }
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func aTomeTeachesASpellThatCastsForMagickaAndRestoresHealth() throws {
        let data = try Data(root: #require(Self.dataRoot))

        // The spell the acceptance picture uses: fire and forget, self
        // delivery, one instant restore-health entry.
        let spell = try #require(data.spells.spell(editorID: "FastHealing"))
        let spellKey = spell.key
        let tome = try #require(data.tome(teaching: spell))
        let tomeKey = try #require(data.key(tome.formID))
        let taught = try #require(data.items.teachesSpell(tome.formID).flatMap(data.key))
        #expect(taught == spellKey)

        let session = Session(data: data)
        let spellbook = session.spellbook
        let caster = session.caster
        let values = session.values

        // 1. Read the tome.
        let reading = spellbook.read(book: tomeKey, teaching: taught, on: .player)
        #expect(reading.taught)
        #expect(spellbook.knows(spellKey, .player))

        // 2. Ready it to the right hand.
        let readied = try spellbook.equip(spellKey, in: .right, on: .player)
        #expect(readied.hands == .rightHand)

        // 3. Hurt the player so a heal has somewhere to go, then cast.
        values.damage(.health, by: 200, on: .player)
        let healthBefore = values.current(of: .player).health
        let magickaBefore = values.current(of: .player).magicka
        #expect(caster.begin(.right, on: .player).failure == nil)
        try caster.advance(delta: #require(spell.data?.chargeTime), on: .player)
        #expect(caster.phase(of: .right) == .ready)
        let outcome = caster.release(.right, on: .player)

        #expect(outcome.isCast)
        let healthAfter = values.current(of: .player).health
        let magickaAfter = values.current(of: .player).magicka
        #expect(magickaAfter == magickaBefore - Float(spell.cost.cost))
        #expect(healthAfter > healthBefore)

        try writeSummary(
            tome: tome.editorID ?? "-",
            spell: spell.editorID ?? "-",
            cost: spell.cost.cost,
            magicka: (magickaBefore, magickaAfter),
            health: (healthBefore, healthAfter)
        )
    }

    /// One line into a run directory under gitignored `logs/`, so a pull request
    /// can link the run rather than describe it.
    private func writeSummary(
        tome: String,
        spell: String,
        cost: UInt32,
        magicka: (Float, Float),
        health: (Float, Float)
    ) throws {
        // Anchored on the source file rather than the working directory, which
        // in a test host is `/` — the same rule the other real-data suites that
        // leave artifacts behind follow.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "caster-acceptance")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let text = """
        19.7 caster acceptance, issue #470
        read tome:      \(tome)
        learned spell:  \(spell), cost \(cost)
        magicka:        \(magicka.0) -> \(magicka.1)
        health:         \(health.0) -> \(health.1)

        """
        try text.write(
            to: directory.appending(path: "acceptance.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
