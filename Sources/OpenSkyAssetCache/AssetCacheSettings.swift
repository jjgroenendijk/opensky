// The asset optimisation settings, read from the one player settings store, so
// the app and openskycli convert and read with the same texture output and folder.

import Foundation
import OpenSkyGameData

/// Reading optimised files straight into GPU memory with Metal fast resource loading.
nonisolated public struct DirectGPULoading: Equatable, Sendable {
    public var isEnabled: Bool
    public var textures: Bool
    /// Off by default (docs/engine/fast-mesh-loading.md).
    public var meshes: Bool
    /// Internal disks only by default: from an external disk it saves no time.
    public var allDisks: Bool

    public init(
        isEnabled: Bool = true,
        textures: Bool = true,
        meshes: Bool = false,
        allDisks: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.textures = textures
        self.meshes = meshes
        self.allDisks = allDisks
    }

    public var loadsTextures: Bool {
        isEnabled && textures
    }

    public var loadsMeshes: Bool {
        isEnabled && meshes
    }
}

nonisolated public struct AssetCacheSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var textureOutput: AssetTextureOutput
    /// Nil uses the default folder.
    public var folder: URL?
    public var directLoad: DirectGPULoading
    /// The kinds a conversion writes and the game reads; the others load from the archives.
    public var kinds: Set<AssetCacheKind>

    public init(
        isEnabled: Bool = true,
        textureOutput: AssetTextureOutput = AssetTextureOutput(),
        folder: URL? = nil,
        directLoad: DirectGPULoading = DirectGPULoading(),
        kinds: Set<AssetCacheKind> = Set(AssetCacheKind.built)
    ) {
        self.isEnabled = isEnabled
        self.textureOutput = textureOutput
        self.folder = folder
        self.directLoad = directLoad
        self.kinds = kinds
    }

    public func effectiveFolder() throws -> URL {
        try folder ?? AssetCacheLocation.defaultFolder()
    }
}

extension AssetCacheSettings {
    public init(store: PlayerSettingsStore) {
        let quality = TextureQuality(rawValue: UInt8(clamping: Int(store.value(.textureQuality))))
        var formats: [AssetTextureClass: TextureFormatChoice] = [:]
        for group in AssetTextureClass.allCases {
            let raw = Int(store.value(.textureFormat(group: group.settingName)))
            if
                let choice = TextureFormatChoice(rawValue: UInt8(clamping: raw)),
                choice != .automatic
            {
                formats[group] = choice
            }
        }
        let folder = store.text(.assetOptimisationFolder)
        self.init(
            isEnabled: store.bool(.assetOptimisationEnabled),
            textureOutput: AssetTextureOutput(quality: quality ?? .default, formats: formats),
            folder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) },
            directLoad: DirectGPULoading(
                isEnabled: store.bool(.directGPULoading),
                textures: store.bool(.directGPULoadingTextures),
                meshes: store.bool(.directGPULoadingMeshes),
                allDisks: store.bool(.directGPULoadingAllDisks)
            ),
            kinds: Set(AssetCacheKind.built.filter {
                store.bool(.assetKind(folder: $0.folderName))
            })
        )
    }

    /// Writes every value back, so a change made in one place reaches the others.
    public func save(to store: PlayerSettingsStore) {
        store.set(.assetOptimisationEnabled, to: isEnabled ? 1 : 0)
        store.set(.textureQuality, to: Double(textureOutput.quality.rawValue))
        for group in AssetTextureClass.allCases {
            let choice = textureOutput.formats[group] ?? .automatic
            store.set(.textureFormat(group: group.settingName), to: Double(choice.rawValue))
        }
        store.setText(.assetOptimisationFolder, to: folder?.path(percentEncoded: false))
        store.set(.directGPULoading, to: directLoad.isEnabled ? 1 : 0)
        store.set(.directGPULoadingTextures, to: directLoad.textures ? 1 : 0)
        store.set(.directGPULoadingMeshes, to: directLoad.meshes ? 1 : 0)
        store.set(.directGPULoadingAllDisks, to: directLoad.allDisks ? 1 : 0)
        for kind in AssetCacheKind.built {
            store.set(.assetKind(folder: kind.folderName), to: kinds.contains(kind) ? 1 : 0)
        }
    }
}

nonisolated extension AssetTextureClass {
    /// The suffix of its forced-format setting id.
    public var settingName: String {
        switch self {
        case .color: "color"
        case .normal: "normal"
        case .data: "data"
        }
    }
}

nonisolated extension AssetCacheReader {
    /// Opens the chosen folder after the location check. The reader exists even
    /// with the cache off, so a toggle can turn it on without a reload.
    public static func open(
        settings: AssetCacheSettings, files: any GameFileSource, gameInstall: URL?
    ) throws -> AssetCacheReader {
        let folder = try settings.effectiveFolder()
        try AssetCacheLocation.validate(folder, gameInstall: gameInstall)
        let store = try AssetCacheStore(root: folder, limitBytes: AssetCacheStore.noLimit)
        return AssetCacheReader(
            store: store,
            files: files,
            textureOutput: settings.textureOutput,
            isEnabled: settings.isEnabled,
            kinds: settings.kinds
        )
    }
}
