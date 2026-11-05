// Short lights and models: a projectile's muzzle flash and an explosion's light.
// See docs/engine/spell-delivery.md#what-a-projectile-shows.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import simd

/// One `LIGH` shown at a point for a while; it fades out over its time.
nonisolated public struct FlashLight: Equatable, Sendable {
    public let light: ReferenceKey
    public let position: SIMD3<Float>
    public let duration: Float
    public var elapsed: Float = 0

    /// 1 at the start, 0 at the end; OpenSky's fade.
    public var strength: Float {
        duration > 0 ? max(0, 1 - elapsed / duration) : 0
    }
}

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
        model: String?, light: ReferenceKey?,
        at position: SIMD3<Float>, along direction: SIMD3<Float>, duration: Float
    ) {
        if let model {
            showModel(
                model, at: .facing(position, forward: direction), cause: .casting,
                duration: duration
            )
        }
        if let key = light {
            addFlashLight(key, at: position, duration: duration)
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
