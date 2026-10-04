// Developer > UI Lab: the screen-space overlay samples, the menu-mode preview,
// and the localized-strings counts. Without a renderer the overlay is inert.

import OpenSkyGameData
import OpenSkyRendering

public final class UILabCoordinator {
    /// The two samples share the one `Renderer.uiScene` slot.
    public enum Sample: Equatable, Sendable {
        case none, lab, localized
    }

    public private(set) var sample = Sample.none
    /// Set by the app; nil without game data.
    public var localizedLabelsLoader: (() -> LocalizedLabels)?
    private var installLabels: LocalizedLabels?
    private var installLabelsResolved = false

    private let menuMode: MenuModeController
    private weak var world: SWFLayerWorld?

    public init(menuMode: MenuModeController) {
        self.menuMode = menuMode
    }

    public func attach(world: SWFLayerWorld) {
        self.world = world
    }

    private var renderer: Renderer? {
        world?.renderer
    }

    public var overlayEnabled: Bool {
        get { renderer?.uiEnabled ?? true }
        set { renderer?.uiEnabled = newValue }
    }

    public var scale: Float {
        get { renderer?.uiScale ?? 1 }
        set {
            renderer?.uiScale = min(
                max(newValue, UIScale.range.lowerBound), UIScale.range.upperBound
            )
        }
    }

    public func isShown(_ candidate: Sample) -> Bool {
        renderer != nil && sample == candidate
    }

    /// Hiding a sample that is not shown leaves the other one in place.
    public func setShown(_ shown: Bool, _ candidate: Sample) {
        if shown {
            apply(candidate)
        } else if sample == candidate {
            apply(.none)
        }
    }

    private func apply(_ selection: Sample) {
        sample = selection
        switch selection {
        case .none: renderer?.uiScene = .empty
        case .lab: renderer?.uiScene = .labSample
        case .localized: renderer?.uiScene = .localizedSample
        }
    }

    public var snapshot: UILabControlSnapshot {
        UILabControlSnapshot(
            overlayEnabled: overlayEnabled,
            scale: scale,
            stats: renderer?.lastUIDrawStats ?? UIDrawStats()
        )
    }

    // MARK: - Menu-mode preview

    /// Names come from the depth (`UILabMenu1`, `UILabMenu2`), so push and pop
    /// never hit the duplicate-name rejection.
    public func pushPreviewMenu() {
        menuMode.present(MenuIdentifier("UILabMenu\(menuMode.stack.count + 1)"))
    }

    public func popPreviewMenu() {
        menuMode.dismissTop()
    }

    public func clearPreviewMenus() {
        menuMode.dismissAll()
    }

    public var menuModeSnapshot: MenuModeControlSnapshot {
        MenuModeControlSnapshot(
            isMenuMode: menuMode.isMenuMode,
            topMenuName: menuMode.topMenu?.name,
            stackDepth: menuMode.stack.count,
            isWorldSimPaused: menuMode.isWorldSimPaused
        )
    }

    // MARK: - Localized strings

    public var localizedLabelsSnapshot: LocalizedLabelsControlSnapshot {
        let install = resolveInstallLabels()
        return LocalizedLabelsControlSnapshot(
            sampleShown: isShown(.localized),
            sampleKeyCount: LocalizedLabels.uiLabSample.keyCount,
            language: install?.language ?? LocalizedLabels.uiLabSample.language,
            installLoaded: install != nil,
            installFileCount: install?.fileCount ?? 0,
            installKeyCount: install?.keyCount ?? 0,
            installVanillaPath: install?.vanillaPath
        )
    }

    /// Loads once, so the 2 Hz readout never walks the file system again.
    private func resolveInstallLabels() -> LocalizedLabels? {
        if !installLabelsResolved {
            installLabels = localizedLabelsLoader?()
            installLabelsResolved = true
        }
        return installLabels
    }
}

/// Lets the app's provider object stand in for its `UILabCoordinator`.
public protocol UILabControlForwarding: UILabControlProviding {
    var uiLab: UILabCoordinator { get }
}

extension UILabControlForwarding {
    public var uiOverlayEnabled: Bool {
        get { uiLab.overlayEnabled }
        set { uiLab.overlayEnabled = newValue }
    }

    public var uiSampleShown: Bool {
        get { uiLab.isShown(.lab) }
        set { uiLab.setShown(newValue, .lab) }
    }

    public var uiScale: Float {
        get { uiLab.scale }
        set { uiLab.scale = newValue }
    }

    public var uiSnapshot: UILabControlSnapshot {
        uiLab.snapshot
    }

    public func pushPreviewMenu() {
        uiLab.pushPreviewMenu()
    }

    public func popPreviewMenu() {
        uiLab.popPreviewMenu()
    }

    public func clearPreviewMenus() {
        uiLab.clearPreviewMenus()
    }

    public var menuModeSnapshot: MenuModeControlSnapshot {
        uiLab.menuModeSnapshot
    }

    public var uiLocalizedSampleShown: Bool {
        get { uiLab.isShown(.localized) }
        set { uiLab.setShown(newValue, .localized) }
    }

    public var localizedLabelsSnapshot: LocalizedLabelsControlSnapshot {
        uiLab.localizedLabelsSnapshot
    }
}
