// Identity-layer tests: plugin key normalization across differing master
// lists, the documented total order, and allocator determinism.

import Foundation
@testable import opensky
import Testing

struct ReferenceKeyTests {
    @Test func sameRecordThroughDifferentMasterListsYieldsOneKey() throws {
        // "Skyrim.esm" at index 0 in one plugin, index 1 in another; the raw
        // FormIDs differ in their high byte but name the same record.
        let firstData = ESMFixture.tes4(masters: ["Skyrim.esm", "Update.esm"])
        let first = try ESMFile(data: firstData).pluginHeader()
            .formIDResolver(pluginName: "Dawnguard.esm")
        let secondData = ESMFixture.tes4(masters: ["Update.esm", "Skyrim.esm"])
        let second = try ESMFile(data: secondData).pluginHeader()
            .formIDResolver(pluginName: "Hearthfires.esm")

        let fromFirst = try #require(ReferenceKey.resolve(FormID(0x0001_3BB9), using: first))
        let fromSecond = try #require(ReferenceKey.resolve(FormID(0x0101_3BB9), using: second))
        #expect(fromFirst == fromSecond)
        #expect(fromFirst.hashValue == fromSecond.hashValue)
        #expect(!(fromFirst < fromSecond) && !(fromSecond < fromFirst))
        #expect(fromFirst == .plugin(name: "skyrim.esm", objectID: 0x013BB9))
        #expect(fromFirst.description == "skyrim.esm:013BB9")
    }

    @Test func pluginNameSpellingIsNormalized() {
        let shouting = ReferenceKey(resolved: ResolvedFormID(plugin: "SKYRIM.ESM", objectID: 0x3C))
        let titled = ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x3C))
        let mixed = ReferenceKey(resolved: ResolvedFormID(plugin: "sKyRiM.EsM", objectID: 0x3C))
        #expect(shouting == titled)
        #expect(titled == mixed)
        #expect(shouting.description == "skyrim.esm:00003C")
    }

    @Test func nullFormIDHasNoKey() {
        let resolver = FormIDResolver(pluginName: "Skyrim.esm", masters: [])
        #expect(ReferenceKey.resolve(FormID(0), using: resolver) == nil)
    }

    @Test func totalOrderIsPluginsThenNameThenObjectIDThenGenerated() {
        let ordered: [ReferenceKey] = [
            .plugin(name: "dawnguard.esm", objectID: 0x000001),
            .plugin(name: "skyrim.esm", objectID: 0x00003C),
            .plugin(name: "skyrim.esm", objectID: 0x013BB9),
            .plugin(name: "update.esm", objectID: 0x000800),
            .generated(1),
            .generated(2),
            .generated(UInt64.max)
        ]
        let shuffled: [ReferenceKey] = [
            .generated(2),
            .plugin(name: "skyrim.esm", objectID: 0x013BB9),
            .generated(UInt64.max),
            .plugin(name: "update.esm", objectID: 0x000800),
            .plugin(name: "skyrim.esm", objectID: 0x00003C),
            .generated(1),
            .plugin(name: "dawnguard.esm", objectID: 0x000001)
        ]
        #expect(shuffled.sorted() == ordered)
        // Spot-check the pairwise rules the sort depends on.
        #expect(ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xFFFFFF) < .generated(0))
        #expect(ReferenceKey.plugin(name: "a.esm", objectID: 9) < .plugin(
            name: "b.esm",
            objectID: 0
        ))
        #expect(ReferenceKey.generated(1) < .generated(2))
    }

    @Test func allocatorsAreDeterministicAndCollisionFree() {
        var left = GeneratedReferenceAllocator()
        var right = GeneratedReferenceAllocator()
        #expect(left.nextSequence == 1)

        let leftKeys = (0 ..< 64).map { _ in left.allocate() }
        let rightKeys = (0 ..< 64).map { _ in right.allocate() }
        #expect(leftKeys == rightKeys)
        #expect(Set(leftKeys).count == leftKeys.count)
        #expect(leftKeys.first == .generated(1))
        #expect(leftKeys.last == .generated(64))
        #expect(left.nextSequence == 65)
        #expect(left == right)
    }

    @Test func restoredAllocatorContinuesWithoutCollision() {
        var original = GeneratedReferenceAllocator()
        let before = (0 ..< 10).map { _ in original.allocate() }

        var restored = GeneratedReferenceAllocator(nextSequence: original.nextSequence)
        let after = (0 ..< 10).map { _ in restored.allocate() }
        #expect(Set(before).isDisjoint(with: Set(after)))
        #expect(after.first == .generated(11))
    }

    @Test func generatedKeysNeverEqualPluginKeys() {
        var allocator = GeneratedReferenceAllocator()
        let generated = (0 ..< 8).map { _ in allocator.allocate() }
        let plugins: [ReferenceKey] = [
            .plugin(name: "skyrim.esm", objectID: 0),
            .plugin(name: "skyrim.esm", objectID: 1),
            .plugin(name: "generated", objectID: 1)
        ]
        #expect(Set(generated).isDisjoint(with: Set(plugins)))
        #expect(generated[0].description == "generated:1")
    }
}
