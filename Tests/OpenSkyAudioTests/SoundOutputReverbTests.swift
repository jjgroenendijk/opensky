// Output models and reverb over synthetic SOPM and REVB records: the distance
// curve, the routing rule, the reverb mapping, and the crossfade ramp.

import FormatsTesting
import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
import Testing

struct SoundOutputReverbTests {
    private typealias Fixture = ESMFixture

    static func outputModel(
        type: UInt32,
        flags: UInt8,
        send: UInt8 = 25
    ) throws -> SoundOutputModel {
        try SoundOutputModel(record: Fixture.record("SOPM", fields: [
            ("EDID", Fixture.zstring("SOMTest")),
            ("NAM1", Fixture.u8(flags, 0, 0, send)),
            ("MNAM", Fixture.u32(type)),
            (
                "ANAM",
                Fixture.u32(0) + Fixture.f32(100, 500) + Fixture.u8(100, 50, 20, 5, 0) + Fixture.u8(
                    0,
                    0,
                    0
                )
            )
        ]))
    }

    static func reverb(decay: UInt16, room: Int8, amplitude: Int8) throws -> ReverbParameters {
        try ReverbParameters(record: Fixture.record("REVB", fields: [
            ("EDID", Fixture.zstring("DungeonHall")),
            (
                "DATA",
                Fixture.u16(decay, 5000)
                    + Fixture.u8(
                        UInt8(bitPattern: room),
                        0,
                        0,
                        UInt8(bitPattern: amplitude),
                        80,
                        20,
                        40,
                        100,
                        100,
                        0
                    )
            )
        ]))
    }

    @Test func theCurveIsFlatInsideTheMinimumAndLinearBetweenPoints() throws {
        let curve =
            try #require(try AttenuationCurve(Self.outputModel(type: 0, flags: 1).attenuation))
        #expect(curve.gain(atDistance: 50) == 1)
        #expect(curve.gain(atDistance: 200) == 0.5)
        #expect(abs(curve.gain(atDistance: 250) - 0.35) < 0.0001)
        #expect(curve.gain(atDistance: 900) == 0)
    }

    @Test func typeOneRoutesFlatAndTheFlagEnablesTheCurve() throws {
        let flat = try #require(try OutputModelProfile(model: Self.outputModel(type: 1, flags: 0)))
        #expect(flat.routing == .nonPositional)
        #expect(flat.attenuation == nil)
        #expect(flat.reverbSend == 0.25)
        let spatial = try #require(try OutputModelProfile(model: Self.outputModel(
            type: 0,
            flags: 1
        )))
        #expect(spatial.routing == .positional)
        #expect(spatial.attenuation != nil)
    }

    @Test func withoutAModelTheChannelCountDecides() {
        #expect(AudioRoutingDecision.routing(profile: nil, channelCount: 1) == .positional)
        #expect(AudioRoutingDecision.routing(profile: nil, channelCount: 2) == .nonPositional)
        #expect(AudioRoutingDecision.routing(profile: nil, channelCount: nil) == .positional)
    }

    @Test func aDungeonReverbMapsToARoomAndAWetLevel() throws {
        let setting = try ReverbSetting(record: Self.reverb(decay: 2500, room: -6, amplitude: 10))
        #expect(setting.room == .mediumHall)
        #expect(setting.level == 4)
        #expect(setting.source == "DungeonHall")
    }

    @Test func aSilentOrZeroDecayRecordSwitchesReverbOff() throws {
        #expect(ReverbSetting(record: nil).isOff)
        #expect(try ReverbSetting(record: Self.reverb(decay: 0, room: -6, amplitude: 0)).isOff)
        #expect(try ReverbSetting(record: Self.reverb(decay: 1000, room: -100, amplitude: 0)).isOff)
    }

    @Test func theRoomFollowsTheDecayFloors() {
        #expect(ReverbRoom.nearest(decayMilliseconds: 193) == .smallRoom)
        #expect(ReverbRoom.nearest(decayMilliseconds: 999) == .mediumRoom)
        #expect(ReverbRoom.nearest(decayMilliseconds: 3987) == .cathedral)
    }

    @Test func theRampFadesOutBeforeItSwitchesRooms() {
        var ramp = ReverbRamp()
        ramp.setTarget(ReverbSetting(room: .largeRoom, level: 0, source: "A"))
        #expect(ramp.room == .largeRoom)
        ramp.advance(2)
        #expect(ramp.level == 0)
        ramp.setTarget(ReverbSetting(room: .cathedral, level: 10, source: "B"))
        ramp.advance(0.5)
        #expect(ramp.room == .largeRoom)
        #expect(ramp.level == -20)
        ramp.advance(0.5)
        #expect(ramp.room == .cathedral)
        ramp.advance(2)
        #expect(ramp.level == 10)
    }

    @Test func theOverrideHoldsTheAppliedLevel() {
        var ramp = ReverbRamp()
        ramp.wetOverride = 12
        #expect(ramp.appliedLevel == 12)
        ramp.wetOverride = 100
        #expect(ramp.appliedLevel == 40)
    }

    @Test func theReadoutNamesTheRecordAndTheMapping() throws {
        let record = try Self.reverb(decay: 2500, room: -6, amplitude: 10)
        var ramp = ReverbRamp()
        ramp.setTarget(ReverbSetting(record: record))
        let text = ReverbReadout.text(record: record, ramp: ramp)
        #expect(text.contains("Record: DungeonHall, decay 2500 ms, room -6 dB, reverb 10 dB"))
        #expect(text.contains("Maps to: mediumHall, wet 4.0 dB"))
    }
}
