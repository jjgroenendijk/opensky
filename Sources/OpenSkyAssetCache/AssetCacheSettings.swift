// The asset cache settings, read from the one player settings store, so the app
// and openskycli build and read with the same preset and folder.

import Foundation
import OpenSkyGameData

nonisolated public struct AssetCacheSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var preset: AssetQualityPreset
    /// Nil uses the default folder.
    public var folder: URL?
    /// Nil uses the preset's default limit.
    public var limitBytes: UInt64?

    public init(
        isEnabled: Bool = true,
        preset: AssetQualityPreset = .default,
        folder: URL? = nil,
        limitBytes: UInt64? = nil
    ) {
        self.isEnabled = isEnabled
        self.preset = preset
        self.folder = folder
        self.limitBytes = limitBytes
    }

    public var effectiveLimitBytes: UInt64 {
        limitBytes ?? preset.defaultLimitBytes
    }

    public func effectiveFolder() throws -> URL {
        try folder ?? AssetCacheLocation.defaultFolder()
    }
}

extension AssetCacheSettings {
    public init(store: PlayerSettingsStore) {
        let presetIndex = Int(store.value(.assetCachePreset).rounded())
        let limit = UInt64(max(0, store.value(.assetCacheLimitGiB).rounded()))
        let folder = store.text(.assetCacheFolder)
        self.init(
            isEnabled: store.bool(.assetCacheEnabled),
            preset: AssetQualityPreset(rawValue: UInt8(clamping: presetIndex)) ?? .default,
            folder: folder.map { URL(filePath: $0, directoryHint: .isDirectory) },
            limitBytes: limit > 0 ? limit << 30 : nil
        )
    }

    /// Writes every value back, so a change made in one place reaches the others.
    public func save(to store: PlayerSettingsStore) {
        store.set(.assetCacheEnabled, to: isEnabled ? 1 : 0)
        store.set(.assetCachePreset, to: Double(preset.rawValue))
        store.setText(.assetCacheFolder, to: folder?.path(percentEncoded: false))
        store.set(.assetCacheLimitGiB, to: Double((limitBytes ?? 0) >> 30))
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
        let store = try AssetCacheStore(root: folder, limitBytes: settings.effectiveLimitBytes)
        return AssetCacheReader(
            store: store,
            files: files,
            preset: settings.preset,
            isEnabled: settings.isEnabled
        )
    }
}
