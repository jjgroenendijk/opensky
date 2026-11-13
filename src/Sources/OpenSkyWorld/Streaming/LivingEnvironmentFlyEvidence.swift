// Peak live-system evidence collected across production fly frames.

import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyWeather

nonisolated struct LivingEnvironmentFlyEvidence: Sendable {
    var grassDrawStats = GrassDrawStats()
    var shadowDrawStats = ShadowDrawStats()
    var animationUpdatedBoneCount = 0
    var particleSystemCount = 0
    var particleLiveCount = 0
    var rainLiveCount = 0
    var weatherName: String?
    var windSpeed: Float = 0

    @MainActor
    mutating func capture(_ gameSession: GameSession) {
        let renderer = gameSession.renderer
        grassDrawStats.formMaximum(renderer.lastGrassDrawStats)
        shadowDrawStats.formMaximum(renderer.combinedShadowDrawStats)
        animationUpdatedBoneCount = max(
            animationUpdatedBoneCount,
            renderer.lastAnimationUpdatedBoneCount
        )
        let particles = renderer.scene.particles
        particleSystemCount = max(particleSystemCount, particles.count)
        particleLiveCount = max(
            particleLiveCount,
            particles.reduce(0) { $0 + $1.liveCount }
        )
        rainLiveCount = max(rainLiveCount, renderer.precipitation.snapshot.rainLiveCount)
        if gameSession.sky.currentResolvedWeather != nil {
            weatherName = gameSession.weather?.currentWeatherEditorID ?? "selected rain"
        }
        windSpeed = max(windSpeed, gameSession.wind.speed)
    }

    func validated(animatedActorCount: Int) throws -> LivingEnvironmentFlyEvidence {
        guard weatherName != nil else {
            throw CellStreamingFlyBenchmarkError.noWeatherRendered
        }
        guard animatedActorCount > 0, animationUpdatedBoneCount > 0 else {
            throw CellStreamingFlyBenchmarkError.noActorAnimationUpdated
        }
        guard particleSystemCount > 0, particleLiveCount > 0 else {
            throw CellStreamingFlyBenchmarkError.noParticlesRendered
        }
        guard rainLiveCount > 0 else {
            throw CellStreamingFlyBenchmarkError.noPrecipitationRendered
        }
        guard shadowDrawStats.cascadesRendered > 0, shadowDrawStats.drawnInstances > 0 else {
            throw CellStreamingFlyBenchmarkError.noShadowsRendered
        }
        guard grassDrawStats.drawnInstances > 0 else {
            throw CellStreamingFlyBenchmarkError.noGrassRendered
        }
        guard grassDrawStats.budgetDroppedInstances == 0 else {
            throw CellStreamingFlyBenchmarkError.grassBudgetExceeded(
                dropped: grassDrawStats.budgetDroppedInstances
            )
        }
        return self
    }
}
