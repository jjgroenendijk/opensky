// The `SPGD` the current weather blend names, for the precipitation volumes,
// and its `VOLI` for the readout.
// See docs/formats/environment-shading.md, section "Precipitation mapping".

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

nonisolated extension WeatherSystem {
    /// The `MNAM` record of the heaviest weather in the blend that names one.
    public func precipitationParticles(
        in records: EffectRecordStore,
        plugin: String
    ) -> ShaderParticleGeometry? {
        blendedWeathers.sorted { $0.weight > $1.weight }
            .lazy
            .compactMap { self.store.weather($0.weather)?.sky.precipitation }
            .compactMap { records.shaderParticles.resolve($0, fromPlugin: plugin)?.record }
            .first
    }
}
