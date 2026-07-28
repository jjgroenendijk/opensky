// GlobalStore index + the GlobalResolution lookup seam, over synthetic GLOB
// records only. See docs/engine/runtime-state.md.

import Foundation
@testable import opensky
import Testing

struct GlobalStoreTests {
    @Test func indexesByFormIDAndEditorID() throws {
        let store = try GlobalFixture.store(Self.records)
        #expect(store.count == 3)
        #expect(store.global(FormID(0x0100_0800))?.editorID == "TimeScale")
        #expect(store.global(editorID: "TimeScale")?.formID == FormID(0x0100_0800))
        // Editor-ID lookup ignores case: scripts and the console always have.
        #expect(store.global(editorID: "timescale")?.formID == FormID(0x0100_0800))
        #expect(store.formID(editorID: "GameHour") == FormID(0x0100_0801))
        #expect(store.global(FormID(0xDEAD)) == nil)
        #expect(store.global(editorID: "NoSuchGlobal") == nil)
    }

    @Test func resolvesSessionStableKeys() throws {
        let store = try GlobalFixture.store(Self.records)
        #expect(store.key(for: FormID(0x0100_0800)) == GlobalFixture.key(0x0800))
        #expect(store.key(editorID: "GameHour") == GlobalFixture.key(0x0801))
        #expect(store.key(for: FormID(0xDEAD)) == nil)
    }

    @Test func sortsByEditorID() throws {
        let store = try GlobalFixture.store(Self.records)
        #expect(store.sortedGlobals().compactMap(\.editorID)
            == ["GameHour", "TimeScale", "WeatherChanceRain"])
    }

    @Test func emptyStoreAnswersNothing() {
        #expect(GlobalStore.empty.isEmpty)
        #expect(GlobalStore.empty.global(FormID(1)) == nil)
        #expect(GlobalResolution.empty.floatValue(for: FormID(1)) == nil)
    }

    // MARK: - Resolution seam

    @Test func resolutionFallsBackToPluginDefault() throws {
        let store = try GlobalFixture.store(Self.records)
        let resolution = GlobalResolution(defaults: store)
        #expect(resolution.value(for: FormID(0x0100_0800))
            == GlobalValue(type: .float, rawValue: 20))
        #expect(resolution.floatValue(editorID: "GameHour") == 12)
        #expect(!resolution.isOverridden(FormID(0x0100_0800)))
        #expect(resolution.value(for: FormID(0xDEAD)) == nil)
        #expect(resolution.floatValue(editorID: "NoSuchGlobal") == nil)
    }

    @Test func resolutionPrefersRuntimeOverride() throws {
        let store = try GlobalFixture.store(Self.records)
        let resolution = GlobalResolution(
            defaults: store,
            overrides: [GlobalFixture.key(0x0800): GlobalValue(type: .float, rawValue: 3)]
        )
        #expect(resolution.floatValue(editorID: "TimeScale") == 3)
        #expect(resolution.isOverridden(FormID(0x0100_0800)))
        // Untouched globals still read their plugin default.
        #expect(resolution.floatValue(editorID: "GameHour") == 12)
    }

    /// The seam the #251 condition evaluator calls: a literal passes through, a
    /// `use global` comparison resolves, an unknown global is nil.
    @Test func resolvesCTDAComparisonValues() throws {
        let store = try GlobalFixture.store(Self.records)
        let resolution = GlobalResolution(
            defaults: store,
            overrides: [GlobalFixture.key(0x0801): GlobalValue(type: .short, rawValue: 5)]
        )
        #expect(resolution.comparisonValue(.value(1.5)) == 1.5)
        #expect(resolution.comparisonValue(.global(FormID(0x0100_0801))) == 5)
        #expect(resolution.comparisonValue(.global(FormID(0x0100_0800))) == 20)
        #expect(resolution.comparisonValue(.global(FormID(0xDEAD))) == nil)
    }

    @Test func resolvesConditionDecodedFromCTDAField() throws {
        // Operator greaterThan (2 << 5) with flag 0x04 (use global) set.
        var payload = Data([(2 << 5) | 0x04, 0, 0, 0])
        payload.appendUInt32(0x0100_0801) // comparison value = GLOB FormID
        payload.append(Data(count: 24))
        let field = try #require(ESMField.parseAll(
            ESMFixture.field("CTDA", payload)
        ).first)
        let condition = try #require(try Condition(ctda: field))
        #expect(condition.comparisonValue == .global(FormID(0x0100_0801)))

        let store = try GlobalFixture.store(Self.records)
        let resolution = GlobalResolution(defaults: store)
        #expect(resolution.comparisonValue(condition.comparisonValue) == 12)
    }

    @Test func resolutionBuildsFromSnapshot() throws {
        let store = try GlobalFixture.store(Self.records)
        let snapshot = WorldStateSnapshot(
            entries: [],
            nextGeneratedSequence: 1,
            globals: [WorldStateGlobalSnapshotEntry(
                key: GlobalFixture.key(0x0800),
                value: GlobalValue(type: .float, rawValue: 0.25)
            )]
        )
        let resolution = GlobalResolution(defaults: store, snapshot: snapshot)
        #expect(resolution.floatValue(editorID: "TimeScale") == 0.25)
    }

    /// Three globals: a float, a short, and one the weather tests reuse.
    private static let records = GlobalFixture.record(
        formID: 0x0100_0800, editorID: "TimeScale", type: .float, value: 20
    ) + GlobalFixture.record(
        formID: 0x0100_0801, editorID: "GameHour", type: .short, value: 12
    ) + GlobalFixture.record(
        formID: 0x0100_0802, editorID: "WeatherChanceRain", type: .short, value: 25
    )
}
