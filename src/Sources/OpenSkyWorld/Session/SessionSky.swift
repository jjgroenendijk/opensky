// Part of the `GameSession` state, held in one object so the session port can name it.

import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWeather
public import OpenSkyWorldInterface
import simd

/// The resolved weather, sky, fog, and particle state of a session, and their clock.
public final class SessionSky {
    /// A script's fog for the loaded interior; ignored once the scene's lighting changes.
    public var interiorFogOverride: InteriorFogOverride?
    /// This frame's resolved weather (exterior only). nil -> no weather active.
    public internal(set) var currentResolvedWeather: ResolvedWeather?
    /// This frame's sun, moons, stars, and aurora; nil whenever the weather is.
    public internal(set) var celestialSky: CelestialSky?
    /// The GMSTs the celestial sky reads; vanilla values until weather is attached.
    public var skySettings = SkySettings.vanilla
    /// The weather's rain or snow particles; nil until the weather links are wired.
    public internal(set) var precipitationTuning: PrecipitationTuning?
    /// The precipitation a script applied with `ShaderParticleGeometry.Apply`.
    public var scriptParticles = ScriptParticleGeometry()
    /// Data-driven sky/fog/light/wind + precipitation-input A/B.
    public var weatherEnabled = true
    /// Wall-clock delta source for the weather runtime, paused in menu mode.
    public var weatherClock = FrameSimClock()
    /// Where the baseline image space comes from; nil leaves the frame ungraded.
    public var imageSpaceLinks: ImageSpaceLinks?

    public init() {}
}
