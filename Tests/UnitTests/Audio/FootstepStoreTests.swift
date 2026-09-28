// Footstep tag -> sound resolution over synthetic records: the chain the
// footstep director walks (issue #352). See docs/engine/audio.md.

import Foundation
@testable import opensky
import Testing

struct FootstepStoreTests {
    @Test func resolvesTagThroughTheWholeChain() {
        let store = Self.store()

        let resolved = store.resolve(tag: "FootLeft", gait: .walking, in: Self.walkSet)
        #expect(resolved?.footstep.editorID == "WalkLeft")
        #expect(resolved?.impact.formID == FormID(0x300))
        #expect(resolved?.sound == FormID(0x400))
    }

    @Test func tagComparisonIgnoresCase() {
        let store = Self.store()

        #expect(store.resolve(tag: "footleft", gait: .walking, in: Self.walkSet) != nil)
    }

    @Test func gaitSelectsItsOwnList() {
        let store = Self.store()

        #expect(store.resolve(tag: "FootLeft", gait: .running, in: Self.walkSet)?.sound
            == FormID(0x401))
        // The walking list has no sprint tag at all.
        #expect(store.resolve(tag: "FootSprintLeft", gait: .walking, in: Self.walkSet) == nil)
    }

    @Test func brokenLinksResolveToNothingRatherThanThrowing() {
        let store = Self.store()

        // A tag the set never names.
        #expect(store.resolve(tag: "FootLeft2", gait: .walking, in: Self.walkSet) == nil)
        // A footstep whose impact data set is missing from the plugin.
        #expect(store.resolve(tag: "FootRight", gait: .walking, in: Self.walkSet) == nil)
        // A gait list that is empty.
        #expect(store.resolve(tag: "FootLeft", gait: .swimming, in: Self.walkSet) == nil)
    }

    /// The whole point of issue #358: the same tag on two surfaces resolves to
    /// two impacts, and a surface the table does not list falls back to the
    /// representative entry rather than to silence.
    @Test func theMaterialSelectsTheImpact() {
        let store = Self.store()

        #expect(store.resolve(
            tag: "FootLeft", gait: .walking, in: Self.walkSet, material: Self.snow
        )?.sound == FormID(0x402))
        #expect(store.resolve(
            tag: "FootLeft", gait: .walking, in: Self.walkSet, material: Self.stone
        )?.sound == FormID(0x400))
        #expect(store.resolve(
            tag: "FootLeft", gait: .walking, in: Self.walkSet, material: FormID(0x999)
        )?.sound == FormID(0x400))
        #expect(store.resolve(
            tag: "FootLeft", gait: .walking, in: Self.walkSet
        )?.sound == FormID(0x400))
    }

    @Test func tagsReportTheGaitListInRecordOrder() {
        let store = Self.store()

        #expect(store.tags(for: .walking, in: Self.walkSet) == ["FootLeft", "FootRight"])
        #expect(store.tags(for: .swimming, in: Self.walkSet).isEmpty)
    }

    @Test func armatureSelectionPrefersTheFirstArmatureThatDeclaresASet() {
        let store = Self.store()

        #expect(store.set(forArmatures: [FormID(0x900)])?.formID == FormID(0x10))
        // Skips an armature with no SNDD and takes the next one.
        #expect(store.set(forArmatures: [FormID(0x901), FormID(0x900)])?.formID
            == FormID(0x10))
        // No armature declares one -> the default set.
        #expect(store.set(forArmatures: [FormID(0x901)])?.editorID == "DefaultFootstepSet")
        #expect(store.set(forArmatures: [])?.editorID == "DefaultFootstepSet")
    }

    @Test func everyLocomotionGaitMapsToItsOwnFootstepList() {
        let pairs: [(LocomotionGait, FootstepGait)] = [
            (.walk, .walking), (.run, .running), (.sprint, .sprinting),
            (.sneak, .sneaking), (.swim, .swimming)
        ]
        for (gait, expected) in pairs {
            #expect(WorldAudioFootstepDirector.footstepGait(for: gait) == expected)
        }
    }

    // MARK: - Fixture

    /// One walk-and-run set: walk carries a resolvable `FootLeft` and a
    /// `FootRight` whose impact data set is missing, run carries a resolvable
    /// `FootLeft`, and swimming carries nothing.
    static let walkSet = FootstepSet(
        formID: FormID(0x10),
        editorID: "BootSet",
        lists: [
            .walking: [FormID(0x100), FormID(0x102)],
            .running: [FormID(0x101)]
        ]
    )

    private static let defaultSet = FootstepSet(
        formID: FormID(0x11),
        editorID: FootstepStore.defaultSetEditorID,
        lists: [.walking: [FormID(0x100)]]
    )

    private static func store() -> FootstepStore {
        FootstepStore(
            sets: [walkSet, defaultSet],
            footsteps: [
                footstep(0x100, "WalkLeft", tag: "FootLeft", set: 0x200),
                footstep(0x101, "RunLeft", tag: "FootLeft", set: 0x201),
                footstep(0x102, "WalkRight", tag: "FootRight", set: 0x2FF)
            ],
            impactDataSets: [
                dataSet(0x200, impact: 0x300),
                dataSet(0x201, impact: 0x301)
            ],
            impacts: [
                impact(0x300, sound: 0x400),
                impact(0x301, sound: 0x401),
                impact(0x302, sound: 0x402)
            ],
            armatureSets: [FormID(0x900): FormID(0x10)]
        )
    }

    private static func footstep(
        _ id: UInt32,
        _ editorID: String,
        tag: String,
        set: UInt32
    ) -> Footstep {
        decode("FSTP") {
            ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", uint32(set))
                + ESMFixture.field("ANAM", ESMFixture.zstring(tag))
        } build: { try Footstep(record: $0) } id: { id }
    }

    /// The two MATT materials the walking table pairs: stone twice, so it is
    /// also the representative entry, and snow once.
    static let stone = FormID(0x501)
    static let snow = FormID(0x502)

    /// A table pairing the given impact with stone twice and 0x302 with snow.
    /// Stone is therefore both an exact answer and the representative one, so
    /// the two paths are told apart by the snow case rather than by luck.
    private static func dataSet(_ id: UInt32, impact: UInt32) -> ImpactDataSet {
        ImpactDataSet(
            formID: FormID(id),
            editorID: nil,
            entries: [
                ImpactDataSet.Entry(material: stone, impact: FormID(impact)),
                ImpactDataSet.Entry(material: FormID(1), impact: FormID(impact)),
                ImpactDataSet.Entry(material: snow, impact: FormID(0x302))
            ]
        )
    }

    private static func impact(_ id: UInt32, sound: UInt32) -> Impact {
        decode("IPCT") {
            ESMFixture.field("SNAM", uint32(sound))
        } build: { try Impact(record: $0) } id: { id }
    }

    /// Builds one synthetic record and decodes it. A fixture that cannot be
    /// decoded is a bug in the test, not in the engine, so it traps here rather
    /// than making every call site throwing.
    private static func decode<Value>(
        _ type: String,
        fields: () -> Data,
        build: (ESMRecord) throws -> Value,
        id: () -> UInt32
    ) -> Value {
        let bytes = ESMFixture.record(type, formID: id(), data: fields())
        do {
            let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
            guard case let .record(record)? = children.first else {
                preconditionFailure("synthetic \(type) fixture produced no record")
            }
            return try build(record)
        } catch {
            preconditionFailure("synthetic \(type) fixture failed: \(error)")
        }
    }

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
