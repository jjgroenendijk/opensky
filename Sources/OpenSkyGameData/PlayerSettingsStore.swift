// The one owner of the player's settings at runtime. A write is clamped, saved,
// and announced to every observer, so a subsystem applies the new value at once
// and the sidebar and the menu read the same value.

import Foundation
import OpenSkyFormatsCore

/// Where the settings file lives. A test passes an in-memory fake.
public protocol PlayerSettingsPersistence: AnyObject {
    func loadSettings() throws -> Data?
    func saveSettings(_ data: Data) throws
}

/// `~/Library/Application Support/OpenSky/Settings.json`, OpenSky's own storage.
/// Skyrim's INI files are never written.
public final class PlayerSettingsFile: PlayerSettingsPersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultFile(fileManager: FileManager = .default) throws
        -> PlayerSettingsFile
    {
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "OpenSky", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return PlayerSettingsFile(url: directory.appending(path: "Settings.json"))
    }

    public func loadSettings() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func saveSettings(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
    }
}

public final class PlayerSettingsStore {
    public typealias Observer = (PlayerSettingID) -> Void

    public let catalog: PlayerSettingsCatalog
    public private(set) var model = PlayerSettingsModel()
    private let persistence: (any PlayerSettingsPersistence)?
    private var observers: [(token: UUID, observer: Observer)] = []

    /// A file that cannot be read or decoded starts from defaults and is reported.
    public init(
        catalog: PlayerSettingsCatalog = .vanilla,
        persistence: (any PlayerSettingsPersistence)?
    ) {
        self.catalog = catalog
        self.persistence = persistence
        do {
            if let data = try persistence?.loadSettings() {
                model = try PlayerSettingsModel(decoding: data, catalog: catalog)
            }
        } catch {
            Self.logger
                .error("[ERROR] settings load: \(String(describing: error), privacy: .public)")
        }
    }

    public func value(_ id: PlayerSettingID) -> Double {
        model.value(id, in: catalog)
    }

    public func bool(_ id: PlayerSettingID) -> Bool {
        value(id) >= 0.5
    }

    public func set(_ id: PlayerSettingID, to value: Double) {
        guard model.set(id, to: value, in: catalog) else { return }
        commit([id])
    }

    public func step(_ id: PlayerSettingID, by direction: Int) {
        guard let definition = catalog.definition(id) else { return }
        set(id, to: definition.stepped(value(id), by: direction))
    }

    /// Replaces every binding at once, so a swap of two keys is one change.
    public func replaceKeyBindings(_ bindings: [String: Int]) {
        guard model.keyBindings != bindings else { return }
        model.replaceKeyBindings(bindings)
        commit([], bindingsChanged: true)
    }

    /// Called with each changed id, and with `keyBindingsChanged` for a binding.
    @discardableResult
    public func observe(_ observer: @escaping Observer) -> UUID {
        let token = UUID()
        observers.append((token, observer))
        return token
    }

    private func commit(_ changed: [PlayerSettingID], bindingsChanged: Bool = false) {
        guard !changed.isEmpty || bindingsChanged else { return }
        do {
            try persistence?.saveSettings(model.encoded())
        } catch {
            Self.logger
                .error("[ERROR] settings save: \(String(describing: error), privacy: .public)")
        }
        let notify = changed + (bindingsChanged ? [.keyBindingsChanged] : [])
        for id in notify {
            for entry in observers {
                entry.observer(id)
            }
        }
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Settings"
    )
}

nonisolated extension PlayerSettingID {
    /// Not a stored setting: the notification sent when a key binding changes.
    public static let keyBindingsChanged = Self("controls.keyBindings")
}
