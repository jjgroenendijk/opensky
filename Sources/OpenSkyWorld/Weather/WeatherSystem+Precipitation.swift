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

    /// The editor ID of the `HNAM` record the heaviest weather names for the
    /// time-of-day slot that weighs most at `hour`.
    public func volumetricLighting(
        in records: EffectRecordStore,
        plugin: String,
        hour: Float
    ) -> String? {
        guard
            let heaviest = blendedWeathers.max(by: { $0.weight < $1.weight }),
            let slots = store.weather(heaviest.weather)?.sky.volumetricLighting
        else { return nil }
        let weights = timeOfDayWeights(hour: hour)
        let slot = [
            (weights.sunrise, slots.sunrise), (weights.day, slots.day),
            (weights.sunset, slots.sunset), (weights.night, slots.night)
        ].max { $0.0 < $1.0 }.flatMap(\.1)
        return records.volumetricLighting.resolve(slot, fromPlugin: plugin).map {
            $0.record.editorID ?? "\($0.id)"
        }
    }
}
