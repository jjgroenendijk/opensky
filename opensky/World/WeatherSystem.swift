// Weather runtime state machine (M7.2.2): drives region/climate selection,
// timed current->target transitions, and the time-of-day blend, producing a
// ResolvedWeather + published WindState each frame. The renderer advances it
// from wall-clock delta + the time-of-day input and feeds ResolvedWeather into
// FrameUniforms; nil ResolvedWeather leaves the procedural sky untouched.
//
// Design + spec citations + deviations: docs/engine/weather.md.
//
// Threading: constructed on the cell-provider setup thread, then owned and
// mutated only by the renderer's main-thread draw loop (like the other
// renderer state). The WeatherStore it reads is immutable after construction.

import Foundation
import simd

nonisolated final class WeatherSystem {
    /// How a forced weather change arrives.
    enum Transition {
        /// Snap instantly (no blend) — tests + the UI "apply now" path.
        case instant
        /// Cross-fade over the target weather's derived transition duration.
        case timed
    }

    let store: WeatherStore
    let worldspaceFormID: UInt32?

    // MARK: Tuning constants (documented in docs/engine/weather.md)

    /// Auto reroll cadence in game-hours, accumulated from the time-of-day
    /// input. Chosen for a visible-but-not-frantic churn on a dev clock.
    static let rerollGameHours: Float = 6
    /// Fallback transition seconds when a weather has no DATA Trans Delta.
    static let defaultTransitionSeconds: Float = 10
    /// Trans Delta is clamped to this floor before inversion so a near-zero
    /// delta cannot produce an unbounded transition.
    static let minTransDelta: Float = 0.02

    // MARK: Selection + transition state

    /// XCLR regions of the current exterior cell; drives region selection.
    private(set) var currentRegions: [FormID] = []
    /// Forced weather override; nil = automatic selection.
    private(set) var forced: FormID?
    /// Reroll epoch — part of the deterministic pick seed.
    private var epoch: UInt64 = 0
    /// Settled source weather of the active blend (== `toWeather` when idle).
    private var fromWeather: FormID?
    /// Target weather the blend is moving toward.
    private var toWeather: FormID?
    /// 0 -> fully `fromWeather`, 1 -> fully `toWeather`.
    private var transitionProgress: Float = 1
    private var transitionDuration: Float = WeatherSystem.defaultTransitionSeconds
    private var gameHoursSinceRoll: Float = 0
    private var lastHour: Float?
    /// Cached resolve at the last update — recomputed only on update().
    private(set) var resolvedWeather: ResolvedWeather?

    init(store: WeatherStore, worldspaceFormID: UInt32?) {
        self.store = store
        self.worldspaceFormID = worldspaceFormID
        // Seed an initial automatic pick so the first frame already has weather.
        let initial = pickAutomatic()
        fromWeather = initial
        toWeather = initial
    }

    /// Convenience: resolve the store + worldspace from an ESM file by editor
    /// ID. Returns nil when the plugin carries no weather data at all.
    convenience init?(file: ESMFile, worldspaceEditorID: String) {
        let store = WeatherStore(file: file)
        guard !store.weathers.isEmpty else { return nil }
        self.init(
            store: store,
            worldspaceFormID: store.worldspaceByEditorID[worldspaceEditorID]
        )
    }

    // MARK: Published outputs

    /// Current published wind (blended across a transition). Calm when no
    /// weather is active.
    var currentWind: WindState {
        resolvedWeather?.wind ?? .calm
    }

    /// FormID of the weather being transitioned toward, nil when inactive.
    var currentWeatherID: FormID? {
        toWeather
    }

    var currentWeatherEditorID: String? {
        toWeather.flatMap { store.weather($0)?.editorID }
    }

    /// 0-1 progress of the active transition (1 when settled).
    var transitionFraction: Float {
        transitionProgress
    }

    // MARK: Inputs

    /// Feeds the current exterior cell's XCLR regions. A changed region set
    /// rerolls immediately (a new region may bring different weather), unless a
    /// weather is forced.
    func setRegions(_ regions: [FormID]) {
        guard regions != currentRegions else { return }
        currentRegions = regions
        guard forced == nil else { return }
        reroll(startTransition: true)
    }

    /// Forces `weather` (nil resumes automatic selection). Instant snaps;
    /// timed cross-fades over the derived duration.
    func forceWeather(_ weather: FormID?, transition: Transition) {
        forced = weather
        guard let weather else {
            // Resume auto: keep showing the settled weather, let rerolls take
            // over from here.
            gameHoursSinceRoll = 0
            return
        }
        beginTransition(to: weather, transition: transition)
    }

    /// Advances the transition by real `deltaTime` seconds and accumulates
    /// reroll game-hours from the change in `hour`, then recomputes the
    /// resolved blend. Cheap: two resolves + one lerp.
    func update(deltaTime: Float, hour: Float) {
        advanceTransition(deltaTime: max(0, deltaTime))
        accumulateGameHours(hour: hour)
        if forced == nil, gameHoursSinceRoll >= Self.rerollGameHours {
            gameHoursSinceRoll = 0
            reroll(startTransition: true)
        }
        recomputeResolved(hour: hour)
    }

    // MARK: Transition mechanics

    private func advanceTransition(deltaTime: Float) {
        guard transitionProgress < 1 else { return }
        let step = transitionDuration > 0 ? deltaTime / transitionDuration : 1
        transitionProgress = simd_clamp(transitionProgress + step, 0, 1)
        if transitionProgress >= 1 {
            fromWeather = toWeather
        }
    }

    private func accumulateGameHours(hour: Float) {
        defer { lastHour = hour }
        guard let last = lastHour else { return }
        var delta = hour - last
        // Forward-wrap: a decrease means the clock rolled past midnight (or was
        // scrubbed forward). Clamp into a single day to bound scrub jumps.
        if delta < 0 {
            delta += 24
        }
        gameHoursSinceRoll += simd_clamp(delta, 0, 24)
    }

    private func reroll(startTransition: Bool) {
        epoch &+= 1
        guard let next = pickAutomatic() else { return }
        if startTransition {
            beginTransition(to: next, transition: .timed)
        } else {
            fromWeather = next
            toWeather = next
            transitionProgress = 1
        }
    }

    private func beginTransition(to weather: FormID, transition: Transition) {
        // Settle any in-flight blend to its current visual before starting the
        // next, so back-to-back changes never pop.
        let source = transitionProgress >= 1 ? toWeather : fromWeather
        switch transition {
        case .instant:
            fromWeather = weather
            toWeather = weather
            transitionProgress = 1
        case .timed:
            guard weather != toWeather || transitionProgress < 1 else { return }
            fromWeather = source ?? weather
            toWeather = weather
            transitionProgress = (source == nil) ? 1 : 0
            transitionDuration = transitionSeconds(for: weather)
        }
    }

    /// Trans Delta (0-0.25) as an inverse rate: full 0->1 blend takes
    /// 1/clamp(delta) seconds. Delta 0.25 -> 4 s, 0.1 -> 10 s, floor -> 50 s.
    /// The exact game time-unit of Trans Delta is unconfirmed in open specs;
    /// this interpretation is documented as a deviation in docs/engine/weather.md.
    private func transitionSeconds(for weather: FormID) -> Float {
        guard let delta = store.weather(weather)?.data?.transDelta, delta > 0 else {
            return Self.defaultTransitionSeconds
        }
        return 1 / max(Self.minTransDelta, delta)
    }

    private func pickAutomatic() -> FormID? {
        let pool = WeatherSelection.candidates(
            worldspace: worldspaceFormID,
            regionIDs: currentRegions,
            store: store
        )
        let seed = (UInt64(worldspaceFormID ?? 0) << 32) ^ epoch &* 0x2545_F491_4F6C_DD1D
        return WeatherSelection.pick(from: pool, seed: seed)
    }

    private func recomputeResolved(hour: Float) {
        guard let toWeather, let toRecord = store.weather(toWeather) else {
            resolvedWeather = nil
            return
        }
        let timing = climateTiming()
        let target = ResolvedWeather.resolve(toRecord, hour: hour, timing: timing)
        guard
            transitionProgress < 1,
            let fromWeather,
            let fromRecord = store.weather(fromWeather)
        else {
            resolvedWeather = target
            return
        }
        let source = ResolvedWeather.resolve(fromRecord, hour: hour, timing: timing)
        // Smoothstep the blend factor for an eased cross-fade.
        let time = transitionProgress * transitionProgress * (3 - 2 * transitionProgress)
        resolvedWeather = ResolvedWeather.blend(source, target, time)
    }

    private func climateTiming() -> Climate.Timing? {
        guard
            let worldspaceFormID,
            let climateID = store.worldspaceClimate[worldspaceFormID]
        else { return nil }
        return store.climate(climateID)?.timing
    }
}
