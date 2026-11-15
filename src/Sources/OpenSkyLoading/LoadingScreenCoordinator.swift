// Shows a loading screen over a transition: covers the view at once, picks
// the screen when the destination is known, holds it for the minimum time,
// then fades back. Doors, fast travel, and loads call it.
// See docs/engine/loading-screens.md.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldConditions
import simd

/// One frame of the cover, as the app draws it.
nonisolated public struct LoadingCoverFrame: Equatable, Sendable {
    /// The STAT model the screen turns, or nil for a dark screen.
    public let model: String?
    public let scale: Float
    /// RNAM, whole degrees per axis.
    public let rotationDegrees: SIMD3<Float>
    public let translation: SIMD3<Float>
    public let turnRadians: Float
    /// The scene camera's field of view, in the game's own unit.
    public let fieldOfView: Float
    /// The MOD2 camera path mesh, played from `elapsedSeconds`.
    public let cameraPath: String?
    public let elapsedSeconds: Double
    public let text: String?
    /// 1 hides the world; below 1 the world shows through during the fade.
    public let opacity: Float
    /// False during the fade, when the world draws again under a dimming readout.
    public let drawsObject: Bool

    init(
        model: String?, scale: Float, rotationDegrees: SIMD3<Float>, translation: SIMD3<Float>,
        turnRadians: Float = 0, fieldOfView: Float = LoadingScreenScene.defaultFieldOfView,
        cameraPath: String? = nil, elapsedSeconds: Double = 0,
        text: String?, opacity: Float, drawsObject: Bool
    ) {
        self.model = model
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.translation = translation
        self.turnRadians = turnRadians
        self.fieldOfView = fieldOfView
        self.cameraPath = cameraPath
        self.elapsedSeconds = elapsedSeconds
        self.text = text
        self.opacity = opacity
        self.drawsObject = drawsObject
    }
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
}

public final class LoadingScreenCoordinator {
    public var isEnabled = true
    public private(set) var session: LoadingScreenSession?
    /// When the cover went up and no screen was picked yet.
    public private(set) var waitingSince: Double?
    public private(set) var forced: ResolvedRecord<LoadScreen>?
    private(set) var lastPassingCount = 0
    public private(set) var shownCount = 0
    private var text: String?
    /// The screens a later tip is drawn from.
    private var tipScreens: [ResolvedRecord<LoadScreen>] = []
    private var fadeOut: FadeOut?
    private var loadInFlight = false
    /// Pointer motion while the button is held, applied at the next tick.
    private var pendingDrag = SIMD2<Float>.zero
    private var stick = SIMD2<Float>.zero
    private var lastTick: Double?
    private var random = ConditionRandom()
    weak let world: (any LoadingScreenWorld)?

    public init(world: any LoadingScreenWorld) {
        self.world = world
    }

    public var isCovering: Bool {
        waitingSince != nil || session != nil || forced != nil
    }

