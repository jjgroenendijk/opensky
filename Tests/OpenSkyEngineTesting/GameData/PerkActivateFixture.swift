// Activate perks shaped like the install's: `VampireFeed` offers two "Feed" choices
// beside the target's own action, and `PlayerWerewolfFeed` runs at once, replaces the
// action, and casts a spell. Built from docs/formats/perks.md, no install bytes.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData

public enum PerkActivateFixture {
    public static let pluginName = "PerkActivate.esm"
    public static let feed: UInt32 = 0x0800
    public static let beastFeed: UInt32 = 0x0801
    public static let beastFeedSpell: UInt32 = 0x0900
    public static let feedScript = "PRKF_FeedPerk_00000800"
    public static let beastScript = "PRKF_BeastFeed_00000801"

    public static func store() throws -> PerkStore {
        let file = try PerkFixture.plugin(
            perks: [feedRecord, beastFeedRecord],
            spells: [PerkFixture.spellRecord(
                formID: beastFeedSpell, editorID: "BeastFeedSpell", name: "Beast Feed"
            )]
        )
        let index = RecordIndex(
            plugins: [(pluginName, file)],
            recordTypes: ["SPEL", "PERK", "MGEF"]
        )
        return PerkStore(
            index: index,
            spells: SpellStore(index: index, effects: MagicEffectStore(index: index))
        )
    }

    /// Activate (14), Add Activate Choice (9), spell-with-label-and-flags (4).
    static func choice(
        label: String?, options: UInt16, fragment: UInt16, priority: UInt8, spell: UInt32? = nil
    ) -> Data {
        PerkFixture.entryPointEffect(
            entryPoint: 14,
            function: 9,
            priority: priority,
            tabs: [(runOn: 0, conditions: []), (runOn: 1, conditions: [])],
            functionType: 4,
            functionData: spell.map(PerkFixture.word),
            buttonLabel: label,
            scriptFlags: (options: options, fragmentIndex: fragment)
        )
    }

    static var feedRecord: Data {
        PerkFixture.perkRecord(
            formID: feed,
            fields: PerkFixture.fields(editorID: "VampireFeed")
                + PerkFixture.fragmentVMAD(
                    fileName: feedScript,
                    fragments: [
                        (index: 0, function: "Fragment_0"),
                        (index: 1, function: "Fragment_15")
                    ]
                )
                + choice(label: "Feed", options: 0, fragment: 1, priority: 20)
                + choice(label: "Feed in bed", options: 0, fragment: 0, priority: 10)
        )
    }

    static var beastFeedRecord: Data {
        PerkFixture.perkRecord(
            formID: beastFeed,
            fields: PerkFixture.fields(editorID: "PlayerWerewolfFeed")
                + PerkFixture.fragmentVMAD(
                    fileName: beastScript, fragments: [(index: 0, function: "Fragment_0")]
                )
                + choice(
                    label: nil,
                    options: 0x0003,
                    fragment: 0,
                    priority: 10,
                    spell: beastFeedSpell
                )
        )
    }
}
