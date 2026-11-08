// The `PlayImpactEffect` pick: the nearer of the static hit and the terrain.

@testable import OpenSkyCombat
import OpenSkyFormatsESM
import Testing

struct ImpactPickTests {
    private let flatGround: (SIMD2<Float>) -> (height: Float, material: FormID?)? = { _ in
        (0, FormID(0x10))
    }

    @Test func aDownwardPickMeetsTheGround() {
        let hit = ImpactPick.resolve(
            origin: [5, 6, 100], direction: [0, 0, -2], length: 512,
            staticHit: nil, terrain: flatGround
        )
        #expect(hit == ImpactPickHit(position: [5, 6, 0], material: FormID(0x10)))
    }

    @Test func aNearerStaticWinsAndAShortPickMisses() {
        let rock = ImpactPickHit(position: [0, 0, 50], material: FormID(0x20))
        #expect(ImpactPick.resolve(
            origin: [0, 0, 100], direction: [0, 0, -1], length: 512,
            staticHit: (50, rock), terrain: flatGround
        ) == rock)
        #expect(ImpactPick.resolve(
            origin: [0, 0, 100], direction: [0, 0, -1], length: 20,
            staticHit: nil, terrain: flatGround
        ) == nil)
        #expect(ImpactPick.resolve(
            origin: .zero, direction: .zero, length: 512, staticHit: nil, terrain: flatGround
        ) == nil)
    }
}