    /// A transition started. After `fadeWait` seconds the view turns black over
    /// `fadeSeconds`, and stays dark until `destinationReady`.
    public func begin(at time: Double, fadeSeconds: Double = 0, fadeWait: Double = 0) {
        guard isEnabled, forced == nil, session == nil, waitingSince == nil else { return }
        waitingSince = time
        fadeOut = FadeOut(start: time + max(0, fadeWait), seconds: fadeSeconds)
        world?.setLoadingPaused(true)
        presentFadeOut(at: time)
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

    /// The destination's location is known but its area still loads, as in a fast
    /// travel. The screen shows until `loadFinished(at:)`.
    public func destinationKnown(location: ResolvedFormID?, at time: Double) {
        guard waitingSince != nil else { return }
        waitingSince = nil
        loadInFlight = true
        start(LoadingScreenSession(screen: pick(location: location), startedAt: time))
    }

    public var isWaitingForDestination: Bool {
        waitingSince != nil
    }

    /// A load that can show its screen at once, such as a new game's first move. The
    /// screen stays until `loadFinished(at:)`.
    public func beginLoad(at time: Double) {
        beginLoad(at: time, state: .gameLoaded)
    }

    /// A load before any game is loaded, such as the session start. Only screens
    /// marked for the main menu can show.
    public func beginFirstLoad(at time: Double) {
        beginLoad(at: time, state: .noGame)
    }

    private func beginLoad(at time: Double, state: LoadScreenSelector.GameState) {
        guard isEnabled, forced == nil, session == nil, waitingSince == nil else { return }
        loadInFlight = true
        start(LoadingScreenSession(screen: pick(location: nil, state: state), startedAt: time))
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

    /// Pointer motion in pixels while the button is held; X turns the object and Y
    /// changes the field of view at the next frame.
    public func drag(by pixels: SIMD2<Float>) {
        guard session != nil, pixels.x.isFinite, pixels.y.isFinite else { return }
        pendingDrag += pixels
    }

    /// The stick, each axis from -1 to 1, held until changed. Up is positive Y.
    public func setStick(_ value: SIMD2<Float>) {
        stick = simd_clamp(value, SIMD2(repeating: -1), SIMD2(repeating: 1))
    }

    /// A later tip, from another random screen that may show. Nil without one.
    public func nextTip() -> String? {
        guard !tipScreens.isEmpty else { return text }
        let screen = tipScreens[Int(random.next() % UInt64(tipScreens.count))]
        return world?.loadingText(of: screen) ?? text
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
        guard session != nil else {
            if waitingSince != nil {
                presentFadeOut(at: time)
            }
            return
        }
        let seconds = lastTick.map { Float(min(max(time - $0, 0), Self.longestFrame)) } ?? 0
        lastTick = time
        steer(seconds: seconds)
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
            rotationDegrees: session.initialRotationDegrees,
            translation: record?.initialTranslation ?? .zero,
            turnRadians: session.turnRadians,
            fieldOfView: session.fieldOfView,
            cameraPath: record?.cameraPath,
            elapsedSeconds: session.elapsedSeconds(at: time),
            text: text,
            opacity: session.opacity(at: time),
            drawsObject: phase == .showing
        )
    }

    /// The game's rates: a drag turns by pixels times frame seconds times 0.02
    /// radians and zooms by pixels times frame seconds times 0.6; the stick turns
    /// by 0.45 radians and zooms by 5 per second.
    private func steer(seconds: Float) {
        let drag = pendingDrag
        pendingDrag = .zero
        let turn = drag.x * seconds * 0.02 - stick.x * 0.45 * seconds
        let zoom = drag.y * seconds * 0.6 - stick.y * 5 * seconds
        if turn != 0 {
            session?.turn(byRadians: turn)
        }
        if zoom != 0 {
            session?.changeFieldOfView(by: zoom)
        }
    }

    /// A stall longer than this counts as this long, so the object does not jump.
    static let longestFrame = 0.1

    private func presentFadeOut(at time: Double) {
        let opacity = fadeOut?.opacity(at: time) ?? 1
        guard opacity < 1 else {
            fadeOut = nil
            world?.presentLoadingCover(Self.darkFrame)
            return
        }
        world?.presentLoadingCover(LoadingCoverFrame(
            model: nil, scale: 1, rotationDegrees: .zero, translation: .zero,
            text: nil, opacity: opacity, drawsObject: false
        ))
    }

    private func start(_ next: LoadingScreenSession) {
        fadeOut = nil
        session = next
        lastTick = nil
        pendingDrag = .zero
        shownCount += 1
        text = next.screen.flatMap { world?.loadingText(of: $0) }
        world?.setLoadingPaused(true)
        tick(time: next.startedAt)
    }

    private func finish() {
        fadeOut = nil
        session = nil
        text = nil
        tipScreens = []
        stick = .zero
        world?.presentLoadingCover(nil)
        world?.setLoadingPaused(false)
    }

    private func pick(
        location: ResolvedFormID?, state: LoadScreenSelector.GameState = .gameLoaded
    ) -> ResolvedRecord<LoadScreen>? {
        guard let selector = selector(location: location) else { return nil }
        let candidates = selector.candidates(state)
        lastPassingCount = candidates.count
        tipScreens = candidates
        return LoadScreenSelector.pick(from: candidates, random: &random)
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

/// The view turning black before a door's load: linear from clear to black.
nonisolated struct FadeOut: Equatable, Sendable {
    let start: Double
    let seconds: Double

    func opacity(at time: Double) -> Float {
        guard seconds > 0 else { return 1 }
        return Float(min(1, max(0, (time - start) / seconds)))
    }
}
