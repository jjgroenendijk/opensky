// Render models stored in the asset cache as flattened arrays.

public import Foundation
public import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyFormatsMesh

/// Flattened render models. Skinned character meshes need the character skeleton
/// and particle models need their emitters, so both keep the NIF path.
nonisolated public struct ReadyMeshConverter: AssetConverting {
    public init() {}

    public var kind: AssetCacheKind {
        .mesh
    }

    public var version: UInt32 {
        AssetConverterVersion.mesh
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".nif")
    }

    public func convert(path: String, bytes: Data, output _: AssetTextureOutput) throws -> Data? {
        let file = try NIFFile(data: bytes)
        if
            path.hasPrefix("meshes\\actors\\character\\"),
            file.blocks.contains(where: { $0.typeName == "NiSkinData" })
        {
            return nil
        }
        guard attempt({ try file.particleSystems() })?.isEmpty ?? false else { return nil }
        return try ModelCacheCodec.encode(file.model(skeleton: nil))
    }
}
