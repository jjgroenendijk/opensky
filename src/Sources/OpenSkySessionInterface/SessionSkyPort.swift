import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The resolved weather, sky, fog, and script particles. Part of `GameSessionPort`.
public protocol SessionSkyPort: AnyObject {
    var celestialSky: CelestialSky? { get }
    var currentResolvedWeather: ResolvedWeather? { get }
    var interiorFogOverride: InteriorFogOverride? { get set }
    var scriptParticles: ScriptParticleGeometry { get set }
    var imageSpaceLinks: ImageSpaceLinks? { get }
}
