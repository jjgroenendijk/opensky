// Shipped DDS textures as ready textures, and the converter that stores them.

public import Foundation
public import OpenSkyAssetCache
import OpenSkyFormatsCore
public import OpenSkyFormatsMesh

nonisolated extension ReadyTextureFormat {
    public init(_ format: DDSPixelFormat) {
        switch format {
        case .bc1: self = .bc1
        case .bc2: self = .bc2
        case .bc3: self = .bc3
        case .bc4: self = .bc4
        case .bc5: self = .bc5
        case .bc7: self = .bc7
        case .rgba8888: self = .rgba8
        case .bgra8888, .xrgb8888: self = .bgra8
        }
    }
}

nonisolated extension ReadyTexture {
    /// The shipped levels as they are. `xrgb8888` gets an opaque alpha byte,
    /// as the direct upload does, because X is undefined.
    public init(dds: DDSFile) {
        var bytes = Data()
        for level in 0 ..< dds.mipCount {
            let level = dds.mipData(level: level)
            bytes.append(dds.format == .xrgb8888 ? Self.withOpaqueAlpha(level) : level)
        }
        self.init(
            format: ReadyTextureFormat(dds.format), width: dds.width, height: dds.height,
            mipCount: dds.mipCount, bytes: bytes
        )
    }

    static func withOpaqueAlpha(_ source: Data) -> Data {
        var result = Data(source)
        for offset in stride(from: 3, to: result.count, by: 4) {
            result[offset] = 255
        }
        return result
    }
}

/// Shipped textures, stored as they are: the BC blocks and mip levels, ready to upload.
nonisolated public struct ShippedTextureConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .texture
    }

    public var version: UInt32 {
        AssetConverterVersion.texture
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".dds")
    }

    public func convert(path _: String, bytes: Data, output: AssetTextureOutput) throws -> Data? {
        try ReadyTexture.shipped(dds: bytes).map {
            ReadyTextureCodec.encode($0.keepingLevels(fittingWithin: output.maximumSide))
        }
    }
}

nonisolated extension ReadyTexture {
    /// Nil for a DDS layout the engine does not read, so the build stores the
    /// "load the original" marker instead of failing on every run.
    public static func shipped(dds bytes: Data) throws -> ReadyTexture? {
        do {
            return try ReadyTexture(dds: DDSFile(data: bytes))
        } catch DDSError.unsupported {
            return nil
        }
    }
}
