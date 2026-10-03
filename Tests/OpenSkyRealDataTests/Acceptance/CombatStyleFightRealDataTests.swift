// Two real Skyrim.esm NPCs whose combat styles differ most in offense fight the
// player for the same seeded minute under vanilla constants. Their attack and
// block counts must differ. The report goes to `logs/combat-style-fight.log`.
// Run with `make test-real T='CombatStyleFightRealDataTests'`.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPerceptionInterface
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct CombatStyleFightRealDataTests {
    private struct Fighter {
        let npc: String
        let style: CombatStyleTuning
    }

    /// One fixed actor key, so both fights roll the same seeded sequence.
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x13BAB)
    private static let fightSteps = 60 * 60

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func differentStylesFightDifferently() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        let skyrim = try #require(plugins.first { $0.name == "Skyrim.esm" })
        let store = PresentationRecordStore(plugins: plugins)
        let resolver = ActorTemplateResolver.build(
            from: skyrim.file,
            localized: skyrim.file.isLocalized
        )
        let (calm, fierce) = try #require(Self.fighters(resolver: resolver, store: store))
        let settings = GameSettingLoader.load(root: root)
        let calmCounts = Self.fight(calm, settings: settings)
        let fierceCounts = Self.fight(fierce, settings: settings)
        let lines = [calm, fierce].enumerated().map { index, fighter in
            let counts = index == 0 ? calmCounts : fierceCounts
            return "[INFO] \(fighter.npc) style \(fighter.style.name ?? "?") "
                + "offense \(fighter.style.offensiveMultiplier) "
                + "defense \(fighter.style.defensiveMultiplier): "
                + "\(counts.attacks) attacks, \(counts.blocks) blocks in \(Self.fightSteps / 60) s"
        }
        try lines.joined(separator: "\n").write(
            to: RepositoryLogs.directory().appending(path: "combat-style-fight.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(calmCounts.attacks < fierceCounts.attacks, "\(lines)")
        #expect(calmCounts != fierceCounts)
    }

    /// The styled NPCs with the lowest and highest offense, lowest FormID first on ties.
    private static func fighters(
        resolver: ActorTemplateResolver, store: PresentationRecordStore
    ) -> (Fighter, Fighter)? {
        let styled = resolver.actors.keys.sorted().compactMap { id -> Fighter? in
            guard
                let link = try? resolver.resolveCombatStyle(base: FormID(id)).value,
                let style = store.combatStyles.resolve(link, fromPlugin: "Skyrim.esm"),
                let npc = resolver.actors[id]
            else { return nil }
            return Fighter(
                npc: npc.editorID ?? String(id, radix: 16),
                style: CombatStyleTuning(style: style.record)
            )
        }
        guard
            let low = styled
                .min(by: { $0.style.offensiveMultiplier < $1.style.offensiveMultiplier }),
            let high = styled
                .max(by: { $0.style.offensiveMultiplier < $1.style.offensiveMultiplier })
        else { return nil }
        return (low, high)
    }

    private struct Counts: Equatable {
        var attacks: Int
        var blocks: Int
    }

    private static func fight(_ fighter: Fighter, settings: GameSettingStore) -> Counts {
        let fight = NPCAIRealDataFight(
            detection: DetectionSettings.resolve(store: settings),
            combat: CombatSettings.resolve(store: settings),
            actor: actor,
            actorFeet: .zero
        )
        fight.combat.behaviorSettings = .standard
        fight.style = fighter.style
        fight.playerFeet = SIMD3(64, 0, 0)
        fight.setHostile(true)
        fight.combat.startCombat(actor, with: .player)
        for _ in 0 ..< fightSteps {
            fight.frame()
        }
        let machine = fight.combat.behaviors[actor]
        return Counts(attacks: machine?.attackCount ?? 0, blocks: machine?.blockCount ?? 0)
    }
}
