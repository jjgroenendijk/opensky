// HDPT, CLFM, EYES, BPTD, IDLE, ANIO, IDLM, CAMS, CPTH, CSTY, MESG and LSCR
// over synthetic fields. Layout sources: xEdit wbDefinitionsTES5.pas; see the
// matching docs/formats/ pages.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct CharacterRecordTests {
    private typealias Fixture = ESMFixture

    private static func condition() -> Data {
        QuestFixture.condition(functionIndex: 58).dropFirst(6)
    }

    @Test func decodesHeadPartAndKeepsUnknownPartType() throws {
        let part = try HeadPart(record: Fixture.record("HDPT", fields: [
            ("MODL", Fixture.zstring("hair.nif")), ("MODT", Data(count: 12)),
            ("DATA", Fixture.u8(0x0B)), ("PNAM", Fixture.u32(9)),
            ("HNAM", Fixture.u32(0x10)), ("HNAM", Fixture.u32(0x11)),
            ("NAM0", Fixture.u32(1)), ("NAM1", Fixture.zstring("hair.tri")),
            ("NAM0", Fixture.u32(5)), ("NAM1", Fixture.zstring("odd.tri")),
            ("TNAM", Fixture.u32(0x20)), ("CNAM", Fixture.u32(0x21)), ("RNAM", Fixture.u32(0x22))
        ]))
        #expect(part.model?.textureHashes?.count == 12)
        #expect(part.flags.contains(.playable))
        #expect(part.flags.contains(.isExtraPart))
        #expect(part.partType == .unknown(9))
        #expect(part.extraParts == [FormID(0x10), FormID(0x11)])
        #expect(part.expressionMorphPath == "hair.tri")
        #expect(part.morphPaths.count == 1)
        #expect(part.skipped.counts[.mismatch("HDPT NAM0 part type outside 0...2")] == 1)
    }

    @Test func decodesColorFormAndEyes() throws {
        let color = try ColorForm(record: Fixture.record("CLFM", flags: 0x04, fields: [
            ("CNAM", Fixture.u8(10, 20, 30, 0)), ("FNAM", Fixture.u32(1))
        ]), localized: false)
        #expect(color.color == SIMD4(10, 20, 30, 0))
        #expect(color.isPlayable)
        #expect(color.isNonPlayable)
        let eyes = try Eyes(record: Fixture.record("EYES", fields: [
            ("ICON", Fixture.zstring("eyes.dds")), ("DATA", Fixture.u8(0x01))
        ]), localized: false)
        #expect(eyes.texturePath == "eyes.dds")
        #expect(eyes.isPlayable)
    }

    @Test func decodesBodyPartsAndFindsPartByNode() throws {
        let node = Fixture.f32(1) + Fixture.u8(0x01, 1, 100, 0xFF, 50, 10) + Fixture.u16(2)
            + Data(count: 84 - 12)
        let data = try BodyPartData(record: Fixture.record("BPTD", fields: [
            ("BPTN", Fixture.zstring("Head")), ("BPNN", Fixture.zstring("NPC Head [Head]")),
            ("BPND", node),
            ("BPNN", Fixture.zstring("NPC Spine")),
            ("BPNN", Fixture.zstring("NPC Pelvis"))
        ]), localized: false)
        #expect(data.parts.count == 3)
        #expect(data.parts[0].name == LString.inline("Head"))
        #expect(data.part(onNode: "npc head [head]")?.nodeData?.actorValue == -1)
        #expect(data.parts[0].nodeData?.explodableDebrisCount == 2)
        #expect(data.skipped.isEmpty)
    }

    @Test func decodesIdleTreeLinksAndMarker() throws {
        let idle = try IdleAnimation(record: Fixture.record("IDLE", fields: [
            ("CTDA", Self.condition()), ("DNAM", Fixture.zstring("idle.hkx")),
            ("ENAM", Fixture.zstring("IdleStart")), ("ANAM", Fixture.u32(0x10, 0)),
            ("DATA", Fixture.u8(1, 3, 0x02, 0) + Fixture.u16(5))
        ]))
        #expect(idle.conditions.count == 1)
        #expect(idle.parent == FormID(0x10))
        #expect(idle.previousSibling == nil)
        #expect(idle.properties?.replayDelay == 5)
        let marker = try IdleMarker(record: Fixture.record("IDLM", fields: [
            ("IDLF", Fixture.u8(1)), ("IDLC", Fixture.u8(3)), ("IDLT", Fixture.f32(2)),
            ("IDLA", Fixture.u32(0x10, 0x11))
        ]))
        #expect(marker.idles == [FormID(0x10), FormID(0x11)])
        #expect(marker.skipped.counts[.mismatch("IDLC count differs from IDLA entries")] == 1)
        let object = try AnimatedObject(record: Fixture.record("ANIO", fields: [
            ("MODL", Fixture.zstring("chair.nif")), ("BNAM", Fixture.zstring("Unload"))
        ]))
        #expect(object.unloadEvent == "Unload")
    }

    @Test(arguments: [40, 44])
    func decodesCameraShotSizesAndPath(size: Int) throws {
        let data = Fixture.u32(1, 2, 2, 0x08) + Fixture.f32(1, 0.5, 0.2, 3, 1, 50, 100)
        let shot = try CameraShot(record: Fixture.record("CAMS", fields: [
            ("DATA", data.prefix(size)), ("MNAM", Fixture.u32(0x30))
        ]))
        #expect(shot.properties?.action == 1)
        #expect(shot.properties?.flags == 0x08)
        #expect((shot.properties?.nearTargetDistance != nil) == (size == 44))
        #expect(shot.imageSpaceModifier == FormID(0x30))
        let path = try CameraPath(record: Fixture.record("CPTH", fields: [
            ("CTDA", Self.condition()), ("ANAM", Fixture.u32(0x40, 0x41)),
            ("DATA", Fixture.u8(0x81)), ("SNAM", Fixture.u32(0x50)), ("SNAM", Fixture.u32(0x51))
        ]))
        #expect(path.parent == FormID(0x40))
        #expect(path.shots.count == 2)
        #expect(!path.requiresShots)
    }

    @Test func decodesShortCombatStyleBlocks() throws {
        let style = try CombatStyle(record: Fixture.record("CSTY", fields: [
            ("CSGD", Fixture.f32(1, 0.5)), ("CSME", Fixture.f32(1, 2, 3, 4, 5, 6, 7)),
            ("CSCR", Fixture.f32(0.2, 0.3)), ("CSLR", Fixture.f32(0.2)),
            ("CSFL", Fixture.f32(0.1)), ("DATA", Fixture.u32(0x03))
        ]))
        #expect(style.value(.defensiveMultiplier) == 0.5)
        #expect(style.value(.avoidThreatChance) == nil)
        #expect(style.value(.bashAttackMultiplier) == 6)
        #expect(style.value(.specialAttackMultiplier) == nil)
        #expect(style.value(.hoverChance) == 0.1)
        #expect(style.flags == 0x03)
    }

    @Test func decodesMessageButtonsWithTheirConditions() throws {
        let message = try GameMessage(record: Fixture.record("MESG", fields: [
            ("DESC", Fixture.zstring("Pick one")), ("INAM", Fixture.u32(0)),
            ("DNAM", Fixture.u32(1)),
            ("ITXT", Fixture.zstring("Yes")), ("CTDA", Self.condition()),
            ("ITXT", Fixture.zstring("No"))
        ]), localized: false)
        #expect(message.isMessageBox)
        #expect(message.buttons.map(\.text) == [.inline("Yes"), .inline("No")])
        #expect(message.buttons[0].conditions.count == 1)
        #expect(message.buttons[1].conditions.isEmpty)
        #expect(message.skipped.isEmpty)
    }

    @Test func decodesLoadScreen() throws {
        let screen = try LoadScreen(record: Fixture.record("LSCR", flags: 0x400, fields: [
            ("DESC", Fixture.zstring("Tip")), ("NNAM", Fixture.u32(0x60)),
            ("SNAM", Fixture.f32(2)), ("RNAM", Fixture.u16(0, 90, 0xFFF6)),
            ("ONAM", Fixture.u16(0xFFE2, 30)), ("XNAM", Fixture.f32(0, 0, 5)),
            ("MOD2", Fixture.zstring("cam.nif"))
        ]), localized: false)
        #expect(screen.displaysInMainMenu)
        #expect(screen.initialRotation == SIMD3(0, 90, -10))
        #expect(screen.rotationOffsetRange == SIMD2(-30, 30))
        #expect(screen.cameraPath == "cam.nif")
    }
}
