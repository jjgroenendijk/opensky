// Milestone 3.5 sky/water scene-build cases. Fixtures live beside the core
// CellSceneBuilder tests; every byte is synthetic, never game content.

import Foundation
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice)) func buildsSkyAndWRLDDefaultWater() throws {
        let scene = try build(pluginData: plugin(
            cellFlags: 0x0002,
            worldDefaultWaterHeight: -14000,
            worldWaterType: 0x18,
            waterRecords: waterRecord(
                formID: 0x18,
                shallow: SIMD3(10, 20, 30),
                deep: SIMD3(40, 50, 60),
                reflection: SIMD3(70, 80, 90)
            )
        ))
        #expect(scene.renderScene.sky != nil)
        let water = try #require(scene.renderScene.water.first)
        let translation = water.modelMatrix.columns.3
        let expected = SIMD3<Float>(24576, -8192, -14000)
        #expect(SIMD3(translation.x, translation.y, translation.z) == expected)
        #expect(water.shallowColor == SIMD3<Float>(10, 20, 30) / 255)
        #expect(water.deepColor == SIMD3<Float>(40, 50, 60) / 255)
        #expect(water.reflectionColor == SIMD3<Float>(70, 80, 90) / 255)
        #expect(scene.summary.waterPlaneCount == 1)
        #expect(scene.renderScene.drawCount == 2) // WRLD fallback terrain + water
    }

    @Test(.enabled(if: Self.hasDevice)) func cellWaterOverridesWRLD() throws {
        let scene = try build(pluginData: plugin(
            cellFlags: 0x0002,
            cellWaterHeightBits: Float(-12345).bitPattern,
            cellWaterType: 0x19,
            worldDefaultWaterHeight: -14000,
            worldWaterType: 0x18,
            waterRecords: waterRecord(formID: 0x18)
                + waterRecord(
                    formID: 0x19,
                    shallow: SIMD3(200, 100, 50),
                    deep: SIMD3(20, 10, 5),
                    reflection: SIMD3(80, 90, 100)
                )
        ))
        let water = try #require(scene.renderScene.water.first)
        #expect(water.modelMatrix.columns.3.z == -12345)
        #expect(water.shallowColor == SIMD3<Float>(200, 100, 50) / 255)
    }

    @Test(.enabled(if: Self.hasDevice)) func inheritsParentWorldWaterData() throws {
        let parent = worldRecord(
            formID: 0x2A,
            editorID: "ParentWorld",
            defaultWaterHeight: -9000,
            waterType: 0x18
        )
        let scene = try build(pluginData: plugin(
            cellFlags: 0x0002,
            worldDefaultWaterHeight: -1000,
            worldWaterType: 0x19,
            parentWorld: 0x2A,
            parentFlags: 0x0009,
            extraWorldRecords: parent,
            waterRecords: waterRecord(
                formID: 0x18,
                shallow: SIMD3(12, 34, 56),
                deep: SIMD3(7, 8, 9),
                reflection: SIMD3(90, 80, 70)
            ) + waterRecord(formID: 0x19)
        ))
        let water = try #require(scene.renderScene.water.first)
        #expect(water.modelMatrix.columns.3.z == -9000)
        #expect(water.shallowColor == SIMD3<Float>(12, 34, 56) / 255)
    }

    @Test(.enabled(if: Self.hasDevice)) func noWaterSentinelSuppressesWRLDFallback() throws {
        let scene = try build(pluginData: plugin(
            cellFlags: 0x0002,
            cellWaterHeightBits: 0x7F7F_FFFF,
            worldDefaultWaterHeight: -14000
        ))
        #expect(scene.renderScene.water.isEmpty)
        #expect(scene.summary.waterPlaneCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func noSkyWorldSuppressesSky() throws {
        let scene = try build(pluginData: plugin(worldFlags: 0x20))
        #expect(scene.renderScene.sky == nil)
    }

    func waterRecord(
        formID: UInt32,
        shallow: SIMD3<UInt8> = SIMD3(20, 80, 110),
        deep: SIMD3<UInt8> = SIMD3(5, 20, 40),
        reflection: SIMD3<UInt8> = SIMD3(100, 150, 190)
    ) -> Data {
        var dnam = Data(count: 40)
        for color in [shallow, deep, reflection] {
            dnam.append(contentsOf: [color.x, color.y, color.z, 0])
        }
        dnam.append(Data(count: 228 - dnam.count))
        return ESMFixture.record(
            "WATR",
            formID: formID,
            data: ESMFixture.field("DNAM", dnam)
        )
    }

    func worldRecord(
        formID: UInt32,
        editorID: String,
        defaultWaterHeight: Float? = nil,
        waterType: UInt32? = nil,
        flags: UInt8 = 0,
        parent: UInt32? = nil,
        parentFlags: UInt16 = 0
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            var wnam = Data()
            wnam.appendUInt32(parent)
            var pnam = Data()
            pnam.appendUInt16(parentFlags)
            fields += ESMFixture.field("WNAM", wnam)
                + ESMFixture.field("PNAM", pnam)
        }
        if let defaultWaterHeight {
            var dnam = Data()
            dnam.appendFloat32(-27000)
            dnam.appendFloat32(defaultWaterHeight)
            fields += ESMFixture.field("DNAM", dnam)
        }
        if let waterType {
            var nam2 = Data()
            nam2.appendUInt32(waterType)
            fields += ESMFixture.field("NAM2", nam2)
        }
        fields += ESMFixture.field("DATA", Data([flags]))
        return ESMFixture.record("WRLD", formID: formID, data: fields)
    }

    func cellFields(
        editorID: String,
        grid: (x: Int32, y: Int32),
        flags: UInt16,
        waterHeightBits: UInt32?,
        waterType: UInt32?
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: grid.x))
        xclc.appendUInt32(UInt32(bitPattern: grid.y))
        xclc.appendUInt32(0)
        fields += ESMFixture.field("XCLC", xclc)
        if flags != 0 {
            var data = Data()
            data.appendUInt16(flags)
            fields += ESMFixture.field("DATA", data)
        }
        if let waterHeightBits {
            var xclw = Data()
            xclw.appendUInt32(waterHeightBits)
            fields += ESMFixture.field("XCLW", xclw)
        }
        if let waterType {
            var xcwt = Data()
            xcwt.appendUInt32(waterType)
            fields += ESMFixture.field("XCWT", xcwt)
        }
        return fields
    }
}
