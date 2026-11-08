// Every field the controller and interpolator decoders read, over synthetic blocks
// (docs/formats/nif-controllers.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFControllerFieldTests {
    private func block(_ type: String, _ data: Data, strings: [String] = []) throws -> Any? {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)], strings: strings))
        return try NIFBlockDecoders.decode(file.blocks[0], header: file.header)
    }

    @Test func timeControllerReadsItsFixedSize() throws {
        let data = NIFBlockFixture.timeController(flags: 0x8, target: 7)
        var reader = BinaryReader(data)
        let controller = try NIFTimeController(reader: &reader)
        #expect(data.count - reader.bytesRemaining == NIFTimeController.size)
        #expect(controller.targetRef == 7)
        #expect(controller.isActive)

        var inactive = BinaryReader(NIFBlockFixture.timeController(flags: 0))
        #expect(try !NIFTimeController(reader: &inactive).isActive)
    }

    @Test func lagBoneKeepsItsRates() throws {
        var data = NIFBlockFixture.timeController(target: 3)
        data.append(NIFBlockFixture.floats([1.5, 2.5, 30]))
        let bone = try #require(block("BSLagBoneController", data) as? NIFLagBoneController)
        #expect(bone.base.targetRef == 3)
        #expect(bone.linearVelocity == 1.5)
        #expect(bone.linearRotation == 2.5)
    }

    @Test func lightningKeepsEveryBoltSetting() throws {
        var data = NIFBlockFixture.timeController(target: 2)
        (10 ..< 19).forEach { data.appendRef(Int32($0)) }
        [4, 3, 2].forEach { data.appendUInt16($0) }
        data.append(NIFBlockFixture.floats([64, 8, 2, 0.5, 1.5]))
        data.append(contentsOf: [1, 0, 1])
        data.appendRef(9)
        let bolt = try #require(block(
            "BSProceduralLightningController", data
        ) as? NIFLightningController)
        #expect(bolt.base.targetRef == 2)
        #expect(bolt.interpolatorRefs == Array(10 ..< 19))
        #expect([bolt.subdivisions, bolt.branches, bolt.branchVariation] == [4, 3, 2])
        #expect([bolt.length, bolt.lengthVariation, bolt.width] == [64, 8, 2])
        #expect(bolt.childWidthMultiplier == 0.5)
        #expect(bolt.arcOffset == 1.5)
        #expect(bolt.fadesMainBolt)
        #expect(!bolt.fadesChildBolts)
        #expect(bolt.animatesArcOffset)
        #expect(bolt.shaderPropertyRef == 9)
    }

    @Test func boneLODAndManagerKeepTheirBase() throws {
        var lod = NIFBlockFixture.timeController(target: 4)
        lod.append(NIFBlockFixture.uint32(1))
        lod.append(NIFBlockFixture.uint32(0))
        lod.append(NIFBlockFixture.uint32(0))
        let levels = try #require(block("NiBSBoneLODController", lod) as? NIFBoneLODController)
        #expect(levels.lod == 1)
        #expect(levels.base.targetRef == 4)

        var manager = NIFBlockFixture.timeController(flags: 0x28, target: 5)
        manager.append(0)
        manager.append(NIFBlockFixture.uint32(0))
        manager.appendRef(-1)
        let sequences = try #require(block("NiControllerManager", manager) as? NIFControllerManager)
        #expect(sequences.base.targetRef == 5)

        var palette = Data()
        palette.appendRef(6)
        palette.append(NIFBlockFixture.uint32(0))
        let objects = try #require(block("NiDefaultAVObjectPalette", palette) as? NIFObjectPalette)
        #expect(objects.sceneRef == 6)
    }

    @Test func singleInterpolatorControllersKeepTheirKind() throws {
        var color = NIFBlockFixture.interpolatedController(interpolator: 2)
        color.append(NIFBlockFixture.uint32(0))
        let shader = try #require(block(
            "BSLightingShaderPropertyColorController", color
        ) as? NIFShaderPropertyController)
        #expect(shader.kind.isColor)
        #expect(!NIFShaderPropertyController.Kind.effectFloat.isColor)

        var extra = NIFBlockFixture.interpolatedController(interpolator: 3)
        extra.append(NIFBlockFixture.uint32(0))
        let named = try #require(block(
            "NiFloatExtraDataController", extra, strings: ["Fade"]
        ) as? NIFExtraDataController)
        #expect(named.base.interpolatorRef == 3)
        #expect(named.extraDataName == "Fade")

        let fieldOfView = try #require(block(
            "BSFrustumFOVController", NIFBlockFixture.interpolatedController(interpolator: 8)
        ) as? NIFPlainController)
        #expect(fieldOfView.kind == .frustumFieldOfView)
        #expect(fieldOfView.base.interpolatorRef == 8)
    }

    @Test func blendItemsKeepTheirWeights() throws {
        var data = Data([0, 1])
        data.append(NIFBlockFixture.floats([0.25]))
        data.append(Data(count: 20))
        data.appendRef(7)
        data.append(NIFBlockFixture.floats([0.5, 1]))
        data.append(3)
        data.append(NIFBlockFixture.floats([0.75, 2]))
        let blend = try #require(block(
            "NiBlendFloatInterpolator", data
        ) as? NIFBlendInterpolator)
        let item = try #require(blend.items.first)
        #expect(blend.weightThreshold == 0.25)
        #expect(item.weight == 0.5)
        #expect(item.normalizedWeight == 1)
        #expect(item.priority == 3)
        #expect(item.easeSpinner == 0.75)
        #expect(blend.value == .float(2))
    }

    @Test func pathKeepsItsBankAndFollowSettings() throws {
        let path = try #require(block("NiPathInterpolator", NIFBlockFixture.pathInterpolator(
            flags: 0x30, bank: (-1, 0.5), smoothing: 0.25, followAxis: 2,
            pathData: 1, percentData: 2
        )) as? NIFPathInterpolator)
        #expect(path.bankDirection == -1)
        #expect(path.maximumBankAngle == 0.5)
        #expect(path.smoothing == 0.25)
        #expect(path.followAxis == 2)
        #expect(path.follows)
        #expect(path.hasConstantVelocity)
    }

    @Test func lookAtKeepsItsTargetAndPose() throws {
        var data = Data()
        data.appendUInt16(0x5)
        data.appendRef(3)
        data.appendUInt32(0)
        data.append(NIFBlockFixture.floats([1, 2, 3, 1, 0, 0, 0, 2]))
        [4, 5, 6].forEach { data.appendRef(Int32($0)) }
        let lookAt = try #require(block(
            "NiLookAtInterpolator", data, strings: ["Head"]
        ) as? NIFLookAtInterpolator)
        #expect(lookAt.lookAtRef == 3)
        #expect(lookAt.lookAtName == "Head")
        #expect(lookAt.translation == SIMD3(1, 2, 3))
        #expect(lookAt.rotation == simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        #expect(lookAt.scale == 2)
        #expect(lookAt.translationInterpolatorRef == 4)
        #expect(lookAt.rollInterpolatorRef == 5)
        #expect(lookAt.scaleInterpolatorRef == 6)
        #expect(lookAt.lookAxis == SIMD3(0, 0, -1))
    }
}
