// The base game's graphics presets, read from `Low.ini`, `Medium.ini`, `High.ini`,
// and `Ultra.ini` in the install folder at runtime. A preset sets the store values
// its file has; a store that matches no preset reads as Custom.

import Foundation

nonisolated public enum GraphicsPreset: Int, CaseIterable, Sendable {
    case low, medium, high, ultra

    public var title: String {
        fileName.replacingOccurrences(of: ".ini", with: "")
    }

    public var fileName: String {
        switch self {
        case .low: "Low.ini"
        case .medium: "Medium.ini"
        case .high: "High.ini"
        case .ultra: "Ultra.ini"
        }
    }

    /// The texture quality a preset names on the Asset Optimisation page, as a
    /// `TextureQuality` raw value: Ultra keeps the shipped textures.
    public var textureQualityIndex: Double {
        switch self {
        case .low: 3
        case .medium: 2
        case .high: 1
        case .ultra: 0
        }
    }
}

nonisolated public struct GraphicsPresetFiles: Sendable {
    public let files: [GraphicsPreset: INIFile]

    public init(files: [GraphicsPreset: INIFile]) {
        self.files = files
    }

    /// The preset files found in `installURL`; a missing one is left out.
    public static func load(installURL: URL, fileManager: FileManager = .default) -> Self {
        var files: [GraphicsPreset: INIFile] = [:]
        for preset in GraphicsPreset.allCases {
            let url = installURL.appending(path: preset.fileName)
            guard
                fileManager.fileExists(atPath: url.path),
                let data = try? Data(contentsOf: url)
            else {
                continue
            }
            files[preset] = INIFile(data: data)
        }
        return Self(files: files)
    }

    /// The store values `preset` sets, by option. Empty when its file is missing.
    public func values(_ preset: GraphicsPreset) -> [PlayerSettingID: Double] {
        guard let file = files[preset] else { return [:] }
        var values: [PlayerSettingID: Double] = [.textureQuality: preset.textureQualityIndex]
        for option in GraphicsOptions.all {
            values[option.id] = GraphicsOptions.value(option, in: file)
        }
        return values
    }

    @MainActor
    public func apply(_ preset: GraphicsPreset, to store: PlayerSettingsStore) {
        for (id, value) in values(preset).sorted(by: { $0.key < $1.key }) {
            store.set(id, to: value)
        }
    }

    /// The preset whose every value the store holds, or nil for Custom.
    @MainActor
    public func current(in store: PlayerSettingsStore) -> GraphicsPreset? {
        GraphicsPreset.allCases.first { preset in
            let values = values(preset)
            return !values.isEmpty && values.allSatisfy { id, value in
                abs(store.value(id) - value) < 0.0001
            }
        }
    }
}
