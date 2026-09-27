// Env-gated AVIF sweep over the user's read-only active load order.

import Foundation
@testable import opensky
import Testing

struct ActorValueInformationRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryActorValueRecordAndPinsTheSkills() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: ["AVIF"])
        let definitions = index.definitions(of: "AVIF")
        var decodedCount = 0
        var unreadFieldCount = 0
        var malformedFieldCount = 0
        var incompleteNodeCount = 0
        var unknownCategoryCount = 0
        var perkNodeCount = 0

        for indexed in definitions {
            let value = try ActorValueInformation(
                record: indexed.record,
                localized: indexed.localized
            )
            decodedCount += 1
            unreadFieldCount += value.skipped.total
            perkNodeCount += value.perkTree.count
            for (kind, count) in value.skipped.counts {
                switch kind {
                case .malformedField: malformedFieldCount += count
                case .incompletePerkTreeNode: incompleteNodeCount += count
                case .unknownField: break
                }
            }
            if case .unknown = value.skillCategory {
                unknownCategoryCount += 1
                // UESP's "large 4byte info" note: the record-level CNAM only
                // means a skill category on a record that has a perk tree.
                #expect(value.perkTree.isEmpty)
            }
        }

        #expect(definitions.count >= 153)
        #expect(decodedCount == definitions.count)
        #expect(malformedFieldCount == 0)
        #expect(incompleteNodeCount == 0)
        // Every field AVIF authors is read, so nothing is silently dropped.
        #expect(unreadFieldCount == 0)

        let store = ActorValueInformationStore(index: index)
        // Fewer identities than definitions: the DLC masters override records
        // Skyrim.esm already defines.
        #expect(store.information.count >= 149)
        #expect(store.information.count <= definitions.count)
        let joined = try expectSkillsAndJoins(in: store)

        print(
            "[INFO] AVIF definitions \(definitions.count), decoded \(decodedCount), "
                + "winning \(store.information.count), skills \(store.skills.count), "
                + "perk-tree records \(store.perkTreeRecords.count), "
                + "perk-tree nodes \(perkNodeCount), joined actor values \(joined), "
                + "unread fields \(unreadFieldCount), malformed \(malformedFieldCount), "
                + "incomplete nodes \(incompleteNodeCount), "
                + "unknown categories \(unknownCategoryCount)"
        )
        for record in store.perkTreeRecords {
            print(
                "[INFO] perk tree \(record.information.editorID ?? "-") — "
                    + "\(record.displayName), actor value "
                    + "\(record.actorValueIndex.map(String.init) ?? "unjoined"), category "
                    + "\(record.information.skillCategory?.description ?? "-"), "
                    + "\(record.information.perkTree.count) perk nodes"
            )
        }
    }

    /// The eighteen skills are exactly the contiguous skill range of the
    /// vanilla actor-value table, and every one of them carries advancement
    /// parameters and a tree. Returns how many vanilla actor values found a
    /// record at all.
    private func expectSkillsAndJoins(in store: ActorValueInformationStore) throws -> Int {
        let skills = store.skills
        #expect(skills.count == 18)
        for skill in skills {
            #expect(skill.information.skillUse != nil)
            #expect(skill.information.perkTree.count > 1)
            #expect(skill.information.skillCategory != nil)
        }
        #expect(
            skills.compactMap(\.actorValueIndex)
                == Array(ActorValueIdentity.firstSkillIndex ... ActorValueIdentity.lastSkillIndex)
        )

        // Dawnguard hangs the vampire and werewolf trees off actor values that
        // are not skills, so a perk tree is the wider set of the two.
        #expect(store.perkTreeRecords.count >= skills.count)
        for record in store.perkTreeRecords where !skills.contains(record) {
            #expect(record.information.perkTree.count > 1)
        }

        try expect(editorID: "AVOneHanded", index: 6, in: store)
        try expect(editorID: "AVDestruction", index: 20, in: store)
        try expect(editorID: "AVSmithing", index: 10, in: store)

        return (0 ..< Int32(ActorValueIdentity.vanillaNames.count))
            .count { store.information(actorValueIndex: $0) != nil }
    }

    /// Where `ActorValueIdentity.recordNameAliases` comes from.
    ///
    /// Three vanilla skills carry an editor id the actor-value name table does
    /// not spell — `AVMarksman`, `AVSpeechcraft`, `AVMysticism`. Rather than
    /// assert the mapping from memory, this reads each record's own FULL string
    /// out of Skyrim.esm's string table and pins what it says, so the alias
    /// table has a standing source and breaks loudly if it is ever wrong.
    @Test(.enabled(if: Self.dataRoot != nil))
    func legacyEditorIDsNameTheSkillTheirOwnFullStringSpells() throws {
        let root = try #require(Self.dataRoot)
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root),
            pluginName: "Skyrim.esm"
        )
        let store = ActorValueInformationStore(plugins: ActivePluginFiles.load(root: root))

        for (editorID, alias) in [
            ("AVMarksman", "Marksman"),
            ("AVSpeechcraft", "Speechcraft"),
            ("AVMysticism", "Mysticism")
        ] {
            let record = try #require(store.information(editorID: editorID))
            let fullName = try #require(strings.resolve(record.information.name))
            let expected = try #require(ActorValueIdentity.recordNameAliases[alias])
            print("[INFO] \(editorID) FULL resolves to \"\(fullName)\"")
            #expect(fullName == expected)
            #expect(record.actorValueIndex == ActorValueIdentity.index(named: expected))
        }
    }

    private func expect(
        editorID: String,
        index: Int32,
        in store: ActorValueInformationStore
    ) throws {
        let record = try #require(store.information(editorID: editorID))
        #expect(record.actorValueIndex == index)
        #expect(store.information(actorValueIndex: index)?.id == record.id)
    }
}
