// Short lights and models: a projectile's muzzle flash and an explosion's light.
// See docs/engine/spell-delivery.md#what-a-projectile-shows.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
public import OpenSkyWorldInterface
import simd

extension EffectsCoordinator {
    /// At most this many flash lights live; the oldest goes first. OpenSky's limit.
    public static let flashLightLimit = 8

    public func addFlashLight(_ light: ReferenceKey, at position: SIMD3<Float>, duration: Float) {
        guard duration.isFinite, duration > 0 else { return }
        flashLights.append(FlashLight(light: light, position: position, duration: duration))
        if flashLights.count > Self.flashLightLimit {
            flashLights.removeFirst(flashLights.count - Self.flashLightLimit)
        }
    }

    /// The `NAM1` model along the shot, and the muzzle light, for the flash's time.
    public func showMuzzleFlash(
        _ flash: MuzzleFlash, at position: SIMD3<Float>, along direction: SIMD3<Float>
    ) {
        if let model = flash.model {
            showModel(
                model, at: .facing(position, forward: direction), cause: .casting,
                duration: flash.duration
            )
        }
        if let key = flash.light {
            addFlashLight(key, at: position, duration: flash.duration)
        }
    }

    func ageFlashLights(_ seconds: Float) {
        guard seconds > 0 else { return }
        for index in flashLights.indices {
            flashLights[index].elapsed += seconds
        }
        flashLights.removeAll { $0.elapsed >= $0.duration }
    }
}
