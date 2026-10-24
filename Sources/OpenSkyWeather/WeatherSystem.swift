// Weather runtime: region and climate selection, timed transitions, and the time-of-day
// blend, giving a `ResolvedWeather` and `WindState` each frame. Owned by the main-thread
// draw loop. See docs/engine/weather.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyShaderTypes
import OpenSkyWorldState
import simd

nonisolated public final class WeatherSystem {
    /// How a forced weather change arrives.
    public enum Transition: Sendable {
        /// Snap instantly (no blend) — tests + the UI "apply now" path.
        case instant
        /// Cross-fade over the target weather's derived transition duration.
        case timed
    }

    public let store: WeatherStore
    public private(set) var worldspaceFormID: UInt32?

    // MARK: Tuning constants (documented in docs/engine/weather.md)

    /// Reroll cadence in game hours at `baseVolatility`, and for a climate without `TNAM`.
    public static let rerollGameHours: Float = 6
    /// The `SkyrimClimate` volatility, which keeps the six-hour cadence.
    public static let baseVolatility: Float = 50

    // MARK: Selection + transition state

    /// XCLR regions of the current exterior cell; drives region selection.
    public private(set) var currentRegions: [FormID] = []
    /// Forced weather override; nil = automatic selection.
    public private(set) var forced: FormID?
    /// Reroll epoch — part of the deterministic pick seed.
    private var epoch: UInt64 = 0
    /// Settled source weather of the active blend (== `toWeather` when idle).
    private var fromWeather: FormID?
    /// Target weather the blend is moving toward.
    private var toWeather: FormID?
    /// 0 -> fully `fromWeather`, 1 -> fully `toWeather`.
    private var transitionProgress: Float = 1
    private var transitionGameHours: Float = 0
    private var gameHoursSinceRoll: Float = 0
    /// Cached resolve at the last update — recomputed only on update().
    public private(set) var resolvedWeather: ResolvedWeather?
    /// Freezes only weather cross-fade progress. Time-of-day resolution and
    /// precipitation particle playback continue, enabling a stable mid-storm
    /// inspection frame in the main app.
    public var transitionsPaused = false
    /// Current globals, for the CLMT WLST global on each weather chance. Nil keeps the
    /// authored chances. Replaced by `setGlobalResolution(_:)`.
    public private(set) var globalResolution: GlobalResolution?

    public init(store: WeatherStore, worldspaceFormID: UInt32?) {
        self.store = store
        self.worldspaceFormID = worldspaceFormID
        // Seed an initial automatic pick so the first frame already has weather.
        let initial = pickAutomatic()
        fromWeather = initial
        toWeather = initial
    }

    /// Convenience: resolve the store + worldspace from an ESM file by editor
    /// ID. Returns nil when the plugin carries no weather data at all.
    public convenience init?(file: ESMFile, worldspaceEditorID: String) {
        self.init(loadOrder: LoadOrderPlugins(file: file), worldspaceEditorID: worldspaceEditorID)
    }

    public convenience init?(loadOrder: LoadOrderPlugins, worldspaceEditorID: String) {
        let store = WeatherStore(loadOrder: loadOrder)
        guard !store.weathers.isEmpty else { return nil }
        self.init(
            store: store,
            worldspaceFormID: store.worldspaceByEditorID[worldspaceEditorID]
        )
    }

    // MARK: Published outputs

    /// Current published wind (blended across a transition). Calm when no
    /// weather is active.
    public var currentWind: WindState {
        resolvedWeather?.wind ?? .calm
    }

    /// FormID of the weather being transitioned toward, nil when inactive.
    public var currentWeatherID: FormID? {
        toWeather
    }

    /// The weather an unfinished blend moves away from; nil when settled.
    public var outgoingWeatherID: FormID? {
        guard transitionProgress < 1, fromWeather != toWeather else { return nil }
        return fromWeather
    }

    public var currentWeatherEditorID: String? {
        toWeather.flatMap { store.weather($0)?.editorID }
    }

    /// 0-1 progress of the active transition (1 when settled).
    public var transitionFraction: Float {
        transitionProgress
    }

    /// The weathers the current look blends, with the eased weights the sky uses.
    public var blendedWeathers: [(weather: FormID, weight: Float)] {
        guard let toWeather else { return [] }
        guard transitionProgress < 1, let fromWeather, fromWeather != toWeather else {
            return [(toWeather, 1)]
        }
        let time = transitionProgress * transitionProgress * (3 - 2 * transitionProgress)
        return [(fromWeather, 1 - time), (toWeather, time)]
    }

    /// The four time-of-day weights at `hour` under this worldspace's climate.
    public func timeOfDayWeights(hour: Float) -> TimeOfDayWeights {
        TimeOfDayWeights(hour: hour, timing: climateTiming())
    }

    // MARK: Inputs

    /// Feeds the current exterior cell's XCLR regions. A changed region set
    /// rerolls immediately (a new region may bring different weather), unless a
    /// weather is forced.
    public func setRegions(_ regions: [FormID]) {
        guard regions != currentRegions else { return }
        currentRegions = regions
        guard forced == nil else { return }
        reroll(startTransition: true)
    }

    /// A new worldspace brings its own climate, so the weather snaps to a new pick
    /// unless one is forced.
    public func setWorldspace(editorID: String) {
        let formID = store.worldspaceByEditorID[editorID]
        guard formID != worldspaceFormID else { return }
        worldspaceFormID = formID
        currentRegions = []
        guard forced == nil, let weather = pickAutomatic() else { return }
        gameHoursSinceRoll = 0
        beginTransition(to: weather, transition: .instant)
    }

    /// Adopts new global values and, unless a weather is forced, rerolls so the
    /// changed chances are visible immediately rather than at the next
    /// six-game-hour boundary. That is what makes a mutated weather-chance
    /// global observable in the running app.
    public func setGlobalResolution(
        _ resolution: GlobalResolution?,
        reroll shouldReroll: Bool = true
    ) {
        globalResolution = resolution
        guard shouldReroll, forced == nil else { return }
        gameHoursSinceRoll = 0
        reroll(startTransition: true)
    }

    /// Forces `weather` (nil resumes automatic selection). Instant snaps;
    /// timed cross-fades over the derived duration.
    public func forceWeather(_ weather: FormID?, transition: Transition) {
        forced = weather
        guard let weather else {
            // Resume auto: keep showing the settled weather, let rerolls take
            // over from here.
            gameHoursSinceRoll = 0
            return
        }
        beginTransition(to: weather, transition: transition)
    }

    /// Starts `weather` without holding it, so the next reroll may replace it. A forced
    /// weather wins, as an override does in the game.
    public func startWeather(_ weather: FormID, transition: Transition) {
        guard forced == nil else { return }
        gameHoursSinceRoll = 0
        beginTransition(to: weather, transition: transition)
    }

    /// The weathers the current regions and climate may pick, for `Weather.FindWeather`.
    public func candidateWeathers() -> [FormID] {
        WeatherSelection.candidates(
            worldspace: worldspaceFormID, regionIDs: currentRegions, store: store,
            globals: globalResolution
        ).map(\.weather)
    }

    /// Advances the fade and the reroll timer by `elapsedGameHours`, then resolves the
    /// blend at `hour`. A still clock neither fades nor rerolls.
    public func update(hour: Float, elapsedGameHours: Float = 0) {
        let elapsed = elapsedGameHours.isFinite ? max(0, elapsedGameHours) : 0
        advanceTransition(gameHours: elapsed)
        gameHoursSinceRoll += elapsed
        if forced == nil, let interval = rerollInterval, gameHoursSinceRoll >= interval {
            gameHoursSinceRoll = 0
            reroll(startTransition: true)
        }
        recomputeResolved(hour: hour)
    }

    /// Game hours between automatic rerolls under the current climate's volatility; nil
    /// for a volatility of 0, whose weather changes only with the region or a script.
    public var rerollInterval: Float? {
        guard let volatility = climateTiming()?.volatility else { return Self.rerollGameHours }
        guard volatility > 0 else { return nil }
        return Self.rerollGameHours * Self.baseVolatility / Float(volatility)
    }

    // MARK: Transition mechanics

    private func advanceTransition(gameHours: Float) {
        guard !transitionsPaused, transitionProgress < 1 else { return }
        let step = transitionGameHours > 0 ? gameHours / transitionGameHours : 1
        transitionProgress = simd_clamp(transitionProgress + step, 0, 1)
        if transitionProgress >= 1 {
            fromWeather = toWeather
        }
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
            toWeather = weather
            transitionGameHours = store.weather(weather)?.data?.transDelta ?? 0
            // Trans Delta is the fade's length in game hours, so 0 switches at once.
            let fades = source != nil && transitionGameHours > 0
            fromWeather = fades ? source : weather
            transitionProgress = fades ? 0 : 1
        }
    }

    private func pickAutomatic() -> FormID? {
        let pool = WeatherSelection.candidates(
            worldspace: worldspaceFormID,
            regionIDs: currentRegions,
            store: store,
            globals: globalResolution
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
