// M7.6 peak live-system evidence collected across production fly frames.

nonisolated public struct LivingEnvironmentFlyEvidence: Sendable {
    public var grassDrawStats = GrassDrawStats()
    public var shadowDrawStats = ShadowDrawStats()
    public var animationUpdatedBoneCount = 0
    public var particleSystemCount = 0
    public var particleLiveCount = 0
    public var rainLiveCount = 0
    public var weatherName: String?
    public var windSpeed: Float = 0

    @MainActor
    public mutating func capture(_ renderer: Renderer) {
        grassDrawStats.formMaximum(renderer.lastGrassDrawStats)
        shadowDrawStats.formMaximum(renderer.lastShadowDrawStats)
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
        if renderer.currentResolvedWeather != nil {
            weatherName = renderer.weather?.currentWeatherEditorID ?? "selected rain"
        }
        windSpeed = max(windSpeed, renderer.currentWind.speed)
    }

    public func validated(animatedActorCount: Int) throws -> LivingEnvironmentFlyEvidence {
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
