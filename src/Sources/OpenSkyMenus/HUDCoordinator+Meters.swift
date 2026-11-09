import OpenSkyFormatsSWF
public import OpenSkyGameData
public import OpenSkyMenusInterface

extension HUDCoordinator {
    /// Sends the meters and the enemy bar to the movie, each only when it changed,
    /// because each call dirties the movie. `meters` are fractions of full.
    public func publishMeters(_ meters: ActorValues, enemy: HUDEnemyHealth?) {
        let sample = HUDMeterValues(
            health: meters.health, magicka: meters.magicka, stamina: meters.stamina
        )
        let changedMeters = meterBinding.publishing(sample)
        let enemyChanged = enemy != publishedEnemy
        guard changedMeters != nil || enemyChanged else { return }
        publishedEnemy = enemy
        callMovie { runtime in
            if let changedMeters {
                HUDMovieBridge.setMeters(changedMeters, runtime: runtime)
            }
            if enemyChanged {
                HUDMovieBridge.setEnemyHealth(enemy, runtime: runtime)
            }
        }
    }
}
