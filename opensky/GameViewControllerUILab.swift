// Developer > UI Lab renderer bridge: UILabControlProviding over the live renderer
// (M8.1.1 overlay controls) plus the M8.1.4 menu-mode and localized-strings
// previews. Satellite of GameViewController.swift (500-line file limit); the
// stored state it maps (uiLabSampleSelection, localizedLabelsLoader and its
// cache) lives on the class. A nil renderer (Metal 4 unavailable) degrades to
// inert controls, matching the other `*ControlProviding` bridges.

import AppKit

extension GameViewController: UILabControlProviding {
    var uiOverlayEnabled: Bool {
        get { renderer?.uiEnabled ?? true }
        set { renderer?.uiEnabled = newValue }
    }

    var uiSampleShown: Bool {
        get { renderer != nil && uiLabSampleSelection == .lab }
        set {
            if newValue {
                applyUILabSample(.lab)
            } else if uiLabSampleSelection == .lab {
                applyUILabSample(.none)
            }
        }
    }

    var uiScale: Float {
        get { renderer?.uiScale ?? 1 }
        set {
            renderer?.uiScale = min(
                max(newValue, UIScale.range.lowerBound), UIScale.range.upperBound
            )
        }
    }

    var uiSnapshot: UILabControlSnapshot {
        UILabControlSnapshot(
            overlayEnabled: uiOverlayEnabled,
            sampleShown: uiSampleShown,
            scale: uiScale,
            stats: renderer?.lastUIDrawStats ?? UIDrawStats()
        )
    }

    /// The two samples are mutually exclusive because they share the one
    /// `Renderer.uiScene` slot; selecting one replaces the other.
    private func applyUILabSample(_ selection: UILabSampleSelection) {
        uiLabSampleSelection = selection
        switch selection {
        case .none:
            renderer?.uiScene = .empty
        case .lab:
            renderer?.uiScene = .labSample
        case .localized:
            renderer?.uiScene = .localizedSample
        }
    }

    // MARK: - Menu-mode preview (M8.1.4)

    /// Opens one more preview menu on the real MenuModeController. Names are
    /// depth-derived (`UILabMenu1`, `UILabMenu2`, ...) so pure push/pop use can
    /// never hit the duplicate-name rejection and the readout stays
    /// deterministic.
    func pushPreviewMenu() {
        menuMode.present(MenuIdentifier("UILabMenu\(menuMode.stack.count + 1)"))
    }

    func popPreviewMenu() {
        menuMode.dismissTop()
    }

    func clearPreviewMenus() {
        menuMode.dismissAll()
    }

    var menuModeSnapshot: MenuModeControlSnapshot {
        MenuModeControlSnapshot(
            isMenuMode: menuMode.isMenuMode,
            topMenuName: menuMode.topMenu?.name,
            stackDepth: menuMode.stack.count,
            isWorldSimPaused: menuMode.isWorldSimPaused
        )
    }

    // MARK: - Localized-strings preview (M8.1.4)

    var uiLocalizedSampleShown: Bool {
        get { renderer != nil && uiLabSampleSelection == .localized }
        set {
            if newValue {
                applyUILabSample(.localized)
            } else if uiLabSampleSelection == .localized {
                applyUILabSample(.none)
            }
        }
    }

    var localizedLabelsSnapshot: LocalizedLabelsControlSnapshot {
        let install = resolveInstallLabels()
        return LocalizedLabelsControlSnapshot(
            sampleShown: uiLocalizedSampleShown,
            sampleKeyCount: LocalizedLabels.uiLabSample.keyCount,
            language: install?.language ?? LocalizedLabels.uiLabSample.language,
            installLoaded: install != nil,
            installFileCount: install?.fileCount ?? 0,
            installKeyCount: install?.keyCount ?? 0
        )
    }

    /// Runs the loader once and caches, so the 2 Hz readout ticker never
    /// re-walks the VFS. nil when no game data is located.
    private func resolveInstallLabels() -> LocalizedLabels? {
        if !installLocalizedLabelsResolved {
            installLocalizedLabels = localizedLabelsLoader?()
            installLocalizedLabelsResolved = true
        }
        return installLocalizedLabels
    }
}
