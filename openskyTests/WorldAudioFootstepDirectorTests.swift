// WorldAudioFootstepDirector coverage over the offline-render engine: routing
// fired graph events to positional sources, gait selection, the enable toggle,
// and the panel force-trigger. Synthetic plugins and a stubbed file loader —
// no real audio device, no VFS, no extracted game file. See
// docs/engine/audio.md and docs/engine/walk-mode.md.

import AVFAudio
import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioFootstepDirectorTests {
    private typealias Fixture = WorldAudioDirectorFixture

    @Test func routesFootstepEventToAPositionalSourceAtTheFeet() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        director.handleGraphEvents(
            ["FootLeft"], gait: .walk, position: SIMD3<Float>(100, 200, 300)
        )

        #expect(engine.sources.count == 1)
        let source = try #require(engine.sources.first)
        #expect(source.isPositional)
        #expect(source.worldPosition == SIMD3<Float>(100, 200, 300))
        #expect(source.category == .footsteps)
        #expect(source.loops == false, "a footstep is a one-shot")
        #expect(director.playedFootstepCount == 1)
        #expect(director.routedEventCount == 1)
        #expect(director.lastFootstepError == nil)
    }

    /// Issue #358 end to end at this seam: the material the ground contact
    /// reports picks the impact, so the same tag on two surfaces takes two
    /// paths through the table.
    @Test func theGroundMaterialSelectsTheImpact() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        director.handleGraphEvents(
            ["FootLeft"], gait: .walk, position: .zero, material: Self.stone
        )
        #expect(engine.sources.count == 1)
        #expect(director.groundMaterial == Self.stone)

        director.handleGraphEvents(
            ["FootLeft"], gait: .walk, position: .zero, material: Self.snow
        )
        #expect(engine.sources.count == 1, "the snow impact names a sound the store lacks")
        #expect(director.lastFootstepError != nil)
        #expect(director.groundMaterial == Self.snow)
    }

    @Test func noMaterialStillResolvesThroughTheRepresentativeImpact() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        director.handleGraphEvents(["FootLeft"], gait: .walk, position: .zero)

        #expect(engine.sources.count == 1)
        #expect(director.groundMaterial == nil)
        #expect(director.materialDescription == "none")
    }

    @Test func aPinnedMaterialOverridesTheGroundContact() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)
        director.forcedMaterial = Self.snow

        director.handleGraphEvents(
            ["FootLeft"], gait: .walk, position: .zero, material: Self.stone
        )

        #expect(engine.sources.isEmpty, "the pinned snow impact names a missing sound")
        #expect(director.activeMaterial == Self.snow)
        #expect(director.materialDescription.hasSuffix("(forced)"))
    }

    @Test func eventsTheSetHasNoTagForAreDroppedSilently() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        // Every one of these is a real vanilla event name the graph fires and
        // the humanoid footstep sets do not answer to.
        director.handleGraphEvents(
            ["FootLeft2", "SoundPlay.WPNSwingBladeMedium", "moveStart"],
            gait: .walk,
            position: .zero
        )

        #expect(engine.sources.isEmpty)
        #expect(director.routedEventCount == 0)
        #expect(director.lastFootstepError == nil)
    }

    @Test func gaitPicksTheMatchingList() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        director.handleGraphEvents(["FootSprintLeft"], gait: .walk, position: .zero)
        #expect(engine.sources.isEmpty)

        director.handleGraphEvents(["FootSprintLeft"], gait: .sprint, position: .zero)
        #expect(engine.sources.count == 1)
    }

    @Test func disablingStopsRoutingWithoutTouchingOtherDirectors() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)
        director.footstepsEnabled = false

        director.handleGraphEvents(["FootLeft"], gait: .walk, position: .zero)

        #expect(engine.sources.isEmpty)
        #expect(director.routedEventCount == 0)
    }

    @Test func armatureFootstepSetOverridesTheDefaultOne() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)
        #expect(director.footstepSetDescription == FootstepStore.defaultSetEditorID)

        director.updateFootstepSet(feetArmatures: [FormID(0x900)])
        #expect(director.footstepSetDescription == "BootSet")

        // No armature declares one -> back to the default set.
        director.updateFootstepSet(feetArmatures: [FormID(0x901)])
        #expect(director.footstepSetDescription == FootstepStore.defaultSetEditorID)
    }

    @Test func forcePlayReportsWhyATagDidNotSound() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        #expect(director.forcePlayFootstep(tag: "FootLeft", gait: .walk, position: .zero)
            == nil)
        #expect(engine.sources.count == 1)

        let failure = director.forcePlayFootstep(
            tag: "FootLeft2", gait: .walk, position: .zero
        )
        #expect(failure?.contains("FootLeft2") == true)
    }

    @Test func tagsReportWhatTheCurrentGaitCanPlay() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = makeDirector(engine: engine)

        #expect(director.tags(for: .walk) == ["FootLeft"])
        #expect(director.tags(for: .sprint) == ["FootSprintLeft"])
        #expect(director.tags(for: .swim).isEmpty)
    }

    @Test func noStoreLeavesTheDirectorInertRatherThanCrashing() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = WorldAudioFootstepDirector(
            engine: engine,
            footstepStore: nil,
            soundStore: nil,
            fileLoader: { _ in Data() }
        )

        director.handleGraphEvents(["FootLeft"], gait: .walk, position: .zero)

        #expect(engine.sources.isEmpty)
        #expect(director.footstepSetDescription == "none")
        #expect(director.forcePlayFootstep(tag: "FootLeft", gait: .walk, position: .zero)
            == "no footstep records")
    }

    /// The vanilla footstep chain ends at a `.wav`, so the engine's own file
    /// entry point has to take one. Same call the director makes, with real
    /// RIFF/WAVE bytes rather than the stubbed loader.
    @Test func engineStartsAPositionalSourceFromWAVBytes() throws {
        let engine = try Fixture.makeRunningEngine()

        try engine.playPositional(
            fileData: Self.wav(),
            request: AudioPlayRequest(
                name: "fx/fst/step.wav", category: .footsteps, worldPosition: .zero
            )
        )

        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.streamer == nil, "a `.wav` plays from one buffer")
    }

    // MARK: - Fixture

    /// 16-bit mono PCM, 22.05 kHz — the shape every vanilla footstep file has.
    private static func wav() -> Data {
        var format = Data()
        format.appendUInt16(1)
        format.appendUInt16(1)
        format.appendUInt32(22050)
        format.appendUInt32(44100)
        format.appendUInt16(2)
        format.appendUInt16(16)
        var payload = Data()
        for index in 0 ..< 128 {
            payload.appendUInt16(UInt16(bitPattern: Int16(index * 100 - 6400)))
        }
        var body = Data("WAVE".utf8)
        body += Data("fmt ".utf8)
        body.appendUInt32(UInt32(format.count))
        body += format
        body += Data("data".utf8)
        body.appendUInt32(UInt32(payload.count))
        body += payload
        var out = Data("RIFF".utf8)
        out.appendUInt32(UInt32(body.count))
        out += body
        return out
    }

    /// Store shaped like vanilla's humanoid sets: a default set answering
    /// `FootLeft` while walking and `FootSprintLeft` while sprinting, a boot
    /// set the armature `0x900` declares, and nothing for swimming.
    private func makeDirector(engine: WorldAudioEngine) -> WorldAudioFootstepDirector {
        WorldAudioFootstepDirector(
            engine: engine,
            footstepStore: Self.makeFootstepStore(),
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA,
                descriptorID: 0xAAA,
                tracks: ["fx/fst/step.xwm"],
                category: .footsteps
            ),
            // Stubbed: the director hands the engine whatever bytes the loader
            // answers with, so these cases use the shared `.xwm` fixture and
            // `engineStartsAPositionalSourceFromWAVBytes` covers the real
            // RIFF/WAVE path separately.
            fileLoader: { _ in XWMFixture.file() }
        )
    }

    /// Two MATT materials the fixture table pairs with different impacts.
    private static let stone = FormID(0x501)
    private static let snow = FormID(0x502)

    private static func makeFootstepStore() -> FootstepStore {
        let lists: [FootstepGait: [FormID]] = [
            .walking: [FormID(0x100)],
            .sprinting: [FormID(0x101)]
        ]
        return FootstepStore(
            sets: [
                FootstepSet(
                    formID: FormID(0x10),
                    editorID: FootstepStore.defaultSetEditorID,
                    lists: lists
                ),
                FootstepSet(formID: FormID(0x11), editorID: "BootSet", lists: lists)
            ],
            footsteps: [
                decodeFootstep(0x100, tag: "FootLeft", set: 0x200),
                decodeFootstep(0x101, tag: "FootSprintLeft", set: 0x200)
            ],
            impactDataSets: [
                ImpactDataSet(
                    formID: FormID(0x200),
                    editorID: nil,
                    entries: [
                        ImpactDataSet.Entry(material: FormID(1), impact: FormID(0x300)),
                        ImpactDataSet.Entry(material: stone, impact: FormID(0x300)),
                        ImpactDataSet.Entry(material: snow, impact: FormID(0x301))
                    ]
                )
            ],
            // 0x301's sound is not in the sound store, so a footstep that
            // reaches it is audibly different from one that reaches 0x300:
            // nothing plays and the readout says why. That is what makes the
            // material's effect on the chain observable without a second
            // descriptor fixture.
            impacts: [
                decodeImpact(0x300, sound: 0xAAA),
                decodeImpact(0x301, sound: 0xBBB)
            ],
            armatureSets: [FormID(0x900): FormID(0x11)]
        )
    }

    private static func decodeFootstep(_ id: UInt32, tag: String, set: UInt32) -> Footstep {
        let fields = ESMFixture.field("DATA", uint32(set))
            + ESMFixture.field("ANAM", ESMFixture.zstring(tag))
        return decode(ESMFixture.record("FSTP", formID: id, data: fields)) {
            try Footstep(record: $0)
        }
    }

    private static func decodeImpact(_ id: UInt32, sound: UInt32) -> Impact {
        let fields = ESMFixture.field("SNAM", uint32(sound))
        return decode(ESMFixture.record("IPCT", formID: id, data: fields)) {
            try Impact(record: $0)
        }
    }

    private static func decode<Value>(
        _ bytes: Data,
        build: (ESMRecord) throws -> Value
    ) -> Value {
        do {
            let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
            guard case let .record(record)? = children.first else {
                preconditionFailure("synthetic fixture produced no record")
            }
            return try build(record)
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
