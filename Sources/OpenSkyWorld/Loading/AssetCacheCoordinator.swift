// The Asset Optimisation logic: the settings, a conversion with cancel, a check
// of what the folder holds, and clear. File work runs off the main actor; results
// come back here, and each observer redraws its page.

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
        public let makeConverters: @Sendable (AssetTextureOutput) throws -> [any AssetConverting]

        public init(
            locate: @escaping @Sendable () throws -> (files: any GameFileSource, install: URL),
            makeConverters: @escaping @Sendable (AssetTextureOutput) throws -> [any AssetConverting]
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
            makeConverters: { try AssetCacheConverters.make(textureOutput: $0) }
        )
    }

    public private(set) var settings: AssetCacheSettings
    public private(set) var activity = Activity.idle
    public private(set) var progress: AssetCacheBuildProgress?
    public private(set) var check: AssetCacheCheck?
    public private(set) var usage: AssetCacheUsage?
    public private(set) var problem: String?
    /// The disk of the folder, read with each check.
    public private(set) var volume: AssetCacheVolume?
    /// The page that owns the coordinator. Other pages use `observe`.
    public var onChange: (() -> Void)? {
        didSet { notify() }
    }

    private var observers: [() -> Void] = []

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
        notify()
    }

    public func setEnabled(_ enabled: Bool) {
        update { $0.isEnabled = enabled }
    }

    /// Adds a redraw handler, such as the Launch page's status line.
    public func observe(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    /// Takes effect at the next game launch, like the in-game switch's start value.
    public func setDirectLoad(_ directLoad: DirectGPULoading) {
        guard directLoad != settings.directLoad else { return }
        update { $0.directLoad = directLoad }
    }

    /// A new quality marks only the textures stale, so the check runs again.
    public func setTextureQuality(_ quality: TextureQuality) {
        guard quality != settings.textureOutput.quality else { return }
        update { $0.textureOutput.quality = quality }
        startCheck()
    }

    public func setTextureFormat(_ choice: TextureFormatChoice, for group: AssetTextureClass) {
        guard (settings.textureOutput.formats[group] ?? .automatic) != choice else { return }
        update { $0.textureOutput.formats[group] = choice == .automatic ? nil : choice }
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

    public func startCheck() {
        run(.checking) { builder in
            let check = await builder.check(builder.planInstall())
            let volume = AssetCacheVolume.of(builder.store.root)
            return { coordinator in
                coordinator.check = check
                coordinator.volume = volume
            }
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
            let volume = AssetCacheVolume.of(builder.store.root)
            return { coordinator in
                coordinator.progress = result
                coordinator.check = check
                coordinator.volume = volume
            }
        }
    }

    public func cancelBuild() {
        control?.cancel()
    }

    public func clear() {
        run(.clearing) { builder in
            try builder.store.clear()
            let check = await builder.check(builder.planInstall())
            return { coordinator in
                coordinator.progress = nil
                coordinator.check = check
            }
        }
    }

    private func update(_ change: (inout AssetCacheSettings) -> Void) {
        change(&settings)
        settings.save(to: store)
        problem = nil
        notify()
    }

    private func notify() {
        onChange?()
        for observer in observers {
            observer()
        }
    }

    private func receive(_ progress: AssetCacheBuildProgress) {
        guard
            activity == .building,
            progress.doneFiles >= (self.progress?.doneFiles ?? 0) else { return }
        self.progress = progress
        notify()
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
        notify()
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
        notify()
    }

    @concurrent
    nonisolated private static func builder(
        settings: AssetCacheSettings, environment: Environment
    ) async throws -> AssetCacheBuilder {
        let (files, install) = try environment.locate()
        let folder = try settings.effectiveFolder()
        try AssetCacheLocation.validate(folder, gameInstall: install)
        let store = try AssetCacheStore(root: folder, limitBytes: AssetCacheStore.noLimit)
        let converters = try environment.makeConverters(settings.textureOutput)
            .filter { settings.kinds.contains($0.kind) }
        return AssetCacheBuilder(
            store: store,
            files: files,
            converters: converters,
            textureOutput: settings.textureOutput
        )
    }

    @concurrent
    nonisolated private static func usage(settings: AssetCacheSettings) async -> AssetCacheUsage? {
        guard
            let folder = try? settings.effectiveFolder(),
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        else { return nil }
        return try? AssetCacheStore(root: folder, limitBytes: AssetCacheStore.noLimit).usage()
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
            "This texture quality needs a Metal GPU to convert textures."
        default:
            error.localizedDescription
        }
    }
}
