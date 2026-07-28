// System menu (M8.5.1): the first real `MenuInputConsumer`. Opening the menu
// pushes the engine's own menu stack, which pauses world sim and re-routes
// keyboard input here; Resume pops it. AppKit and the renderer stay in this
// controller satellite, the selector is UI/SystemMenuModel.swift, and the
// vanilla presentation layer is UI/SystemMenuMovieBridge.swift — both build
// into the CLI target. See docs/engine/system-menu.md.

import AppKit
import OSLog

struct SystemMenuRuntimeState {
    var model = SystemMenuModel()
    /// Off by default: the engine-side selector is the durable surface, and the
    /// vanilla movie takes over the single SWF layer from the gameplay HUD.
    var movieEnabled = false
    var movieLoaded = false
    var movieError: String?
    var dataRoot: GameDataRoot?
    var dataRootResolved = false
}

extension GameViewController {
    static let systemMenuIdentifier: MenuIdentifier = "SystemMenu"

    /// Resolved once and cached: `GameDataLocator.locate()` walks the
    /// filesystem, and the 2 Hz panel readout must never trigger that walk.
    var systemMenuDataRoot: GameDataRoot? {
        if systemMenu.dataRootResolved {
            return systemMenu.dataRoot
        }
        systemMenu.dataRootResolved = true
        systemMenu.dataRoot = try? GameDataLocator.locate()
        return systemMenu.dataRoot
    }

    static func dataRootSourceLabel(_ source: GameDataRoot.Source) -> String {
        switch source {
        case .environment: "\(GameDataLocator.environmentKey) environment variable"
        case .userDefaults: "Settings"
        case .steamDefault: "Steam default"
        }
    }

    func applySystemMenuOutcome(_ outcome: SystemMenuOutcome) {
        switch outcome {
        case .resume:
            closeSystemMenu()
        case .showSettings:
            // The placeholders live beside the menu for M8.5.1; revealing them
            // is state on the model, not a second menu on the stack.
            break
        case .quit:
            closeSystemMenu()
            NSApplication.shared.terminate(nil)
        }
    }

    /// Brings the vanilla movie up in place of the gameplay HUD. A missing
    /// install, an undecodable movie, or a contract the AS2 subset cannot
    /// satisfy degrades to an explanatory readout — never a thrown error out of
    /// a control action.
    func startSystemMenuMovie() {
        guard let renderer, let loader = resolveSWFLoader() else {
            systemMenu.movieLoaded = false
            systemMenu.movieError = "No game data located."
            return
        }
        do {
            // The renderer owns exactly one SWF layer. Taking it over here is
            // the same handoff Developer > UI Lab performs, so the HUD can
            // never mutate the replacement runtime.
            hud.isLoaded = false
            let scene = try loader.load(path: SystemMenuMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: SystemMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                systemMenu.movieLoaded = false
                systemMenu.movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.closeSystemMenu()
                }
            }
            for _ in 0 ..< Self.systemMenuActivationTicks {
                try renderer.advanceSWFRuntime()
            }
            systemMenu.movieLoaded = true
            systemMenu.movieError = nil
        } catch {
            systemMenu.movieLoaded = false
            systemMenu.movieError = String(describing: error)
            Self.systemMenuLogger.error(
                "[ERROR] system menu movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    func stopSystemMenuMovie() {
        systemMenu.movieLoaded = false
        systemMenu.movieError = nil
        guard let renderer else { return }
        startHUD(renderer: renderer)
    }

    /// Frames the journal's top-level fade needs to settle after `ShowMenu`;
    /// measured against the install, not guessed.
    static let systemMenuActivationTicks = 20

    private static let systemMenuLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "SystemMenu"
    )

    private func routeSystemMenuInput(_ event: MenuInputEvent) {
        guard systemMenu.model.isOpen else { return }
        if
            systemMenu.movieLoaded,
            let runtime = renderer?.swfRuntime,
            SystemMenuMovieBridge.handle(event, runtime: runtime)
        {
            return
        }
        let outcome = systemMenu.model.handle(event)
        if let outcome {
            applySystemMenuOutcome(outcome)
        }
    }
}

extension GameViewController: MenuInputConsumer {
    func handleMenuInput(_ event: MenuInputEvent) {
        routeSystemMenuInput(event)
    }
}

extension GameViewController: SystemMenuControlProviding {
    var systemMenuIsOpen: Bool {
        systemMenu.model.isOpen
    }

    var systemMenuMovieEnabled: Bool {
        get { systemMenu.movieEnabled }
        set {
            guard newValue != systemMenu.movieEnabled else { return }
            systemMenu.movieEnabled = newValue
            guard systemMenu.model.isOpen else { return }
            if newValue {
                startSystemMenuMovie()
            } else {
                stopSystemMenuMovie()
            }
        }
    }

    var systemMenuMasterVolume: Float {
        get { audioMasterVolume }
        set { audioMasterVolume = newValue }
    }

    func openSystemMenu() {
        guard !systemMenu.model.isOpen else { return }
        systemMenu.model.open()
        menuMode.inputConsumer = self
        menuMode.present(Self.systemMenuIdentifier)
        if systemMenu.movieEnabled {
            startSystemMenuMovie()
        }
    }

    func closeSystemMenu() {
        guard systemMenu.model.isOpen else { return }
        systemMenu.model.close()
        menuMode.dismiss(Self.systemMenuIdentifier)
        if systemMenu.movieLoaded {
            stopSystemMenuMovie()
        }
    }

    func sendSystemMenuInput(_ event: MenuInputEvent) {
        routeSystemMenuInput(event)
    }

    var systemMenuSnapshot: SystemMenuControlSnapshot {
        let model = systemMenu.model
        let diagnostics = renderer?.swfRuntime.map(SystemMenuMovieBridge.diagnostics(runtime:))
        return SystemMenuControlSnapshot(
            isOpen: model.isOpen,
            entryTitles: model.entries.map(\.title),
            selectedIndex: model.selectedIndex,
            lastOutcome: model.lastOutcome?.label,
            settingsRevealed: model.settingsRevealed,
            openMenus: menuMode.stack.identifiers.map(\.name),
            worldSimPaused: menuMode.isWorldSimPaused,
            dataRootPath: systemMenuDataRoot?.installURL.path(percentEncoded: false),
            dataRootSource: systemMenuDataRoot.map { Self.dataRootSourceLabel($0.source) },
            masterVolume: audioMasterVolume,
            audioEnabled: audioEnabled,
            movieEnabled: systemMenu.movieEnabled,
            movieLoaded: systemMenu.movieLoaded,
            movieError: systemMenu.movieError,
            movieDrawStats: systemMenu.movieLoaded
                ? (renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieEntryTitles: systemMenu.movieLoaded
                ? (renderer?.swfRuntime.map(SystemMenuMovieBridge.entryLabels(runtime:)) ?? [])
                : [],
            movieState: systemMenu.movieLoaded
                ? renderer?.swfRuntime.flatMap(SystemMenuMovieBridge.currentState(runtime:))
                : nil
        )
    }
}
