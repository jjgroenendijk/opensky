// Shows a loading screen over a transition: covers the view at once, picks
// the screen when the destination is known, holds it for the minimum time,
// then fades back. Doors call it now; fast travel and save loading can call
// the same entry points. See docs/engine/loading-screens.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One frame of the cover, as the app draws it.
nonisolated public struct LoadingCoverFrame: Equatable, Sendable {
    /// The STAT model the screen turns, or nil for a dark screen.
    public let model: String?
    public let scale: Float
    public let rotationDegrees: SIMD3<Float>
    public let translation: SIMD3<Float>
    public let text: String?
    /// 1 hides the world; below 1 the world shows through during the fade.
    public let opacity: Float
    /// False during the fade, when the world draws again under a dimming panel.
    public let drawsObject: Bool
}

/// What the loading screen needs from the app.
public protocol LoadingScreenWorld: AnyObject {
    var presentationRecords: PresentationRecordStore? { get }
    func loadingConditionContext() -> ConditionContext
    /// The screen's DESC text, from the localized strings.
    func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String?
    /// Draws one frame of the cover, or removes it for nil.
    func presentLoadingCover(_ frame: LoadingCoverFrame?)
    func setLoadingPaused(_ paused: Bool)
    /// The `XLCN` of the cell the player stands in, for the panel's passing list.
    var currentLocation: ResolvedFormID? { get }
}

public final class LoadingScreenCoordinator {
    public var isEnabled = true
    public private(set) var session: LoadingScreenSession?
    /// When the cover went up and no screen was picked yet.
    public private(set) var waitingSince: Double?
    public private(set) var forced: ResolvedRecord<LoadScreen>?
    public private(set) var lastPassingCount = 0
    public private(set) var shownCount = 0
    private var text: String?
    private var loadInFlight = false
    private var random = ConditionRandom()
    private(set) weak var world: (any LoadingScreenWorld)?

    public init() {}

    public func attach(world: any LoadingScreenWorld) {
        self.world = world
    }

    public var isCovering: Bool {
        waitingSince != nil || session != nil || forced != nil
    }

    /// A transition started. The view goes dark until `destinationReady`.
    public func begin(at time: Double) {
        guard isEnabled, forced == nil, session == nil, waitingSince == nil else { return }
        waitingSince = time
        world?.setLoadingPaused(true)
        world?.presentLoadingCover(Self.darkFrame)
    }

    /// The destination is built. Picks a screen for `location` and starts the
    /// minimum display time from now.
    public func destinationReady(location: ResolvedFormID?, at time: Double) {
        guard waitingSince != nil else { return }
        waitingSince = nil
        let screen = pick(location: location)
        var next = LoadingScreenSession(screen: screen, startedAt: time)
        next.markReady(at: time)
        start(next)
    }

    /// A load that can show its screen at once, such as the session start. The
    /// screen stays until `loadFinished(at:)`.
    public func beginLoad(at time: Double) {
        guard isEnabled, forced == nil, session == nil, waitingSince == nil else { return }
        loadInFlight = true
        start(LoadingScreenSession(screen: pick(location: nil), startedAt: time))
    }

    public func loadFinished(at time: Double) {
        guard loadInFlight else { return }
        loadInFlight = false
        session?.markReady(at: time)
    }

    /// The transition failed: the old scene stays, so the cover lifts now.
    public func cancel() {
        guard waitingSince != nil else { return }
        waitingSince = nil
        finish()
    }

    /// Passing screens for `location`, in load order.
    public func passingScreens(location: ResolvedFormID?) -> [ResolvedRecord<LoadScreen>] {
        selector(location: location)?.passing() ?? []
    }

    // MARK: - Debug

    /// Holds `editorID` on screen until `releaseForced`. False when no LSCR matches.
    @discardableResult
    public func force(editorID: String, at time: Double) -> Bool {
        guard let screen = world?.presentationRecords?.loadScreens.record(editorID: editorID)
        else { return false }
        forced = screen
        waitingSince = nil
        start(LoadingScreenSession(screen: screen, startedAt: time))
        return true
    }

    public func releaseForced(at time: Double) {
        guard forced != nil else { return }
        forced = nil
        session?.markReady(at: time)
    }

    // MARK: - Frames

    public func tick(time: Double) {
        guard let session else { return }
        let phase = session.phase(at: time)
        guard phase != .finished else {
            finish()
            return
        }
        world?.presentLoadingCover(frame(session, at: time, phase: phase))
    }

    private func frame(
        _ session: LoadingScreenSession,
        at time: Double,
        phase: LoadingScreenSession.Phase
    ) -> LoadingCoverFrame {
        let record = session.screen?.record
        return LoadingCoverFrame(
            model: session.screen.flatMap { world?.presentationRecords?.model(of: $0) },
            scale: record?.initialScale ?? 1,
            rotationDegrees: session.objectRotationDegrees(at: time),
            translation: record?.initialTranslation ?? .zero,
            text: text,
            opacity: session.opacity(at: time),
            drawsObject: phase == .showing
        )
    }

    private func start(_ next: LoadingScreenSession) {
        session = next
        shownCount += 1
        text = next.screen.flatMap { world?.loadingText(of: $0) }
        world?.setLoadingPaused(true)
        tick(time: next.startedAt)
    }

    private func finish() {
        session = nil
        text = nil
        world?.presentLoadingCover(nil)
        world?.setLoadingPaused(false)
    }

    private func pick(location: ResolvedFormID?) -> ResolvedRecord<LoadScreen>? {
        guard let selector = selector(location: location) else { return nil }
        lastPassingCount = selector.passing().count
        return selector.pick(random: &random)
    }

    private func selector(location: ResolvedFormID?) -> LoadScreenSelector? {
        guard let world, let store = world.presentationRecords else { return nil }
        let check = LoadScreenSelector.conditionCheck(
            context: world.loadingConditionContext(), destination: location
        )
        return LoadScreenSelector(store: store, check: check)
    }

    static let darkFrame = LoadingCoverFrame(
        model: nil, scale: 1, rotationDegrees: .zero, translation: .zero,
        text: nil, opacity: 1, drawsObject: true
    )
}
