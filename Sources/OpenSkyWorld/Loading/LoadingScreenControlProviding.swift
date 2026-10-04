// World > Loading Screens: the seam the sidebar reads and the readout lines.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct LoadingScreenSnapshot: Equatable, Sendable {
    public var isAvailable = false
    public var isEnabled = true
    public var screenNames: [String] = []
    public var showing: String?
    public var isForced = false
    public var shownCount = 0
    /// Screens whose conditions pass where the player stands now.
    public var passing: [String] = []

    public init() {}
}

public protocol LoadingScreenControlProviding: AnyObject {
    var loadingScreenSnapshot: LoadingScreenSnapshot { get }
    var loadingScreensEnabled: Bool { get set }
    /// Holds one LSCR on screen until released.
    func forceLoadingScreen(editorID: String)
    func releaseLoadingScreen()
}

extension LoadingScreenCoordinator {
    public var snapshot: LoadingScreenSnapshot {
        var snapshot = LoadingScreenSnapshot()
        guard let world, let store = world.presentationRecords else { return snapshot }
        snapshot.isAvailable = true
        snapshot.isEnabled = isEnabled
        snapshot.screenNames = store.loadScreens.records.compactMap(\.record.editorID).sorted()
        snapshot.showing = session.map { $0.screen?.record.editorID ?? "dark screen" }
            ?? (waitingSince == nil ? nil : "dark screen")
        snapshot.isForced = forced != nil
        snapshot.shownCount = shownCount
        snapshot.passing = passingScreens(location: world.currentLocation).map {
            $0.record.editorID ?? $0.id.description
        }
        return snapshot
    }
}

nonisolated public enum LoadingScreenReadout {
    public static let passingCap = 12

    public static func text(for snapshot: LoadingScreenSnapshot) -> String {
        guard snapshot.isAvailable else { return "Loading screens: no game data" }
        var lines = [
            "Showing: \(snapshot.showing ?? "none")" + (snapshot.isForced ? " (forced)" : ""),
            "Shown this session: \(snapshot.shownCount)",
            "Pass here: \(snapshot.passing.count) of \(snapshot.screenNames.count)"
        ]
        lines += snapshot.passing.prefix(passingCap).map { "  \($0)" }
        if snapshot.passing.count > passingCap {
            lines.append("  and \(snapshot.passing.count - passingCap) more")
        }
        return lines.joined(separator: "\n")
    }
}

/// Lets the app's provider stand in for its coordinator, one line to conform.
public protocol LoadingScreenControlForwarding: LoadingScreenControlProviding {
    var loadingScreens: LoadingScreenCoordinator { get }
}

extension LoadingScreenControlForwarding {
    private var now: Double {
        Date().timeIntervalSinceReferenceDate
    }

    public var loadingScreenSnapshot: LoadingScreenSnapshot {
        loadingScreens.snapshot
    }

    public var loadingScreensEnabled: Bool {
        get { loadingScreens.isEnabled }
        set { loadingScreens.isEnabled = newValue }
    }

    public func forceLoadingScreen(editorID: String) {
        loadingScreens.force(editorID: editorID, at: now)
    }

    public func releaseLoadingScreen() {
        loadingScreens.releaseForced(at: now)
    }
}
