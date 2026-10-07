// Which GPUs run the ray-traced shadows, which geometry they trace against, and when the
// acceleration structures are built or freed.

import OpenSkyRendering
import Testing

struct RayTracingAvailabilityTests {
    @Test func hardwareRayTracingIsAvailable() {
        let availability = RayTracingAvailability.check(
            supportsRayTracing: true, hardwareRayTracing: true
        )
        #expect(availability.isAvailable)
        #expect(availability.reason == nil)
    }

    @Test func softwareRayTracingSaysWhy() {
        let availability = RayTracingAvailability.check(
            supportsRayTracing: true, hardwareRayTracing: false
        )
        #expect(!availability.isAvailable)
        #expect(availability.reason == RayTracingAvailability.softwareReason)
    }

    @Test func noRayTracingSaysWhy() {
        let availability = RayTracingAvailability.check(
            supportsRayTracing: false, hardwareRayTracing: false
        )
        #expect(availability.reason == RayTracingAvailability.missingReason)
    }
}

struct RayTracingScenePlanTests {
    @Test func onlyRigidOpaqueCastersGoIn() {
        #expect(RayTracingScenePlan.includes(RayTracingCaster()))
        var caster = RayTracingCaster()
        caster.castsShadows = false
        #expect(!RayTracingScenePlan.includes(caster))
        for change in [
            { (caster: inout RayTracingCaster) in caster.isSkinned = true },
            { (caster: inout RayTracingCaster) in caster.isMorphed = true },
            { (caster: inout RayTracingCaster) in caster.isAlphaTested = true },
            { (caster: inout RayTracingCaster) in caster.isMoved = true }
        ] {
            var excluded = RayTracingCaster()
            change(&excluded)
            #expect(!RayTracingScenePlan.includes(excluded))
        }
    }

    @Test func aNewSceneBuildsAndTurningOffFrees() {
        #expect(RayTracingScenePlan.action(active: true, built: false, current: false) == .build)
        #expect(RayTracingScenePlan.action(active: true, built: true, current: false) == .build)
        #expect(RayTracingScenePlan.action(active: true, built: true, current: true) == .none)
        #expect(RayTracingScenePlan.action(active: false, built: true, current: true) == .release)
        #expect(RayTracingScenePlan.action(active: false, built: false, current: false) == .none)
    }
}
