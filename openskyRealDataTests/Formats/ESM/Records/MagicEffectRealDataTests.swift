// Env-gated MGEF sweep over the user's read-only active load order.

import Foundation
@testable import opensky
import Testing

struct MagicEffectRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryMagicEffectAndPinsVanillaIdentities() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: ["MGEF"])
        let definitions = index.definitions(of: "MGEF")
        var decodedCount = 0
        var unreadFieldCount = 0
        var malformedFieldCount = 0
        var dataSizes: [Int: Int] = [:]
        var unknownEnumCount = 0

        for indexed in definitions {
            for field in try indexed.record.fields() where field.type == "DATA" {
                dataSizes[field.data.count, default: 0] += 1
            }
            let effect = try MagicEffect(
                record: indexed.record,
                localized: indexed.localized
            )
            decodedCount += 1
            unreadFieldCount += effect.skipped.total
            malformedFieldCount += effect.skipped.counts.reduce(into: 0) { result, entry in
                if case .malformedField = entry.key {
                    result += entry.value
                }
            }
            let data = try #require(effect.data)
            unknownEnumCount += data.unknownEnumCount
        }

        #expect(definitions.count >= 1633)
        #expect(decodedCount == definitions.count)
        #expect(Set(dataSizes.keys) == [152])
        #expect(malformedFieldCount == 0)

        let store = MagicEffectStore(index: index)
        try expect(
            editorID: "AlchRestoreHealth",
            objectID: 0x03EB15,
            in: store
        )
        try expect(editorID: "AlchDamageHealth", objectID: 0x03EB42, in: store)
        try expect(editorID: "AlchDamageMagicka", objectID: 0x03A2B6, in: store)
        try expect(editorID: "AlchDamageStamina", objectID: 0x03A2C6, in: store)

        print(
            "[INFO] MGEF definitions \(definitions.count), decoded \(decodedCount), "
                + "winning \(store.effects.count), unread fields \(unreadFieldCount), "
                + "malformed fields \(malformedFieldCount), unknown enums \(unknownEnumCount)"
        )
    }

    private func expect(
        editorID: String,
        objectID: UInt32,
        in store: MagicEffectStore
    ) throws {
        let effect = try #require(store.effect(editorID: editorID))
        #expect(effect.effect.editorID == editorID)
        #expect(effect.id == ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID))
    }
}
