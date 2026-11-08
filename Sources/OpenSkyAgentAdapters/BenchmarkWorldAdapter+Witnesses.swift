import Metal
import MetalKit
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySession
import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import QuartzCore
import simd

/// Witnesses that forward to the narrow parts of `BenchmarkWorldAdapter`.
extension BenchmarkWorldAdapter {
    public var activeSettings: [String: Double] {
        tourSettings.activeSettings
    }

    public func beginTour(overrides: [PlayerSettingID: Double], passTiming: Bool) {
        tourSettings.beginTour(overrides: overrides, passTiming: passTiming)
    }

    public func tourFinished(_ result: BenchmarkTourResult) {
        tourSettings.tourFinished(result)
    }

    public func endTour() {
        tourSettings.endTour()
    }

    public var loadInputs: BenchmarkLoadInputs? {
        tourSettings.loadInputs
    }
}
