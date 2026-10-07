// The Asset Cache page's logic: the settings, a build with cancel, a check of
// what the cache holds, and clear. File work runs off the main actor; results
// come back here, and `onChange` tells the page to redraw.

import Foundation
import OpenSkyAssetCache
import OpenSkyGameData

public final class AssetCacheCoordinator {
    public enum Activity: Equatable, Sendable {
        case idle
        case checking
        case building
        case clearing
    }

    /// What one build or check needs from outside, so a test can pass fakes.
    public struct Environment: Sendable {
        public let locate: @Sendable () throws -> (files: any GameFileSource, install: URL)
        public let makeConverters: @Sendable (AssetQualityPreset) throws -> [any AssetConverting]

        public init(
            locate: @escaping @Sendable () throws -> (files: any GameFileSource, install: URL),
            makeConverters: @escaping @Sendable (AssetQualityPreset) throws -> [any AssetConverting]
        ) {
            self.locate = locate
            self.makeConverters = makeConverters
        }

        /// The located install and the converters on the system GPU.
        public static let live = Self(
            locate: {
                let root = try GameDataLocator.locate()
                return (VirtualFileSystem(root: root), root.installURL)
            },
            makeConverters: { try AssetCacheConverters.make(preset: $0) }
        )
    }

    public private(set) var settings: AssetCacheSettings
    public private(set) var activity = Activity.idle
    public private(set) var progress: AssetCacheBuildProgress?
    public private(set) var check: AssetCacheCheck?
    public private(set) var usage: AssetCacheUsage?
    public private(set) var problem: String?
    public var onChange: (() -> Void)?

    private var store: PlayerSettingsStore
    private let environment: Environment
    private var control: AssetCacheBuildControl?

    public init(store: PlayerSettingsStore, environment: Environment = .live) {
        self.store = store
        self.environment = environment
        settings = AssetCacheSettings(store: store)
    }

    /// Reads the settings again from `store`, after another window saved them.
    public func reloadSettings(from store: PlayerSettingsStore) {
        self.store = store
        settings = AssetCacheSettings(store: store)
        onChange?()
    }

    public func setEnabled(_ enabled: Bool) {
        update { $0.isEnabled = enabled }
    }

    /// A new preset makes every entry stale, so the check runs again.
    public func setPreset(_ preset: AssetQualityPreset) {
        guard preset != settings.preset else { return }
        update { $0.preset = preset }
        startCheck()
    }

    /// The check runs again, because it counts only the kinds that are on.
    public func setKind(_ kind: AssetCacheKind, stored: Bool) {
        guard settings.kinds.contains(kind) != stored else { return }
        update { settings in
            if stored {
                settings.kinds.insert(kind)
            } else {
                settings.kinds.remove(kind)
            }
        }
        startCheck()
    }

    /// Nil goes back to the default folder.
    public func setFolder(_ folder: URL?) {
        update { $0.folder = folder }
        startCheck()
    }

    /// Zero uses the preset's default limit.
    public func setLimitGiB(_ gib: Int) {
        update { $0.limitBytes = gib > 0 ? UInt64(gib) << 30 : nil }
    }

    public func startCheck() {
        run(.checking) { builder in
            let check = await builder.check(builder.planInstall())
            return { coordinator in coordinator.check = check }
        }
    }

    public func startBuild() {
        let control = AssetCacheBuildControl()
        self.control = control
        progress = AssetCacheBuildProgress()
        let throttle = AssetCacheProgressThrottle(interval: .milliseconds(250))
        run(.building) { [weak self] builder in
            let width = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
            let items = builder.planInstall()
            let result = await builder.build(items, width: width, control: control) { progress in
                guard throttle.shouldReport(progress) else { return }
                Task { @MainActor in self?.receive(progress) }
            }
            let check = await builder.check(items)
            return { coordinator in
                coordinator.progress = result
                coordinator.check = check
            }
        }
    }

    public func cancelBuild() {
        control?.cancel()
    }

    public func clear() {
        run(.clearing) { builder in
            try builder.store.clear()
            return { coordinator in
                coordinator.progress = nil
                coordinator.check = nil
            }
        }
    }

    private func update(_ change: (inout AssetCacheSettings) -> Void) {
        change(&settings)
        settings.save(to: store)
        problem = nil
        onChange?()
    }

    private func receive(_ progress: AssetCacheBuildProgress) {
        guard
            activity == .building,
            progress.doneFiles >= (self.progress?.doneFiles ?? 0) else { return }
        self.progress = progress
        onChange?()
    }

    /// Runs `work` off the main actor with a builder for the current settings,
    /// then applies its result here. One job runs at a time.
    private func run(
        _ activity: Activity,
        work: @escaping @Sendable (AssetCacheBuilder) async throws
            -> @Sendable @MainActor (AssetCacheCoordinator) -> Void
    ) {
        guard self.activity == .idle else { return }
        self.activity = activity
        problem = nil
        onChange?()
        let settings = settings
        let environment = environment
        Task(priority: .utility) { [weak self] in
            let outcome: Result<@Sendable @MainActor (AssetCacheCoordinator) -> Void, any Error>
            do {
                let builder = try await Self.builder(settings: settings, environment: environment)
                outcome = try await .success(work(builder))
            } catch {
                outcome = .failure(error)
            }
            let usage = await Self.usage(settings: settings)
            self?.finish(outcome, usage: usage)
        }
    }

    private func finish(
        _ outcome: Result<@Sendable @MainActor (AssetCacheCoordinator) -> Void, any Error>,
        usage: AssetCacheUsage?
    ) {
        switch outcome {
        case let .success(apply): apply(self)
        case let .failure(error): problem = AssetCacheCoordinator.message(for: error)
        }
        self.usage = usage
        activity = .idle
        control = nil
        onChange?()
    }

    @concurrent
    nonisolated private static func builder(
        settings: AssetCacheSettings, environment: Environment
    ) async throws -> AssetCacheBuilder {
        let (files, install) = try environment.locate()
        let folder = try settings.effectiveFolder()
        try AssetCacheLocation.validate(folder, gameInstall: install)
        let store = try AssetCacheStore(root: folder, limitBytes: settings.effectiveLimitBytes)
        let converters = try environment.makeConverters(settings.preset)
            .filter { settings.kinds.contains($0.kind) }
        return AssetCacheBuilder(
            store: store,
            files: files,
            converters: converters,
            preset: settings.preset
        )
    }

    @concurrent
    nonisolated private static func usage(settings: AssetCacheSettings) async -> AssetCacheUsage? {
        guard
            let folder = try? settings.effectiveFolder(),
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        else { return nil }
        return try? AssetCacheStore(root: folder, limitBytes: settings.effectiveLimitBytes).usage()
    }

    nonisolated static func message(for error: any Error) -> String {
        switch error {
        case AssetCacheLocationError.insideGameInstall:
            "The folder is inside the game folder. Choose another folder."
        case AssetCacheLocationError.containsGameInstall:
            "The folder holds the game folder. Choose another folder."
        case AssetCacheLocationError.insideRepository:
            "The folder is inside a git checkout. Choose another folder."
        case AssetCacheConvertersError.metalUnavailable:
            "This preset needs a Metal GPU to convert textures."
        default:
            error.localizedDescription
        }
    }
}
