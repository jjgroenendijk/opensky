// Enable parents over synthetic REFRs: both flag polarities, a runtime disable on
// the parent, a chain, the initially-disabled flag, and a missing parent.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorldState
import Testing

struct EnableParentResolverTests {
    private typealias Fixture = ESMFixture

    static let initiallyDisabledFlag: UInt32 = 0x800

    static func entry(
        _ objectID: UInt32,
        parent: UInt32? = nil,
        opposite: Bool = false,
        disabled: Bool = false
    ) throws -> RuntimeReferenceEntry {
        var fields: [(String, Data)] = [("NAME", Fixture.u32(0x10))]
        if let parent {
            fields.append(("XESP", Fixture.u32(parent) + Fixture.u8(opposite ? 1 : 0, 0, 0, 0)))
        }
        fields.append(("DATA", Fixture.f32(0, 0, 0, 0, 0, 0)))
        let record = try Fixture.record(
            "REFR",
            formID: objectID,
            flags: disabled ? initiallyDisabledFlag : 0,
            fields: fields
        )
        return try RuntimeReferenceEntry(
            key: .plugin(name: "skyrim.esm", objectID: objectID),
            formID: FormID(objectID),
            isPersistent: true,
            record: .reference(PlacedReference(record: record))
        )
    }

    static func resolver(
        _ entries: [RuntimeReferenceEntry],
        disabled: Set<UInt32> = []
    ) -> EnableParentResolver {
        let byFormID = Dictionary(uniqueKeysWithValues: entries.map { ($0.formID, $0) })
        var deltas: [ReferenceKey: ReferenceStateDelta] = [:]
        for objectID in disabled {
            var delta = ReferenceStateDelta()
            _ = delta.set(ReferenceEnableState.disabled.erased)
            deltas[.plugin(name: "skyrim.esm", objectID: objectID)] = delta
        }
        return EnableParentResolver(deltas: deltas) { byFormID[$0] }
    }

    @Test func aChildFollowsItsParent() throws {
        let parent = try Self.entry(0x900)
        let child = try Self.entry(0x901, parent: 0x900)
        #expect(Self.resolver([parent, child]).isEnabled(child))
        #expect(!Self.resolver([parent, child], disabled: [0x900]).isEnabled(child))
    }

    @Test func theOppositeFlagInvertsTheParent() throws {
        let parent = try Self.entry(0x900)
        let child = try Self.entry(0x901, parent: 0x900, opposite: true)
        #expect(!Self.resolver([parent, child]).isEnabled(child))
        #expect(Self.resolver([parent, child], disabled: [0x900]).isEnabled(child))
    }

    @Test func anInitiallyDisabledParentHidesItsChildren() throws {
        let parent = try Self.entry(0x900, disabled: true)
        let child = try Self.entry(0x901, parent: 0x900)
        let resolver = Self.resolver([parent, child])
        #expect(!resolver.isEnabled(parent))
        #expect(!resolver.isEnabled(child))
    }

    @Test func aDisableOnTheChildHasNoEffect() throws {
        let parent = try Self.entry(0x900)
        let child = try Self.entry(0x901, parent: 0x900)
        #expect(Self.resolver([parent, child], disabled: [0x901]).isEnabled(child))
    }

    @Test func aChainResolvesToTheRoot() throws {
        let root = try Self.entry(0x900)
        let middle = try Self.entry(0x901, parent: 0x900, opposite: true)
        let leaf = try Self.entry(0x902, parent: 0x901, opposite: true)
        let entries = [root, middle, leaf]
        #expect(Self.resolver(entries).isEnabled(leaf))
        #expect(!Self.resolver(entries, disabled: [0x900]).isEnabled(leaf))
    }

    @Test func aMissingParentLeavesTheOwnState() throws {
        let child = try Self.entry(0x901, parent: 0x900)
        let hidden = try Self.entry(0x902, parent: 0x900, disabled: true)
        let resolver = Self.resolver([child, hidden])
        #expect(resolver.hasUnresolvedParent(child))
        #expect(resolver.isEnabled(child))
        #expect(!resolver.isEnabled(hidden))
    }

    @Test func aCycleStopsAtTheDepthLimit() throws {
        let first = try Self.entry(0x900, parent: 0x901)
        let second = try Self.entry(0x901, parent: 0x900)
        _ = Self.resolver([first, second]).isEnabled(first)
    }
}
