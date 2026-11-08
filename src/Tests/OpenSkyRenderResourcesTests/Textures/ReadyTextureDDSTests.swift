// Shipped DDS textures are stored as their own levels, ready to upload.

import Foundation
import OpenSkyAssetCache
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyRenderResources
import Testing

struct ReadyTextureDDSTests {
    @Test(arguments: [DDSPixelFormat.bc1, .bc3, .bc5, .bc7])
    func shippedTextureLevelsAreStoredAsTheyAre(format: DDSPixelFormat) throws {
        let dds = try DDSFile(data: DDSFixture.file(
            format: format,
            width: 16,
            height: 8,
            mipCount: 5
        ))
        let ready = try ReadyTextureCodec.decode(ReadyTextureCodec.encode(ReadyTexture(dds: dds)))
        #expect(ready.format == ReadyTextureFormat(format))
        #expect(ready.mipCount == dds.mipCount)
        for level in 0 ..< dds.mipCount {
            let range = ready.levelRange(level)
            let start = ready.bytes.startIndex
            #expect(Data(ready.bytes[(start + range.lowerBound) ..< (start + range.upperBound)]) ==
                dds.mipData(level: level))
            #expect(ready.bytesPerRow(level: level) == dds.bytesPerRow(level: level))
        }
    }

    @Test func xrgbTexturesGetTheOpaqueAlphaTheDirectUploadGives() throws {
        let dds = try DDSFile(data: DDSFixture.xrgb8888File(width: 4, height: 4, mipCount: 1))
        let ready = ReadyTexture(dds: dds)
        #expect(ready.format == .bgra8)
        #expect(stride(from: 3, to: ready.bytes.count, by: 4).allSatisfy { ready.bytes[$0] == 255 })
    }

    @Test func aDDSLayoutTheEngineDoesNotReadIsNotStored() throws {
        let rgb16 = DDSFixture.xrgb8888File(width: 4, height: 4, mipCount: 1, bitCount: 16)
        #expect(try ShippedTextureConverter().convert(
            path: "textures\\a.dds", bytes: rgb16, output: AssetTextureOutput()
        ) == nil)
    }

    @Test func aTexturePayloadWithMissingBytesThrows() throws {
        let dds = try DDSFile(data: DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 4))
        let payload = ReadyTextureCodec.encode(ReadyTexture(dds: dds))
        #expect(throws: ReadyTextureError.self) {
            try ReadyTextureCodec.decode(payload.prefix(payload.count - 1))
        }
    }
}
